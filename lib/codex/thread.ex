defmodule Codex.Thread do
  @moduledoc """
  Represents a Codex conversation thread and exposes turn execution APIs.
  """

  alias Codex.AgentRunner
  alias Codex.ApprovalError
  alias Codex.Approvals
  alias Codex.Error
  alias Codex.Events
  alias Codex.GuardrailError
  alias Codex.Items
  alias Codex.Models
  alias Codex.Options
  alias Codex.OutputSchemaFile
  alias Codex.RunResultStreaming
  alias Codex.Telemetry
  alias Codex.Thread.Backoff
  alias Codex.Thread.Options, as: ThreadOptions
  alias Codex.ToolGuardrail
  alias Codex.ToolOutput
  alias Codex.Tools
  alias Codex.Turn.Result

  @enforce_keys [:codex_opts, :thread_opts]
  defstruct thread_id: nil,
            codex_opts: nil,
            thread_opts: nil,
            metadata: %{},
            labels: %{},
            resume: nil,
            continuation_token: nil,
            usage: %{},
            rate_limits: nil,
            pending_tool_outputs: [],
            pending_tool_failures: [],
            transport: :exec,
            transport_ref: nil

  @type t :: %__MODULE__{
          thread_id: String.t() | nil,
          codex_opts: Options.t(),
          thread_opts: ThreadOptions.t(),
          metadata: map(),
          labels: map(),
          resume: :last | nil,
          continuation_token: String.t() | nil,
          usage: map(),
          rate_limits: Codex.Protocol.RateLimit.Snapshot.t() | map() | nil,
          pending_tool_outputs: [map()],
          pending_tool_failures: [map()],
          transport: :exec | {:app_server, pid()},
          transport_ref: reference() | nil
        }

  @doc false
  @spec build(Options.t(), ThreadOptions.t(), keyword()) :: t()
  def build(%Options{} = opts, %ThreadOptions{} = thread_opts, extra \\ []) do
    transport = thread_opts.transport || :exec

    struct!(
      __MODULE__,
      Keyword.merge(
        [
          thread_id: nil,
          codex_opts: opts,
          thread_opts: thread_opts,
          metadata: %{},
          labels: %{},
          resume: nil,
          continuation_token: nil,
          usage: %{},
          rate_limits: nil,
          pending_tool_outputs: [],
          pending_tool_failures: [],
          transport: transport,
          transport_ref: nil
        ],
        extra
      )
    )
  end

  @doc false
  @spec clear_pending_tool_payloads(t()) :: t()
  def clear_pending_tool_payloads(%__MODULE__{} = thread) do
    %{thread | pending_tool_outputs: [], pending_tool_failures: []}
  end

  @type user_input_block :: map()
  @type user_input :: String.t() | [user_input_block()]

  @doc """
  Executes a blocking multi-turn run using the agent runner.
  """
  @spec run(t(), user_input(), map() | keyword()) ::
          {:ok, Result.t()} | {:error, term()}
  def run(thread, input, opts \\ %{})

  def run(%__MODULE__{} = thread, input, opts)
      when is_binary(input) or is_list(input) do
    AgentRunner.run(thread, input, opts)
  end

  def run(%__MODULE__{}, input, _opts), do: {:error, {:invalid_input, input}}

  @doc false
  @spec run_turn(t(), user_input(), map() | keyword()) ::
          {:ok, Result.t()} | {:error, term()}
  def run_turn(thread, input, turn_opts \\ %{})

  def run_turn(%__MODULE__{} = thread, input, turn_opts)
      when is_binary(input) or is_list(input) do
    thread = maybe_reset_for_new(thread, input)

    case transport_impl(thread) do
      {:error, _} = error -> error
      transport -> transport.run_turn(thread, input, turn_opts)
    end
  end

  def run_turn(%__MODULE__{}, input, _turn_opts), do: {:error, {:invalid_input, input}}

  @doc false
  @spec run_turn_exec_jsonl(t(), String.t(), map() | keyword()) ::
          {:ok, Result.t()} | {:error, term()}
  def run_turn_exec_jsonl(%__MODULE__{} = thread, input, turn_opts \\ %{})
      when is_binary(input) do
    thread = maybe_reset_for_new(thread, input)
    span_token = make_ref()

    meta =
      %{
        thread_id: thread.thread_id,
        input: input,
        originator: :sdk,
        span_token: span_token
      }
      |> maybe_put(:source, extract_source(thread.metadata))
      |> maybe_put(:workflow, extract_trace(thread.metadata, :workflow))
      |> maybe_put(:group, extract_trace(thread.metadata, :group))
      |> maybe_put(:trace_id, extract_trace(thread.metadata, :trace_id))
      |> maybe_put(:trace_sensitive, extract_trace(thread.metadata, :trace_sensitive))
      |> maybe_put(:tracing_disabled, extract_trace(thread.metadata, :tracing_disabled))
      |> maybe_put(:conversation_id, extract_trace(thread.metadata, :conversation_id))
      |> maybe_put(:previous_response_id, extract_trace(thread.metadata, :previous_response_id))

    Telemetry.emit([:codex, :thread, :start], %{system_time: System.system_time()}, meta)
    started_monotonic = System.monotonic_time()

    with {:ok, exec_opts, cleanup, exec_meta} <- build_exec_options(thread, turn_opts) do
      structured_output? = Map.get(exec_meta, :structured_output?, false)

      try do
        case Codex.Exec.run(input, exec_opts) do
          {:ok, %{events: events} = exec_result} ->
            duration = System.monotonic_time() - started_monotonic
            failure = extract_turn_failure(events)
            early_exit? = early_exit?(events)
            identifiers = extract_thread_context(events, thread)
            progress_meta = merge_metadata(meta, identifiers)

            emit_progress_events(events, progress_meta)

            Telemetry.emit(
              [:codex, :thread, :stop],
              %{duration: duration, system_time: System.system_time()},
              progress_meta
              |> Map.put(:result, telemetry_result(failure, early_exit?))
              |> maybe_put(:error, failure_meta(failure))
              |> maybe_put(:early_exit?, early_exit?)
            )

            exec_result =
              exec_result
              |> Map.put(:structured_output?, structured_output?)
              |> Map.put(:pruned?, early_exit?)

            result = finalize_turn(thread, exec_result, exec_meta)

            case failure do
              {:error, err} -> {:error, {:turn_failed, err}}
              :ok -> {:ok, result}
            end

          {:error, reason} ->
            duration = System.monotonic_time() - started_monotonic
            error = Error.normalize(reason)

            Telemetry.emit(
              [:codex, :thread, :exception],
              %{duration: duration, system_time: System.system_time()},
              merge_metadata(meta, %{
                thread_id: thread.thread_id,
                source: extract_source(thread.metadata)
              })
              |> Map.put(:reason, error)
              |> Map.put(:result, :error)
            )

            {:error, {:exec_failed, error}}
        end
      after
        cleanup.()
      end
    end
  end

  @doc """
  Executes a run and returns a stream of events for progressive consumption.

  The stream is lazy; events will not be produced until enumerated.
  """
  @spec run_streamed(t(), user_input(), map() | keyword()) ::
          {:ok, RunResultStreaming.t()} | {:error, term()}
  def run_streamed(thread, input, opts \\ %{})

  def run_streamed(%__MODULE__{} = thread, input, opts)
      when is_binary(input) or is_list(input) do
    AgentRunner.run_streamed(thread, input, opts)
  end

  def run_streamed(%__MODULE__{}, input, _opts), do: {:error, {:invalid_input, input}}

  @doc false
  @spec run_turn_streamed(t(), user_input(), map() | keyword()) ::
          {:ok, Enumerable.t()} | {:error, term()}
  def run_turn_streamed(thread, input, turn_opts \\ %{})

  def run_turn_streamed(%__MODULE__{} = thread, input, turn_opts)
      when is_binary(input) or is_list(input) do
    thread = maybe_reset_for_new(thread, input)

    case transport_impl(thread) do
      {:error, _} = error -> error
      transport -> transport.run_turn_streamed(thread, input, turn_opts)
    end
  end

  def run_turn_streamed(%__MODULE__{}, input, _turn_opts), do: {:error, {:invalid_input, input}}

  @doc false
  @spec run_turn_streamed_exec_jsonl(t(), String.t(), map() | keyword()) ::
          {:ok, Enumerable.t()} | {:error, term()}
  def run_turn_streamed_exec_jsonl(%__MODULE__{} = thread, input, turn_opts \\ %{})
      when is_binary(input) do
    turn_opts_map = Map.new(turn_opts)
    schema = Map.get(turn_opts_map, :output_schema, Map.get(turn_opts_map, "output_schema"))

    with {:ok, encoded_schema} <- OutputSchemaFile.encode(schema) do
      stream =
        Stream.resource(
          fn ->
            %{
              phase: :init,
              thread: thread,
              input: input,
              turn_opts: turn_opts_map,
              encoded_schema: encoded_schema,
              meta: nil,
              progress_meta: nil,
              context: nil,
              started_monotonic: nil,
              failure: :ok,
              early_exit?: false,
              completed?: false,
              cleanup: nil,
              structured_output?: false,
              exec_stream: nil,
              exec_continuation: nil
            }
          end,
          &next_streamed_exec_event/1,
          &after_streamed_exec/1
        )

      {:ok, stream}
    end
  end

  defp next_streamed_exec_event(%{phase: :init} = state) do
    case start_streamed_exec(state) do
      {:ok, started_state} -> next_streamed_exec_event(started_state)
      {:error, reason, _state} -> raise_stream_error(Error.normalize(reason))
    end
  end

  defp next_streamed_exec_event(%{phase: :running} = state) do
    case next_exec_event(state) do
      {:halt, halted_state} ->
        {:halt, halted_state}

      {[event], updated_state} ->
        decoded = maybe_decode_stream_event(event, updated_state.structured_output?)

        state_with_context = update_stream_context(updated_state, decoded)

        progress_meta =
          state_with_context.progress_meta
          |> merge_metadata(state_with_context.context)

        emit_progress_event(decoded, progress_meta)

        next_state = update_stream_status(state_with_context, decoded)

        {[decoded], next_state}
    end
  end

  defp after_streamed_exec(state) do
    maybe_cleanup_stream(state)
    maybe_emit_stream_stop(state)
  end

  defp maybe_cleanup_stream(%{cleanup: cleanup}) when is_function(cleanup, 0) do
    cleanup.()
    :ok
  end

  defp maybe_cleanup_stream(_), do: :ok

  defp start_streamed_exec(state) do
    thread = maybe_reset_for_new(state.thread, state.input)
    span_token = make_ref()

    meta =
      %{
        thread_id: thread.thread_id,
        input: state.input,
        originator: :sdk,
        span_token: span_token
      }
      |> maybe_put(:source, extract_source(thread.metadata))
      |> maybe_put(:workflow, extract_trace(thread.metadata, :workflow))
      |> maybe_put(:group, extract_trace(thread.metadata, :group))
      |> maybe_put(:trace_id, extract_trace(thread.metadata, :trace_id))
      |> maybe_put(:trace_sensitive, extract_trace(thread.metadata, :trace_sensitive))
      |> maybe_put(:tracing_disabled, extract_trace(thread.metadata, :tracing_disabled))
      |> maybe_put(:conversation_id, extract_trace(thread.metadata, :conversation_id))
      |> maybe_put(:previous_response_id, extract_trace(thread.metadata, :previous_response_id))

    started_monotonic = System.monotonic_time()
    Telemetry.emit([:codex, :thread, :start], %{system_time: System.system_time()}, meta)

    progress_meta = meta
    initial_context = stream_context_for_thread(thread)

    case build_exec_options_from_encoded(thread, state.turn_opts, state.encoded_schema) do
      {:ok, exec_opts, cleanup, exec_meta} ->
        structured_output? = Map.get(exec_meta, :structured_output?, false)

        case Codex.Exec.run_stream(state.input, exec_opts) do
          {:ok, exec_stream} ->
            {:ok,
             %{
               state
               | phase: :running,
                 thread: thread,
                 meta: meta,
                 progress_meta: progress_meta,
                 context: initial_context,
                 started_monotonic: started_monotonic,
                 cleanup: cleanup,
                 structured_output?: structured_output?,
                 exec_stream: exec_stream,
                 exec_continuation: nil
             }}

          {:error, reason} ->
            duration = System.monotonic_time() - started_monotonic
            error = Error.normalize(reason)

            Telemetry.emit(
              [:codex, :thread, :exception],
              %{duration: duration, system_time: System.system_time()},
              merge_metadata(meta, initial_context)
              |> Map.put(:reason, error)
              |> Map.put(:result, :error)
            )

            cleanup.()

            {:error, error,
             %{
               state
               | phase: :error,
                 thread: thread,
                 meta: meta,
                 progress_meta: progress_meta,
                 context: initial_context,
                 started_monotonic: started_monotonic,
                 cleanup: nil
             }}
        end

      {:error, reason} ->
        {:error, reason,
         %{
           state
           | phase: :error,
             thread: thread,
             meta: meta,
             progress_meta: progress_meta,
             context: initial_context,
             started_monotonic: started_monotonic
         }}
    end
  end

  defp next_exec_event(%{exec_stream: exec_stream, exec_continuation: nil} = state) do
    case reduce_one(exec_stream) do
      {:ok, event, continuation} ->
        {[event], %{state | exec_continuation: continuation}}

      :done ->
        {:halt, state}
    end
  end

  defp next_exec_event(%{exec_continuation: continuation} = state) do
    case resume_one(continuation) do
      {:ok, event, next_continuation} ->
        {[event], %{state | exec_continuation: next_continuation}}

      :done ->
        {:halt, state}
    end
  end

  defp reduce_one(enumerable) do
    case Enumerable.reduce(enumerable, {:cont, nil}, &suspend_one/2) do
      {:suspended, event, continuation} -> {:ok, event, continuation}
      {:done, nil} -> :done
      {:halted, nil} -> :done
    end
  rescue
    error ->
      raise_stream_error(Error.normalize(error))
  end

  defp resume_one(continuation) when is_function(continuation, 1) do
    case continuation.({:cont, nil}) do
      {:suspended, event, next_continuation} -> {:ok, event, next_continuation}
      {:done, nil} -> :done
      {:halted, nil} -> :done
    end
  rescue
    error ->
      raise_stream_error(Error.normalize(error))
  end

  defp suspend_one(event, _acc), do: {:suspend, event}

  @spec raise_stream_error(Exception.t()) :: no_return()
  defp raise_stream_error(%{__exception__: true} = exception), do: raise(exception)

  defp transport_impl(%__MODULE__{transport: :exec}), do: Codex.Transport.ExecJsonl
  defp transport_impl(%__MODULE__{transport: {:app_server, _pid}}), do: Codex.Transport.AppServer
  defp transport_impl(%__MODULE__{transport: other}), do: {:error, {:invalid_transport, other}}

  @doc """
  Executes an auto-run loop, retrying while a continuation token is present.

  Options:
    * `:max_attempts` – maximum number of attempts (default: 3)
    * `:backoff` – unary function invoked with current attempt (default: exponential sleep)
    * `:turn_opts` – per-turn options forwarded to each attempt
  """
  @spec run_auto(t(), String.t(), keyword()) :: {:ok, Result.t()} | {:error, term()}
  def run_auto(%__MODULE__{} = thread, input, opts \\ []) when is_binary(input) do
    max_attempts = Keyword.get(opts, :max_attempts, 3)
    backoff = Keyword.get(opts, :backoff, &default_backoff/1)
    turn_opts = Keyword.get(opts, :turn_opts, %{})

    run_opts =
      turn_opts
      |> Map.new()
      |> Map.put(:max_turns, max_attempts)
      |> Map.put(:backoff, backoff)

    case AgentRunner.run(thread, input, run_opts) do
      {:error, {:max_turns_exceeded, ^max_attempts, context}} ->
        {:error, {:max_attempts_reached, max_attempts, context}}

      other ->
        other
    end
  end

  defp default_backoff(attempt) when attempt >= 1 do
    Backoff.sleep(attempt)
  end

  defp default_backoff(_attempt), do: :ok

  defp build_exec_options(thread, turn_opts) do
    turn_opts_map = Map.new(turn_opts)

    schema =
      case {
        Map.has_key?(turn_opts_map, :output_schema) ||
          Map.has_key?(turn_opts_map, "output_schema"),
        Map.get(turn_opts_map, :output_schema, Map.get(turn_opts_map, "output_schema"))
      } do
        {true, value} -> value
        {false, _} -> thread.thread_opts.output_schema
      end

    with {:ok, encoded_schema} <- OutputSchemaFile.encode(schema),
         {:ok, schema_path, cleanup} <- OutputSchemaFile.create_encoded(encoded_schema) do
      build_exec_options_with_schema(thread, turn_opts_map, schema_path, cleanup)
    end
  end

  defp build_exec_options_from_encoded(thread, turn_opts_map, encoded_schema) do
    with {:ok, schema_path, cleanup} <- OutputSchemaFile.create_encoded(encoded_schema) do
      build_exec_options_with_schema(thread, turn_opts_map, schema_path, cleanup)
    end
  end

  defp build_exec_options_with_schema(thread, turn_opts_map, schema_path, cleanup) do
    env = Map.get(turn_opts_map, :env, Map.get(turn_opts_map, "env"))
    clear_env? = Map.get(turn_opts_map, :clear_env?, Map.get(turn_opts_map, "clear_env?"))

    cancellation_token =
      Map.get(turn_opts_map, :cancellation_token, Map.get(turn_opts_map, "cancellation_token"))

    timeout_ms = Map.get(turn_opts_map, :timeout_ms, Map.get(turn_opts_map, "timeout_ms"))

    stream_idle_timeout_ms =
      Map.get(
        turn_opts_map,
        :stream_idle_timeout_ms,
        Map.get(turn_opts_map, "stream_idle_timeout_ms")
      ) || thread.thread_opts.stream_idle_timeout_ms

    filtered_turn_opts =
      turn_opts_map
      |> Map.delete(:output_schema)
      |> Map.delete("output_schema")
      |> Map.delete(:env)
      |> Map.delete("env")
      |> Map.delete(:clear_env?)
      |> Map.delete("clear_env?")
      |> Map.delete(:cancellation_token)
      |> Map.delete("cancellation_token")
      |> Map.delete(:timeout_ms)
      |> Map.delete("timeout_ms")
      |> Map.delete(:stream_idle_timeout_ms)
      |> Map.delete("stream_idle_timeout_ms")

    exec_opts =
      %{
        codex_opts: thread.codex_opts,
        thread: thread,
        turn_opts: filtered_turn_opts,
        continuation_token: thread.continuation_token,
        attachments: thread.thread_opts.attachments,
        tool_outputs: thread.pending_tool_outputs,
        tool_failures: thread.pending_tool_failures
      }
      |> maybe_put(:output_schema_path, schema_path)
      |> maybe_put(:env, env)
      |> maybe_put(:clear_env?, clear_env?)
      |> maybe_put(:cancellation_token, cancellation_token)
      |> maybe_put(:timeout_ms, timeout_ms)
      |> maybe_put(:stream_idle_timeout_ms, stream_idle_timeout_ms)

    exec_meta = %{
      structured_output?: not is_nil(schema_path)
    }

    {:ok, exec_opts, cleanup, exec_meta}
  end

  defp finalize_turn(thread, %{events: events} = exec_result, opts) do
    {updated_thread, final_response, usage} = reduce_events(thread, events, opts)
    last_response_id = last_response_id(events)

    updated_thread =
      updated_thread
      |> Map.put(:usage, usage || thread.usage)
      |> clear_pending_tool_payloads()
      |> then(fn t ->
        if early_exit?(events) do
          reset_conversation(t)
        else
          t
        end
      end)

    %Result{
      thread: updated_thread,
      events: events,
      final_response: final_response,
      usage: usage,
      raw: exec_result,
      attempts: 1,
      last_response_id: last_response_id
    }
  end

  @doc false
  @spec last_response_id([Events.t()]) :: String.t() | nil
  def last_response_id(events) when is_list(events) do
    Enum.reduce(events, nil, fn
      %Events.TurnCompleted{response_id: response_id}, _acc
      when is_binary(response_id) and response_id != "" ->
        response_id

      _event, acc ->
        acc
    end)
  end

  def last_response_id(_events), do: nil

  @doc """
  Returns the most recent account rate limit snapshot for this thread, if any.
  """
  @spec rate_limits(t()) :: Codex.Protocol.RateLimit.Snapshot.t() | map() | nil
  def rate_limits(%__MODULE__{rate_limits: rate_limits}), do: rate_limits

  @doc false
  @spec reduce_events(t(), [Events.t()], map()) :: {t(), term(), map() | nil}
  def reduce_events(thread, events, opts) do
    structured? = Map.get(opts, :structured_output?, false)

    {acc_thread, response, usage, continuation} =
      Enum.reduce(events, {thread, nil, thread.usage, thread.continuation_token}, fn event, acc ->
        reduce_event(event, acc, structured?)
      end)

    {Map.put(acc_thread, :continuation_token, continuation), response, usage}
  end

  defp reduce_event(
         %Events.ThreadStarted{} = started,
         {thread, response, usage, continuation},
         _structured?
       ) do
    labels =
      case started.metadata do
        %{"labels" => label_map} -> label_map
        _ -> thread.labels
      end

    updated =
      thread
      |> maybe_put(:thread_id, started.thread_id)
      |> Map.put(:metadata, started.metadata || %{})
      |> Map.put(:labels, labels)

    {updated, response, usage, continuation}
  end

  defp reduce_event(
         %Events.SessionConfigured{} = configured,
         {thread, response, usage, continuation},
         _structured?
       ) do
    model = configured.model || thread.codex_opts.model

    effort =
      configured.reasoning_effort
      |> normalize_reasoning_effort()
      |> case do
        nil -> thread.codex_opts.reasoning_effort
        value -> value
      end
      |> then(&Models.coerce_reasoning_effort(model, &1))

    updated_opts =
      thread.codex_opts
      |> maybe_put(:model, model)
      |> maybe_put(:reasoning_effort, effort)

    updated = %{thread | codex_opts: updated_opts}

    {updated, response, usage, continuation}
  end

  defp reduce_event(
         %Events.TurnContinuation{continuation_token: token},
         {thread, response, usage, _continuation},
         _structured?
       ) do
    updated = Map.put(thread, :continuation_token, token)
    {updated, response, usage, token}
  end

  defp reduce_event(
         %Events.ThreadTokenUsageUpdated{} = usage_event,
         {thread, response, usage, continuation},
         _structured?
       ) do
    updated_usage = apply_usage_update(usage, usage_event)

    updated_thread =
      thread
      |> maybe_put(:thread_id, usage_event.thread_id)
      |> maybe_put(:rate_limits, usage_event.rate_limits)

    {updated_thread, response, updated_usage, continuation}
  end

  defp reduce_event(
         %Events.AccountRateLimitsUpdated{} = rate_event,
         {thread, response, usage, continuation},
         _structured?
       ) do
    updated =
      thread
      |> maybe_put(:thread_id, rate_event.thread_id)
      |> Map.put(:rate_limits, rate_event.rate_limits)

    {updated, response, usage, continuation}
  end

  defp reduce_event(
         %Events.TurnDiffUpdated{thread_id: thread_id},
         {thread, response, usage, continuation},
         _structured?
       ) do
    {maybe_put(thread, :thread_id, thread_id), response, usage, continuation}
  end

  defp reduce_event(
         %Events.TurnCompaction{thread_id: thread_id, compaction: compaction},
         {thread, response, usage, continuation},
         _structured?
       ) do
    updated_thread = maybe_put(thread, :thread_id, thread_id)
    updated_usage = apply_compaction_usage_update(usage, compaction)
    {updated_thread, response, updated_usage, continuation}
  end

  defp reduce_event(
         %Events.ItemAgentMessageDelta{item: item},
         {thread, response, usage, continuation},
         structured?
       ) do
    message =
      case item do
        %{"content" => %{"type" => "text", "text" => text}} ->
          decode_agent_message(Map.get(item, "id"), text, structured?)

        %{"text" => text} when is_binary(text) ->
          decode_agent_message(Map.get(item, "id"), text, structured?)

        _ ->
          nil
      end

    {thread, message || response, usage, continuation}
  end

  defp reduce_event(
         %Events.ItemCompleted{item: %Items.AgentMessage{text: text} = item},
         {thread, _response, usage, continuation},
         structured?
       ) do
    decoded_item = maybe_decode_agent_item(item, text, structured?)
    {thread, decoded_item, usage, continuation}
  end

  defp reduce_event(
         %Events.ItemCompleted{},
         {thread, response, usage, continuation},
         _structured?
       ),
       do: {thread, response, usage, continuation}

  defp reduce_event(
         %Events.TurnCompleted{} = completed,
         {thread, response, usage, continuation},
         structured?
       ) do
    new_usage = completed.usage || usage

    new_response =
      completed.final_response
      |> decode_final_response(structured?)
      |> Kernel.||(response)

    new_continuation =
      if new_response do
        nil
      else
        thread.continuation_token || continuation
      end

    updated =
      thread
      |> maybe_put(:thread_id, completed.thread_id)
      |> Map.put(:continuation_token, new_continuation)

    {updated, new_response, new_usage, new_continuation}
  end

  defp reduce_event(_event, {thread, response, usage, continuation}, _structured?),
    do: {thread, response, usage, continuation}

  defp apply_usage_update(current_usage, %Events.ThreadTokenUsageUpdated{
         usage: usage,
         delta: delta
       }) do
    update_usage_with_maps(current_usage, usage, delta)
  end

  @doc false
  @spec merge_usage(map() | nil, map() | nil) :: map()
  def merge_usage(nil, nil), do: %{}
  def merge_usage(map, nil) when is_map(map), do: map
  def merge_usage(nil, map) when is_map(map), do: map

  def merge_usage(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn _key, l, r ->
      if is_number(l) and is_number(r), do: l + r, else: r || l
    end)
  end

  defp apply_compaction_usage_update(current_usage, compaction) when is_map(compaction) do
    usage =
      compaction
      |> get_usage_map(:usage)
      |> Kernel.||(get_usage_map(compaction, :token_usage))

    delta =
      compaction
      |> get_usage_map(:usage_delta)
      |> Kernel.||(get_usage_map(compaction, :usageDelta))

    update_usage_with_maps(current_usage, usage, delta)
  end

  defp apply_compaction_usage_update(current_usage, _compaction), do: current_usage

  defp update_usage_with_maps(current_usage, usage_map, delta_map) do
    cond do
      is_map(usage_map) and map_size(usage_map) > 0 ->
        base_usage = overlay_usage(current_usage, usage_map)
        merge_usage_delta(base_usage, usage_map, current_usage, delta_map)

      is_map(delta_map) ->
        merge_usage(current_usage || %{}, delta_map)

      is_map(usage_map) ->
        overlay_usage(current_usage, usage_map)

      true ->
        current_usage
    end
  end

  defp overlay_usage(current_usage, usage_map) do
    Map.merge(current_usage || %{}, usage_map || %{}, fn _key, _left, right -> right end)
  end

  defp merge_usage_delta(base_usage, usage_map, current_usage, delta_map)
       when is_map(delta_map) do
    Enum.reduce(delta_map, base_usage, fn {key, value}, acc ->
      if Map.has_key?(usage_map || %{}, key) do
        acc
      else
        previous = Map.get(current_usage || %{}, key)
        Map.put(acc, key, add_usage(previous, value))
      end
    end)
  end

  defp merge_usage_delta(base_usage, _usage_map, _current_usage, _delta_map), do: base_usage

  defp add_usage(nil, value), do: value
  defp add_usage(value, nil), do: value

  defp add_usage(left, right) when is_number(left) and is_number(right), do: left + right
  defp add_usage(_left, right), do: right

  defp get_usage_map(map, key) when is_map(map) do
    fetch_map_value(map, key) || fetch_map_value(map, to_string(key))
  end

  defp fetch_map_value(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} when is_map(value) -> value
      _ -> nil
    end
  end

  defp fetch_metadata_value(metadata, key) when is_map(metadata) do
    case Map.fetch(metadata, key) do
      {:ok, value} -> {:ok, value}
      :error -> Map.fetch(metadata, to_string(key))
    end
  end

  defp extract_source(metadata) when is_map(metadata) do
    case fetch_metadata_value(metadata, :source) do
      {:ok, value} -> value
      :error -> nil
    end
  end

  defp extract_source(_metadata), do: nil

  defp extract_trace(metadata, key) when is_map(metadata) do
    case fetch_metadata_value(metadata, key) do
      {:ok, value} -> value
      :error -> nil
    end
  end

  defp extract_trace(_metadata, _key), do: nil

  defp decode_final_response(nil, _structured?), do: nil
  defp decode_final_response(%Items.AgentMessage{} = item, _structured?), do: item

  defp decode_final_response(%{"type" => "text", "text" => text}, structured?)
       when is_binary(text) do
    decode_agent_message(nil, text, structured?)
  end

  defp decode_final_response(%{type: "text", text: text}, structured?) when is_binary(text) do
    decode_agent_message(nil, text, structured?)
  end

  defp decode_final_response(_other, _structured?), do: nil

  defp decode_agent_message(id, text, structured?) do
    maybe_parse_structured(id, text, structured?)
  end

  defp maybe_decode_agent_item(%Items.AgentMessage{id: id} = item, text, structured?) do
    case maybe_parse_structured(id, text, structured?) do
      %Items.AgentMessage{} = decoded -> decoded
      _ -> item
    end
  end

  defp maybe_parse_structured(id, text, true) when is_binary(text) do
    case Jason.decode(text) do
      {:ok, decoded} ->
        %Items.AgentMessage{id: id, text: text, parsed: decoded}

      _ ->
        %Items.AgentMessage{id: id, text: text}
    end
  end

  defp maybe_parse_structured(id, text, _structured?) when is_binary(text) do
    %Items.AgentMessage{id: id, text: text}
  end

  defp maybe_parse_structured(_id, _text, _structured?), do: nil

  defp maybe_decode_stream_event(
         %Events.ItemCompleted{item: %Items.AgentMessage{text: text} = item} = event,
         structured?
       ) do
    decoded = maybe_decode_agent_item(item, text, structured?)
    %Events.ItemCompleted{event | item: decoded}
  end

  defp maybe_decode_stream_event(
         %Events.TurnCompleted{final_response: response} = event,
         structured?
       ) do
    decoded = decode_final_response(response, structured?) || response
    %Events.TurnCompleted{event | final_response: decoded}
  end

  defp maybe_decode_stream_event(event, _structured?), do: event

  defp extract_turn_failure(events) do
    find_turn_failed_failure(events) ||
      find_turn_completed_failure(events) ||
      find_error_failure(events) ||
      :ok
  end

  defp find_turn_failed_failure(events) do
    case Enum.find(events, &match?(%Events.TurnFailed{}, &1)) do
      %Events.TurnFailed{error: error} -> {:error, Error.normalize(error)}
      _ -> nil
    end
  end

  defp find_turn_completed_failure(events) do
    case Enum.find(events, &failed_turn_completed?/1) do
      %Events.TurnCompleted{final_response: response, status: status, error: error} ->
        {:error, Error.normalize(turn_completed_error_payload(response, status, error))}

      _ ->
        nil
    end
  end

  defp find_error_failure(events) do
    case Enum.find(events, &match?(%Events.Error{}, &1)) do
      %Events.Error{} = event ->
        {:error, Error.normalize(error_event_payload(event))}

      _ ->
        nil
    end
  end

  defp error_event_payload(%Events.Error{} = event) do
    %{
      "message" => event.message,
      "additional_details" => event.additional_details,
      "codex_error_info" => event.codex_error_info,
      "details" =>
        %{}
        |> maybe_put("will_retry", event.will_retry)
    }
  end

  defp failed_turn_completed?(%Events.TurnCompleted{status: status})
       when status in ["failed", :failed, "error"],
       do: true

  defp failed_turn_completed?(_event), do: false

  defp telemetry_result(:ok, true), do: :early_exit
  defp telemetry_result(:ok, false), do: :ok
  defp telemetry_result({:error, _}, _), do: :error

  defp emit_progress_events(events, meta) when is_list(events) do
    Enum.each(events, &emit_progress_event(&1, meta))
  end

  defp emit_progress_event(%Events.ThreadTokenUsageUpdated{} = event, meta) do
    Telemetry.emit(
      [:codex, :thread, :token_usage, :updated],
      %{system_time: System.system_time()},
      progress_metadata(meta, %{
        thread_id: event.thread_id,
        turn_id: event.turn_id,
        usage: event.usage,
        delta: event.delta
      })
    )
  end

  defp emit_progress_event(%Events.TurnDiffUpdated{} = event, meta) do
    Telemetry.emit(
      [:codex, :turn, :diff, :updated],
      %{system_time: System.system_time()},
      progress_metadata(meta, %{
        thread_id: event.thread_id,
        turn_id: event.turn_id,
        diff: event.diff
      })
    )
  end

  defp emit_progress_event(%Events.TurnCompaction{stage: stage} = event, meta) do
    stage_name = normalize_compaction_stage(stage)

    measurements =
      %{
        system_time: System.system_time()
      }
      |> maybe_put(:token_savings, compaction_token_savings(event.compaction))

    Telemetry.emit(
      [:codex, :turn, :compaction, stage_name],
      measurements,
      progress_metadata(meta, %{
        thread_id: event.thread_id,
        turn_id: event.turn_id,
        compaction: event.compaction,
        stage: stage
      })
    )
  end

  defp emit_progress_event(_event, _meta), do: :ok

  defp progress_metadata(meta, updates) do
    meta
    |> merge_metadata(updates)
  end

  defp merge_metadata(nil, right) when is_map(right), do: right
  defp merge_metadata(left, nil) when is_map(left), do: left

  defp merge_metadata(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn _key, original, updated ->
      if is_nil(updated), do: original, else: updated
    end)
  end

  defp merge_metadata(left, _right), do: left

  defp extract_thread_context(events, thread) when is_list(events) do
    Enum.reduce(
      events,
      %{thread_id: thread.thread_id, turn_id: nil, source: extract_source(thread.metadata)},
      fn
        %Events.ThreadStarted{thread_id: id, metadata: metadata}, acc ->
          acc
          |> maybe_put(:thread_id, id)
          |> maybe_put(:source, extract_source(metadata))

        %Events.TurnStarted{thread_id: id, turn_id: turn_id}, acc ->
          acc
          |> maybe_put(:thread_id, id)
          |> maybe_put(:turn_id, turn_id)

        %Events.TurnContinuation{thread_id: id, turn_id: turn_id}, acc ->
          acc
          |> maybe_put(:thread_id, id)
          |> maybe_put(:turn_id, turn_id)

        %Events.TurnCompleted{thread_id: id, turn_id: turn_id, usage: usage}, acc ->
          acc
          |> maybe_put(:thread_id, id)
          |> maybe_put(:turn_id, turn_id)
          |> maybe_put(:source, extract_source(usage))

        %Events.ThreadTokenUsageUpdated{thread_id: id, turn_id: turn_id}, acc ->
          acc
          |> maybe_put(:thread_id, id)
          |> maybe_put(:turn_id, turn_id)

        %Events.TurnDiffUpdated{thread_id: id, turn_id: turn_id}, acc ->
          acc
          |> maybe_put(:thread_id, id)
          |> maybe_put(:turn_id, turn_id)

        %Events.TurnCompaction{thread_id: id, turn_id: turn_id, compaction: compaction}, acc ->
          acc
          |> maybe_put(:thread_id, id)
          |> maybe_put(:turn_id, turn_id)
          |> maybe_put(:source, extract_source(compaction))

        _event, acc ->
          acc
      end
    )
  end

  defp stream_context_for_thread(%__MODULE__{} = thread) do
    %{thread_id: thread.thread_id, turn_id: nil, source: extract_source(thread.metadata)}
  end

  defp update_stream_context(%{context: context} = state, event) do
    %{state | context: update_stream_context_for_event(context, event)}
  end

  defp update_stream_context_for_event(context, %Events.ThreadStarted{
         thread_id: id,
         metadata: metadata
       }) do
    context
    |> maybe_put(:thread_id, id)
    |> maybe_put(:source, extract_source(metadata))
  end

  defp update_stream_context_for_event(context, %Events.TurnStarted{
         thread_id: id,
         turn_id: turn_id
       }) do
    context
    |> maybe_put(:thread_id, id)
    |> maybe_put(:turn_id, turn_id)
  end

  defp update_stream_context_for_event(context, %Events.TurnContinuation{
         thread_id: id,
         turn_id: turn_id
       }) do
    context
    |> maybe_put(:thread_id, id)
    |> maybe_put(:turn_id, turn_id)
  end

  defp update_stream_context_for_event(
         context,
         %Events.TurnCompleted{thread_id: id, turn_id: turn_id, usage: usage}
       ) do
    context
    |> maybe_put(:thread_id, id)
    |> maybe_put(:turn_id, turn_id)
    |> maybe_put(:source, extract_source(usage))
  end

  defp update_stream_context_for_event(context, %Events.TurnFailed{
         thread_id: id,
         turn_id: turn_id
       }) do
    context
    |> maybe_put(:thread_id, id)
    |> maybe_put(:turn_id, turn_id)
  end

  defp update_stream_context_for_event(
         context,
         %Events.ThreadTokenUsageUpdated{thread_id: id, turn_id: turn_id}
       ) do
    context
    |> maybe_put(:thread_id, id)
    |> maybe_put(:turn_id, turn_id)
  end

  defp update_stream_context_for_event(context, %Events.TurnDiffUpdated{
         thread_id: id,
         turn_id: turn_id
       }) do
    context
    |> maybe_put(:thread_id, id)
    |> maybe_put(:turn_id, turn_id)
  end

  defp update_stream_context_for_event(
         context,
         %Events.TurnCompaction{thread_id: id, turn_id: turn_id, compaction: compaction}
       ) do
    context
    |> maybe_put(:thread_id, id)
    |> maybe_put(:turn_id, turn_id)
    |> maybe_put(:source, extract_source(compaction))
  end

  defp update_stream_context_for_event(context, _event), do: context

  defp update_stream_status(state, %Events.TurnFailed{error: error}) do
    failure =
      case state.failure do
        :ok -> {:error, Error.normalize(error)}
        other -> other
      end

    %{state | failure: failure, completed?: true}
  end

  defp update_stream_status(
         state,
         %Events.TurnCompleted{status: status, final_response: response, error: error} = event
       ) do
    failure =
      cond do
        state.failure != :ok ->
          state.failure

        failed_turn_completed?(event) ->
          {:error, Error.normalize(turn_completed_error_payload(response, status, error || %{}))}

        true ->
          state.failure
      end

    early_exit? = state.early_exit? || status in ["early_exit", :early_exit]

    %{state | failure: failure, early_exit?: early_exit?, completed?: true}
  end

  defp update_stream_status(state, _event), do: state

  defp maybe_emit_stream_stop(%{completed?: false}), do: :ok

  defp maybe_emit_stream_stop(state) do
    duration = System.monotonic_time() - state.started_monotonic

    Telemetry.emit(
      [:codex, :thread, :stop],
      %{duration: duration, system_time: System.system_time()},
      state.meta
      |> merge_metadata(state.context)
      |> Map.put(:result, telemetry_result(state.failure, state.early_exit?))
      |> maybe_put(:error, failure_meta(state.failure))
      |> maybe_put(:early_exit?, state.early_exit?)
    )
  end

  defp compaction_token_savings(compaction) do
    case compaction do
      %{} ->
        case fetch_metadata_value(compaction, :token_savings) do
          {:ok, value} -> value
          :error -> nil
        end

      _ ->
        nil
    end
  end

  defp normalize_compaction_stage(stage) when is_atom(stage), do: stage

  defp normalize_compaction_stage(stage) when is_binary(stage) do
    stage
    |> String.downcase()
    |> case do
      "started" -> :started
      "completed" -> :completed
      "failed" -> :failed
      _ -> :unknown
    end
  end

  defp normalize_compaction_stage(_stage), do: :unknown

  defp failure_meta({:error, %Error{} = error}) do
    %{kind: error.kind, message: error.message}
  end

  defp failure_meta(_), do: nil

  defp early_exit?(events) do
    Enum.any?(events, fn
      %Events.TurnCompleted{status: status} when status in ["early_exit", :early_exit] -> true
      _ -> false
    end)
  end

  defp maybe_reset_for_new(%__MODULE__{} = thread, input) do
    if new_command?(input) do
      reset_conversation(thread)
    else
      thread
    end
  end

  defp new_command?(input) when is_binary(input) do
    String.trim(input) == "/new"
  end

  defp new_command?(input) when is_list(input) do
    case input do
      [block | _rest] -> new_command_block?(block)
      _ -> false
    end
  end

  defp new_command?(_input), do: false

  defp new_command_block?(%{"type" => "text"} = block),
    do: new_command_text(Map.get(block, "text"))

  defp new_command_block?(%{type: :text} = block),
    do: new_command_text(Map.get(block, :text))

  defp new_command_block?(%{type: "text"} = block),
    do: new_command_text(Map.get(block, :text) || Map.get(block, "text"))

  defp new_command_block?(%{"text" => text} = block) do
    if Map.has_key?(block, "type"), do: false, else: new_command_text(text)
  end

  defp new_command_block?(%{text: text} = block) do
    if Map.has_key?(block, :type) or Map.has_key?(block, "type"),
      do: false,
      else: new_command_text(text)
  end

  defp new_command_block?(text) when is_binary(text), do: new_command_text(text)
  defp new_command_block?(_block), do: false

  defp new_command_text(text) when is_binary(text) do
    String.trim(text) == "/new"
  end

  defp new_command_text(_text), do: false

  defp reset_conversation(%__MODULE__{} = thread) do
    %__MODULE__{
      clear_pending_tool_payloads(thread)
      | thread_id: nil,
        metadata: %{},
        labels: %{},
        resume: nil,
        continuation_token: nil,
        usage: %{}
    }
  end

  defp turn_completed_error_payload(_response, _status, %{} = error) when map_size(error) > 0,
    do: error

  defp turn_completed_error_payload(%Items.AgentMessage{text: text}, status, _error)
       when is_binary(text),
       do: %{"message" => text, "type" => status}

  defp turn_completed_error_payload(%{"text" => text}, status, _error) when is_binary(text),
    do: %{"message" => text, "type" => status}

  defp turn_completed_error_payload(%{text: text}, status, _error) when is_binary(text),
    do: %{"message" => text, "type" => status}

  defp turn_completed_error_payload(response, status, _error) when is_map(response),
    do: Map.put(response, "type", status)

  defp turn_completed_error_payload(nil, status, _error),
    do: %{"message" => "turn failed", "type" => status}

  defp turn_completed_error_payload(response, status, _error),
    do: %{"message" => to_string(response), "type" => status}

  defp merge_file_search_metadata(metadata, nil), do: metadata

  defp merge_file_search_metadata(metadata, file_search) do
    fs_map = normalize_file_search_map(file_search)

    metadata
    |> maybe_put_new(:file_search, fs_map)
    |> maybe_put_new("file_search", fs_map)
    |> maybe_put_new(:vector_store_ids, Map.get(fs_map, :vector_store_ids))
    |> maybe_put_new("vector_store_ids", Map.get(fs_map, :vector_store_ids))
    |> maybe_put_new(:filters, Map.get(fs_map, :filters))
    |> maybe_put_new("filters", Map.get(fs_map, :filters))
    |> maybe_put_new(:ranking_options, Map.get(fs_map, :ranking_options))
    |> maybe_put_new("ranking_options", Map.get(fs_map, :ranking_options))
    |> maybe_put_new(:include_search_results, Map.get(fs_map, :include_search_results))
    |> maybe_put_new("include_search_results", Map.get(fs_map, :include_search_results))
  end

  defp normalize_file_search_map(%Codex.FileSearch{} = file_search),
    do: file_search |> Map.from_struct()

  defp normalize_file_search_map(map) when is_map(map), do: map
  defp normalize_file_search_map(_), do: %{}

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp normalize_reasoning_effort(value) do
    case Models.normalize_reasoning_effort(value) do
      {:ok, effort} -> effort
      _ -> nil
    end
  end

  defp maybe_put_new(map, _key, nil), do: map

  defp maybe_put_new(map, key, value) do
    if Map.has_key?(map, key) do
      map
    else
      Map.put(map, key, value)
    end
  end

  @doc false
  @spec handle_tool_requests(Result.t(), non_neg_integer(), map()) ::
          {:ok, Result.t()} | {:error, term()}
  def handle_tool_requests(result, attempt, opts \\ %{})

  def handle_tool_requests(%Result{} = result, attempt, opts) do
    tool_events = Enum.filter(result.events, &match?(%Events.ToolCallRequested{}, &1))

    guardrails = %{
      input: Map.get(opts, :tool_input, Map.get(opts, "tool_input", [])) || [],
      output: Map.get(opts, :tool_output, Map.get(opts, "tool_output", [])) || []
    }

    hooks = Map.get(opts, :hooks, %{})

    Enum.reduce_while(tool_events, {:ok, result}, fn event, {:ok, acc_result} ->
      handle_tool_event(acc_result, event, attempt, guardrails, hooks)
    end)
  end

  def handle_tool_requests(result, _attempt, _opts), do: {:ok, result}

  defp handle_tool_event(
         %Result{} = result,
         %Events.ToolCallRequested{} = event,
         attempt,
         guardrails,
         hooks
       ) do
    case handled_tool_call?(result, event) do
      true ->
        {:cont, {:ok, result}}

      false ->
        do_handle_tool_event(result, event, attempt, guardrails, hooks)
    end
  end

  defp do_handle_tool_event(
         %Result{} = result,
         %Events.ToolCallRequested{} = event,
         attempt,
         guardrails,
         hooks
       ) do
    case maybe_invoke_tool(result.thread, event, attempt, guardrails, hooks) do
      {:ok, output} ->
        payload = %{
          call_id: event.call_id,
          tool_name: event.tool_name,
          arguments: event.arguments,
          output: output
        }

        updated =
          update_result_tool_payload(result, :tool_outputs, :pending_tool_outputs, payload)

        {:cont, {:ok, updated}}

      {:failure, reason} ->
        payload = %{
          call_id: event.call_id,
          tool_name: event.tool_name,
          arguments: event.arguments,
          reason: normalize_tool_failure(reason)
        }

        updated =
          update_result_tool_payload(result, :tool_failures, :pending_tool_failures, payload)

        {:cont, {:ok, updated}}

      {:error, reason} ->
        {:halt, {:error, reason}}
    end
  end

  defp update_result_tool_payload(%Result{} = result, raw_key, thread_key, payload) do
    updated_raw =
      result.raw
      |> Map.put(raw_key, merge_tool_payload(Map.get(result.raw, raw_key, []), payload))

    updated_thread =
      result.thread
      |> Map.put(thread_key, merge_tool_payload(Map.get(result.thread, thread_key, []), payload))

    %Result{result | raw: updated_raw, thread: updated_thread}
  end

  defp maybe_invoke_tool(thread, %Events.ToolCallRequested{} = event, attempt, guardrails, hooks) do
    context = build_tool_context(thread, event, attempt)

    case run_tool_guardrails(:input, guardrails.input, event, event.arguments, context, hooks) do
      :ok ->
        invoke_and_check_output(thread, event, context, guardrails, hooks)

      {:reject_content, message} ->
        {:ok, ToolOutput.normalize(ToolOutput.text(message))}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp invoke_and_check_output(thread, event, context, guardrails, hooks) do
    with :ok <- approve_tool(thread, event, context, hooks),
         {:ok, output} <- invoke_tool(event, context) do
      case run_tool_guardrails(:output, guardrails.output, event, output, context, hooks) do
        :ok -> {:ok, output}
        {:reject_content, message} -> {:ok, ToolOutput.normalize(ToolOutput.text(message))}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp approve_tool(thread, %Events.ToolCallRequested{} = event, context, hooks) do
    policy_or_hook = thread.thread_opts.approval_hook || thread.thread_opts.approval_policy
    timeout = thread.thread_opts.approval_timeout_ms || 30_000

    case Approvals.review_tool(policy_or_hook, event, context, timeout: timeout) do
      :allow ->
        notify_approval(hooks, event, :allow, nil)

      {:deny, reason} ->
        case notify_approval(hooks, event, :deny, reason) do
          :ok -> {:error, ApprovalError.new(event.tool_name, reason)}
          {:error, error} -> {:error, error}
        end
    end
  end

  defp invoke_tool(%Events.ToolCallRequested{} = event, context) do
    case Tools.invoke(event.tool_name, event.arguments, context) do
      {:ok, output} ->
        {:ok, ToolOutput.normalize(output)}

      {:error, reason} ->
        {:failure,
         Error.new(:tool_failure, "tool #{event.tool_name} failed", %{
           tool: event.tool_name,
           reason: reason
         })}
    end
  end

  defp build_tool_context(thread, event, attempt) do
    metadata =
      thread.thread_opts.metadata
      |> Kernel.||(%{})
      |> merge_file_search_metadata(thread.thread_opts.file_search)

    tool_context =
      metadata[:tool_context] || metadata["tool_context"] || %{}

    warnings =
      Map.get(event, :sandbox_warnings) || Map.get(event, "sandbox_warnings") ||
        Map.get(event, :warnings) || Map.get(event, "warnings")

    capabilities = Map.get(event, :capabilities) || Map.get(event, "capabilities")

    %{
      thread: thread,
      metadata: metadata,
      context: tool_context,
      file_search: thread.thread_opts.file_search,
      event: event,
      attempt: attempt,
      retry?: attempt > 1
    }
    |> maybe_put(:capabilities, capabilities)
    |> maybe_put(:sandbox_warnings, warnings)
  end

  defp run_tool_guardrails(_stage, guardrails, _event, _payload, _context, _hooks)
       when guardrails in [nil, []],
       do: :ok

  defp run_tool_guardrails(stage, guardrails, event, payload, context, hooks) do
    context = Map.put(context, :event, event)

    {parallel, sequential} = Enum.split_with(guardrails, & &1.run_in_parallel)

    case run_tool_guardrails_sequential(stage, sequential, event, payload, context, hooks) do
      :ok -> run_tool_guardrails_parallel(stage, parallel, event, payload, context, hooks)
      {:reject_content, message} -> {:reject_content, message}
      {:error, reason} -> {:error, reason}
    end
  end

  defp run_tool_guardrails_sequential(_stage, [], _event, _payload, _context, _hooks), do: :ok

  defp run_tool_guardrails_sequential(stage, guardrails, event, payload, context, hooks) do
    Enum.reduce_while(guardrails, :ok, fn guardrail, :ok ->
      case run_tool_guardrail(stage, guardrail, event, payload, context, hooks) do
        :ok -> {:cont, :ok}
        {:reject_content, message} -> {:halt, {:reject_content, message}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp run_tool_guardrails_parallel(_stage, [], _event, _payload, _context, _hooks), do: :ok

  defp run_tool_guardrails_parallel(stage, guardrails, event, payload, context, hooks) do
    guardrails
    |> Task.async_stream(
      fn guardrail ->
        run_tool_guardrail(stage, guardrail, event, payload, context, hooks)
      end,
      ordered: true
    )
    |> Enum.reduce_while(:ok, fn
      {:ok, :ok}, :ok ->
        {:cont, :ok}

      {:ok, {:reject_content, message}}, :ok ->
        {:halt, {:reject_content, message}}

      {:ok, {:error, reason}}, :ok ->
        {:halt, {:error, reason}}

      {:exit, reason}, :ok ->
        {:halt,
         {:error,
          guardrail_exception_error(stage, %{name: "parallel_guardrail"}, inspect(reason))}}
    end)
  end

  defp run_tool_guardrail(stage, guardrail, event, payload, context, hooks) do
    stage
    |> safe_tool_guardrail_run(guardrail, event, payload, context)
    |> handle_tool_guardrail_result(stage, guardrail, hooks)
  end

  defp handle_tool_guardrail_result({:error, reason}, _stage, _guardrail, _hooks),
    do: {:error, reason}

  defp handle_tool_guardrail_result({:ok, :ok}, stage, guardrail, hooks) do
    case notify_tool_guardrail(hooks, stage, guardrail, :ok, nil) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp handle_tool_guardrail_result({:ok, {:reject, message}}, stage, guardrail, hooks) do
    case guardrail.behavior do
      :reject_content ->
        case notify_tool_guardrail(hooks, stage, guardrail, :reject, message) do
          :ok -> {:reject_content, message}
          {:error, reason} -> {:error, reason}
        end

      :raise_exception ->
        handle_tool_guardrail_failure(stage, guardrail, hooks, :tripwire, message)

      _ ->
        handle_tool_guardrail_failure(stage, guardrail, hooks, :reject, message)
    end
  end

  defp handle_tool_guardrail_result({:ok, {:tripwire, message}}, stage, guardrail, hooks) do
    handle_tool_guardrail_failure(stage, guardrail, hooks, :tripwire, message)
  end

  defp handle_tool_guardrail_failure(stage, guardrail, hooks, type, message) do
    case notify_tool_guardrail(hooks, stage, guardrail, type, message) do
      :ok -> {:error, guardrail_error(stage, guardrail, type, message)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp safe_tool_guardrail_run(stage, guardrail, event, payload, context) do
    {:ok, ToolGuardrail.run(guardrail, event, payload, context)}
  rescue
    exception ->
      {:error,
       guardrail_exception_error(
         stage,
         guardrail,
         "guardrail handler raised: #{Exception.message(exception)}"
       )}
  catch
    kind, reason ->
      {:error,
       guardrail_exception_error(
         stage,
         guardrail,
         "guardrail handler #{kind}: #{inspect(reason)}"
       )}
  end

  defp guardrail_error(stage, guardrail, type, message) do
    %GuardrailError{
      stage: if(stage == :output, do: :tool_output, else: :tool_input),
      guardrail: Map.get(guardrail, :name),
      message: message,
      type: type
    }
  end

  defp guardrail_exception_error(stage, guardrail, message) do
    guardrail_error(stage, guardrail, :tripwire, message)
  end

  defp notify_tool_guardrail(%{on_guardrail: fun}, stage, guardrail, result, message)
       when is_function(fun, 4) do
    fun.(stage, guardrail, result, message)
    :ok
  rescue
    exception ->
      {:error,
       guardrail_exception_error(
         stage,
         guardrail,
         "guardrail hook raised: #{Exception.message(exception)}"
       )}
  catch
    kind, reason ->
      {:error,
       guardrail_exception_error(
         stage,
         guardrail,
         "guardrail hook #{kind}: #{inspect(reason)}"
       )}
  end

  defp notify_tool_guardrail(_hooks, _stage, _guardrail, _result, _message), do: :ok

  defp notify_approval(%{on_approval: fun}, event, decision, reason)
       when is_function(fun, 3) do
    fun.(event, decision, reason)
    :ok
  rescue
    exception ->
      {:error, approval_hook_error(event, Exception.message(exception))}
  catch
    kind, value ->
      {:error, approval_hook_error(event, "#{kind}: #{inspect(value)}")}
  end

  defp notify_approval(_hooks, _event, _decision, _reason), do: :ok

  defp approval_hook_error(event, message) do
    Error.new(:approval_hook_failed, "approval hook failed: #{message}", %{
      tool: Map.get(event, :tool_name) || Map.get(event, "tool_name"),
      call_id: Map.get(event, :call_id) || Map.get(event, "call_id")
    })
  end

  defp normalize_tool_failure(reason) do
    %Codex.Error{message: message, kind: kind, details: details} = Codex.Error.normalize(reason)

    %{
      message: message,
      kind: kind,
      details: details
    }
  end

  defp handled_tool_call?(%Result{} = result, %Events.ToolCallRequested{} = event) do
    key = tool_call_key(event)

    if is_nil(key) do
      false
    else
      outputs = Map.get(result.raw, :tool_outputs, []) ++ result.thread.pending_tool_outputs

      failures = Map.get(result.raw, :tool_failures, []) ++ result.thread.pending_tool_failures

      Enum.any?(outputs ++ failures, fn payload ->
        tool_call_key(payload) == key
      end)
    end
  end

  defp merge_tool_payload(existing, payload) do
    key = tool_call_key(payload)

    existing
    |> List.wrap()
    |> Enum.reject(&(not is_nil(key) and tool_call_key(&1) == key))
    |> Kernel.++([payload])
  end

  defp tool_call_key(%Events.ToolCallRequested{} = event) do
    call_id = normalize_call_id(event.call_id || Map.get(event, :call_id))

    if call_id do
      {:call_id, call_id}
    else
      fallback_tool_key(event.tool_name, event.arguments)
    end
  end

  defp tool_call_key(%{} = payload) do
    call_id = normalize_call_id(payload)

    if call_id do
      {:call_id, call_id}
    else
      tool_name = Map.get(payload, :tool_name) || Map.get(payload, "tool_name")
      arguments = Map.get(payload, :arguments) || Map.get(payload, "arguments")
      fallback_tool_key(tool_name, arguments)
    end
  end

  defp tool_call_key(_), do: nil

  defp fallback_tool_key(tool_name, arguments) when is_binary(tool_name) do
    {:fallback, :erlang.phash2({tool_name, arguments})}
  end

  defp fallback_tool_key(_tool_name, _arguments), do: nil

  defp normalize_call_id(%{call_id: id}), do: normalize_call_id(id)
  defp normalize_call_id(%{"call_id" => id}), do: normalize_call_id(id)
  defp normalize_call_id(nil), do: nil
  defp normalize_call_id(id) when is_atom(id), do: Atom.to_string(id)
  defp normalize_call_id(id) when is_binary(id), do: id
  defp normalize_call_id(_), do: nil
end
