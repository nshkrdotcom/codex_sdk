defmodule Codex.Thread do
  @moduledoc """
  Represents a Codex conversation thread and exposes turn execution APIs.
  """

  alias Codex.AgentRunner
  alias Codex.ApprovalError
  alias Codex.Approvals
  alias Codex.Error
  alias Codex.Events
  alias Codex.RunResultStreaming
  alias Codex.GuardrailError
  alias Codex.Items
  alias Codex.Options
  alias Codex.OutputSchemaFile
  alias Codex.Thread.Options, as: ThreadOptions
  alias Codex.ToolGuardrail
  alias Codex.ToolOutput
  alias Codex.Tools
  alias Codex.Telemetry
  alias Codex.Turn.Result

  @enforce_keys [:codex_opts, :thread_opts]
  defstruct thread_id: nil,
            codex_opts: nil,
            thread_opts: nil,
            metadata: %{},
            labels: %{},
            continuation_token: nil,
            usage: %{},
            pending_tool_outputs: [],
            pending_tool_failures: []

  @type t :: %__MODULE__{
          thread_id: String.t() | nil,
          codex_opts: Options.t(),
          thread_opts: ThreadOptions.t(),
          metadata: map(),
          labels: map(),
          continuation_token: String.t() | nil,
          usage: map(),
          pending_tool_outputs: [map()],
          pending_tool_failures: [map()]
        }

  @doc false
  @spec build(Options.t(), ThreadOptions.t(), keyword()) :: t()
  def build(%Options{} = opts, %ThreadOptions{} = thread_opts, extra \\ []) do
    struct!(
      __MODULE__,
      Keyword.merge(
        [
          thread_id: nil,
          codex_opts: opts,
          thread_opts: thread_opts,
          metadata: %{},
          labels: %{},
          continuation_token: nil,
          usage: %{},
          pending_tool_outputs: [],
          pending_tool_failures: []
        ],
        extra
      )
    )
  end

  @doc """
  Executes a blocking multi-turn run using the agent runner.
  """
  @spec run(t(), String.t(), map() | keyword()) ::
          {:ok, Result.t()} | {:error, term()}
  def run(%__MODULE__{} = thread, input, opts \\ %{}) when is_binary(input) do
    AgentRunner.run(thread, input, opts)
  end

  @doc false
  @spec run_turn(t(), String.t(), map() | keyword()) ::
          {:ok, Result.t()} | {:error, term()}
  def run_turn(%__MODULE__{} = thread, input, turn_opts \\ %{}) when is_binary(input) do
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

            Telemetry.emit(
              [:codex, :thread, :exception],
              %{duration: duration, system_time: System.system_time()},
              merge_metadata(meta, %{
                thread_id: thread.thread_id,
                source: extract_source(thread.metadata)
              })
              |> Map.put(:reason, reason)
              |> Map.put(:result, :error)
            )

            {:error, reason}
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
  @spec run_streamed(t(), String.t(), map() | keyword()) ::
          {:ok, RunResultStreaming.t()} | {:error, term()}
  def run_streamed(%__MODULE__{} = thread, input, opts \\ %{}) when is_binary(input) do
    AgentRunner.run_streamed(thread, input, opts)
  end

  @doc false
  @spec run_turn_streamed(t(), String.t(), map() | keyword()) ::
          {:ok, Enumerable.t()} | {:error, term()}
  def run_turn_streamed(%__MODULE__{} = thread, input, turn_opts \\ %{}) when is_binary(input) do
    thread = maybe_reset_for_new(thread, input)

    with {:ok, exec_opts, cleanup, exec_meta} <- build_exec_options(thread, turn_opts) do
      structured_output? = Map.get(exec_meta, :structured_output?, false)

      progress_meta =
        %{
          thread_id: thread.thread_id,
          originator: :sdk,
          span_token: make_ref()
        }
        |> maybe_put(:source, extract_source(thread.metadata))

      case Codex.Exec.run_stream(input, exec_opts) do
        {:ok, stream} ->
          wrapped =
            Stream.transform(
              stream,
              fn -> :ok end,
              fn event, acc ->
                decoded = maybe_decode_stream_event(event, structured_output?)
                emit_progress_event(decoded, progress_meta)
                {[decoded], acc}
              end,
              fn _ -> cleanup.() end
            )

          {:ok, wrapped}

        {:error, reason} ->
          cleanup.()
          {:error, reason}
      end
    end
  end

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
    exponent = attempt - 1
    delay = trunc(:math.pow(2, exponent))
    Process.sleep(delay * 100)
  end

  defp build_exec_options(thread, turn_opts) do
    turn_opts_map = Map.new(turn_opts)
    schema = Map.get(turn_opts_map, :output_schema, Map.get(turn_opts_map, "output_schema"))

    with {:ok, schema_path, cleanup} <- OutputSchemaFile.create(schema) do
      env = Map.get(turn_opts_map, :env, Map.get(turn_opts_map, "env"))

      cancellation_token =
        Map.get(turn_opts_map, :cancellation_token, Map.get(turn_opts_map, "cancellation_token"))

      timeout_ms = Map.get(turn_opts_map, :timeout_ms, Map.get(turn_opts_map, "timeout_ms"))

      filtered_turn_opts =
        turn_opts_map
        |> Map.delete(:output_schema)
        |> Map.delete("output_schema")
        |> Map.delete(:env)
        |> Map.delete("env")
        |> Map.delete(:cancellation_token)
        |> Map.delete("cancellation_token")
        |> Map.delete(:timeout_ms)
        |> Map.delete("timeout_ms")

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
        |> maybe_put(:cancellation_token, cancellation_token)
        |> maybe_put(:timeout_ms, timeout_ms)

      {:ok, exec_opts, cleanup, %{structured_output?: not is_nil(schema)}}
    end
  end

  defp finalize_turn(thread, %{events: events} = exec_result, opts) do
    {updated_thread, final_response, usage} = reduce_events(thread, events, opts)

    updated_thread =
      updated_thread
      |> Map.put(:usage, usage || thread.usage)
      |> Map.put(:pending_tool_outputs, [])
      |> Map.put(:pending_tool_failures, [])
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
      attempts: 1
    }
  end

  @doc false
  @spec reduce_events(t(), [Events.t()], map()) :: {t(), term(), map() | nil}
  def reduce_events(thread, events, opts) do
    structured? = Map.get(opts, :structured_output?, false)

    Enum.reduce(events, {thread, nil, thread.usage, thread.continuation_token}, fn event,
                                                                                   {acc_thread,
                                                                                    response,
                                                                                    usage,
                                                                                    continuation} ->
      case event do
        %Events.ThreadStarted{} = started ->
          labels =
            case started.metadata do
              %{"labels" => label_map} -> label_map
              _ -> acc_thread.labels
            end

          updated =
            acc_thread
            |> maybe_put(:thread_id, started.thread_id)
            |> Map.put(:metadata, started.metadata || %{})
            |> Map.put(:labels, labels)

          {updated, response, usage, continuation}

        %Events.TurnContinuation{continuation_token: token} ->
          updated = Map.put(acc_thread, :continuation_token, token)
          {updated, response, usage, token}

        %Events.ThreadTokenUsageUpdated{} = usage_event ->
          updated_usage = apply_usage_update(usage, usage_event)

          updated_thread =
            acc_thread
            |> maybe_put(:thread_id, usage_event.thread_id)

          {updated_thread, response, updated_usage, continuation}

        %Events.TurnDiffUpdated{thread_id: thread_id} ->
          updated_thread = maybe_put(acc_thread, :thread_id, thread_id)
          {updated_thread, response, usage, continuation}

        %Events.TurnCompaction{thread_id: thread_id, compaction: compaction} ->
          updated_thread = maybe_put(acc_thread, :thread_id, thread_id)
          updated_usage = apply_compaction_usage_update(usage, compaction)
          {updated_thread, response, updated_usage, continuation}

        %Events.ItemAgentMessageDelta{item: item} ->
          new_response =
            case item do
              %{"content" => %{"type" => "text", "text" => text}} ->
                decode_agent_message(Map.get(item, "id"), text, structured?)

              %{"text" => text} when is_binary(text) ->
                decode_agent_message(Map.get(item, "id"), text, structured?)

              _ ->
                response
            end

          {acc_thread, new_response || response, usage, continuation}

        %Events.ItemCompleted{item: %Items.AgentMessage{text: text} = item} ->
          decoded_item = maybe_decode_agent_item(item, text, structured?)
          {acc_thread, decoded_item, usage, continuation}

        %Events.ItemCompleted{} ->
          {acc_thread, response, usage, continuation}

        %Events.TurnCompleted{} = completed ->
          new_usage = completed.usage || usage

          new_response =
            completed.final_response
            |> decode_final_response(structured?)
            |> Kernel.||(response)

          new_continuation =
            if new_response do
              nil
            else
              acc_thread.continuation_token || continuation
            end

          updated =
            acc_thread
            |> maybe_put(:thread_id, completed.thread_id)
            |> Map.put(:continuation_token, new_continuation)

          {updated, new_response, new_usage, new_continuation}

        _other ->
          {acc_thread, response, usage, continuation}
      end
    end)
    |> then(fn {acc_thread, response, usage, continuation} ->
      updated_thread =
        acc_thread
        |> Map.put(:continuation_token, continuation)

      {updated_thread, response, usage}
    end)
  end

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
      cond do
        is_number(l) and is_number(r) -> l + r
        true -> r || l
      end
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

  defp get_usage_map(_map, _key), do: nil

  defp fetch_map_value(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} when is_map(value) -> value
      _ -> nil
    end
  end

  defp extract_source(metadata) when is_map(metadata) do
    Map.get(metadata, :source) || Map.get(metadata, "source")
  end

  defp extract_source(_metadata), do: nil

  defp extract_trace(metadata, key) when is_map(metadata) do
    Map.get(metadata, key) || Map.get(metadata, to_string(key))
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
    with {:ok, decoded} <- Jason.decode(text) do
      %Items.AgentMessage{id: id, text: text, parsed: decoded}
    else
      _ -> %Items.AgentMessage{id: id, text: text}
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
    case Enum.find(events, &match?(%Events.TurnFailed{}, &1)) do
      %Events.TurnFailed{error: error} ->
        {:error, Error.normalize(error)}

      nil ->
        case Enum.find(events, fn
               %Events.TurnCompleted{status: status}
               when status in ["failed", :failed, "error"] ->
                 true

               _ ->
                 false
             end) do
          %Events.TurnCompleted{final_response: response, status: status} ->
            {:error, Error.normalize(turn_completed_error_payload(response, status))}

          _ ->
            :ok
        end
    end
  end

  defp telemetry_result(:ok, true), do: :early_exit
  defp telemetry_result(:ok, false), do: :ok
  defp telemetry_result({:error, _}, _), do: :error

  defp emit_progress_events(events, meta) when is_list(events) do
    Enum.each(events, &emit_progress_event(&1, meta))
  end

  defp emit_progress_events(_events, _meta), do: :ok

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

  defp extract_thread_context(_events, thread) do
    %{thread_id: thread.thread_id, turn_id: nil, source: extract_source(thread.metadata)}
  end

  defp compaction_token_savings(compaction) do
    case compaction do
      %{} ->
        Map.get(compaction, :token_savings) || Map.get(compaction, "token_savings")

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

  defp reset_conversation(%__MODULE__{} = thread) do
    %__MODULE__{
      thread
      | thread_id: nil,
        metadata: %{},
        labels: %{},
        continuation_token: nil,
        usage: %{},
        pending_tool_outputs: [],
        pending_tool_failures: []
    }
  end

  defp turn_completed_error_payload(%Items.AgentMessage{text: text}, status),
    do: %{"message" => text, "type" => status}

  defp turn_completed_error_payload(%{"text" => text}, status) when is_binary(text),
    do: %{"message" => text, "type" => status}

  defp turn_completed_error_payload(%{text: text}, status) when is_binary(text),
    do: %{"message" => text, "type" => status}

  defp turn_completed_error_payload(response, status) when is_map(response),
    do: Map.put(response, "type", status)

  defp turn_completed_error_payload(response, status),
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
      if handled_tool_call?(acc_result, event) do
        {:cont, {:ok, acc_result}}
      else
        case maybe_invoke_tool(acc_result.thread, event, attempt, guardrails, hooks) do
          {:ok, output} ->
            tool_payload = %{call_id: event.call_id, tool_name: event.tool_name, output: output}

            updated_raw =
              acc_result.raw
              |> Map.put(
                :tool_outputs,
                merge_tool_payload(Map.get(acc_result.raw, :tool_outputs, []), tool_payload)
              )

            updated_thread =
              acc_result.thread
              |> Map.put(
                :pending_tool_outputs,
                merge_tool_payload(acc_result.thread.pending_tool_outputs, tool_payload)
              )

            updated_result = %Result{acc_result | raw: updated_raw, thread: updated_thread}

            {:cont, {:ok, updated_result}}

          {:failure, reason} ->
            failure_payload = %{
              call_id: event.call_id,
              tool_name: event.tool_name,
              reason: normalize_tool_failure(reason)
            }

            updated_raw =
              acc_result.raw
              |> Map.put(
                :tool_failures,
                merge_tool_payload(Map.get(acc_result.raw, :tool_failures, []), failure_payload)
              )

            updated_thread =
              acc_result.thread
              |> Map.put(
                :pending_tool_failures,
                merge_tool_payload(
                  acc_result.thread.pending_tool_failures,
                  failure_payload
                )
              )

            updated_result = %Result{acc_result | raw: updated_raw, thread: updated_thread}

            {:cont, {:ok, updated_result}}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      end
    end)
  end

  def handle_tool_requests(result, _attempt, _opts), do: {:ok, result}

  defp maybe_invoke_tool(thread, %Events.ToolCallRequested{} = event, attempt, guardrails, hooks) do
    context = build_tool_context(thread, event, attempt)

    with :ok <-
           run_tool_guardrails(:input, guardrails.input, event, event.arguments, context, hooks) do
      # Prefer approval_hook over approval_policy
      policy_or_hook = thread.thread_opts.approval_hook || thread.thread_opts.approval_policy
      timeout = thread.thread_opts.approval_timeout_ms || 30_000

      case Approvals.review_tool(policy_or_hook, event, context, timeout: timeout) do
        :allow ->
          notify_approval(hooks, event, :allow, nil)

          case Tools.invoke(event.tool_name, event.arguments, context) do
            {:ok, output} ->
              normalized_output = ToolOutput.normalize(output)

              with :ok <-
                     run_tool_guardrails(
                       :output,
                       guardrails.output,
                       event,
                       normalized_output,
                       context,
                       hooks
                     ) do
                {:ok, normalized_output}
              end

            {:error, reason} ->
              {:failure,
               Error.new(:tool_failure, "tool #{event.tool_name} failed", %{
                 tool: event.tool_name,
                 reason: reason
               })}
          end

        {:deny, reason} ->
          notify_approval(hooks, event, :deny, reason)
          {:error, ApprovalError.new(event.tool_name, reason)}
      end
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

    Enum.reduce_while(guardrails, :ok, fn guardrail, :ok ->
      case ToolGuardrail.run(guardrail, event, payload, context) do
        :ok ->
          notify_tool_guardrail(hooks, stage, guardrail, :ok, nil)
          {:cont, :ok}

        {:reject, message} ->
          notify_tool_guardrail(hooks, stage, guardrail, :reject, message)
          {:halt, {:error, guardrail_error(stage, guardrail, :reject, message)}}

        {:tripwire, message} ->
          notify_tool_guardrail(hooks, stage, guardrail, :tripwire, message)
          {:halt, {:error, guardrail_error(stage, guardrail, :tripwire, message)}}
      end
    end)
  end

  defp guardrail_error(stage, guardrail, type, message) do
    %GuardrailError{
      stage: if(stage == :output, do: :tool_output, else: :tool_input),
      guardrail: Map.get(guardrail, :name),
      message: message,
      type: type
    }
  end

  defp notify_tool_guardrail(%{on_guardrail: fun}, stage, guardrail, result, message)
       when is_function(fun, 4) do
    fun.(stage, guardrail, result, message)
  end

  defp notify_tool_guardrail(_hooks, _stage, _guardrail, _result, _message), do: :ok

  defp notify_approval(%{on_approval: fun}, event, decision, reason)
       when is_function(fun, 3) do
    fun.(event, decision, reason)
  end

  defp notify_approval(_hooks, _event, _decision, _reason), do: :ok

  defp normalize_tool_failure(%Codex.Error{} = error) do
    details =
      case error.details do
        value when is_map(value) -> value
        _ -> %{}
      end

    %{
      message: error.message,
      kind: error.kind,
      details: details
    }
  end

  defp normalize_tool_failure(value) when is_map(value), do: value
  defp normalize_tool_failure(value) when is_binary(value), do: %{message: value}
  defp normalize_tool_failure(value), do: %{message: inspect(value)}

  defp handled_tool_call?(%Result{} = result, %Events.ToolCallRequested{} = event) do
    call_id = normalize_call_id(event.call_id || Map.get(event, :call_id))

    outputs = Map.get(result.raw, :tool_outputs, []) ++ result.thread.pending_tool_outputs

    failures = Map.get(result.raw, :tool_failures, []) ++ result.thread.pending_tool_failures

    Enum.any?(outputs ++ failures, fn payload ->
      normalize_call_id(payload) == call_id
    end)
  end

  defp handled_tool_call?(_result, _event), do: false

  defp merge_tool_payload(existing, payload) do
    normalized_id = normalize_call_id(payload)

    existing
    |> List.wrap()
    |> Enum.reject(&(normalize_call_id(&1) == normalized_id && not is_nil(normalized_id)))
    |> Kernel.++([payload])
  end

  defp normalize_call_id(%{call_id: id}), do: normalize_call_id(id)
  defp normalize_call_id(%{"call_id" => id}), do: normalize_call_id(id)
  defp normalize_call_id(id) when is_atom(id), do: Atom.to_string(id)
  defp normalize_call_id(id) when is_binary(id), do: id
  defp normalize_call_id(_), do: nil
end
