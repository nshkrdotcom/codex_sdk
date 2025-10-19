defmodule Codex.Thread do
  @moduledoc """
  Represents a Codex conversation thread and exposes turn execution APIs.
  """

  alias Codex.ApprovalError
  alias Codex.Approvals
  alias Codex.Error
  alias Codex.Events
  alias Codex.Items
  alias Codex.Options
  alias Codex.OutputSchemaFile
  alias Codex.Thread.Options, as: ThreadOptions
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
  Executes a blocking turn against the codex engine.
  """
  @spec run(t(), String.t(), map() | keyword()) ::
          {:ok, Result.t()} | {:error, term()}
  def run(%__MODULE__{} = thread, input, turn_opts \\ %{}) when is_binary(input) do
    span_token = make_ref()

    meta = %{
      thread_id: thread.thread_id,
      input: input,
      originator: :sdk,
      span_token: span_token
    }

    Telemetry.emit([:codex, :thread, :start], %{system_time: System.system_time()}, meta)
    started_monotonic = System.monotonic_time()

    with {:ok, exec_opts, cleanup, exec_meta} <- build_exec_options(thread, turn_opts) do
      structured_output? = Map.get(exec_meta, :structured_output?, false)

      try do
        case Codex.Exec.run(input, exec_opts) do
          {:ok, exec_result} ->
            duration = System.monotonic_time() - started_monotonic

            Telemetry.emit(
              [:codex, :thread, :stop],
              %{duration: duration, system_time: System.system_time()},
              Map.put(meta, :result, :ok)
            )

            exec_result = Map.put(exec_result, :structured_output?, structured_output?)

            {:ok, finalize_turn(thread, exec_result, exec_meta)}

          {:error, reason} ->
            duration = System.monotonic_time() - started_monotonic

            Telemetry.emit(
              [:codex, :thread, :exception],
              %{duration: duration, system_time: System.system_time()},
              meta
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
  Executes a turn and returns a stream of events for progressive consumption.

  The stream is lazy; events will not be produced until enumerated.
  """
  @spec run_streamed(t(), String.t(), map() | keyword()) ::
          {:ok, Enumerable.t()} | {:error, term()}
  def run_streamed(%__MODULE__{} = thread, input, turn_opts \\ %{}) when is_binary(input) do
    with {:ok, exec_opts, cleanup, exec_meta} <- build_exec_options(thread, turn_opts) do
      structured_output? = Map.get(exec_meta, :structured_output?, false)

      case Codex.Exec.run_stream(input, exec_opts) do
        {:ok, stream} ->
          wrapped =
            Stream.transform(
              stream,
              fn -> :ok end,
              fn event, acc -> {[maybe_decode_stream_event(event, structured_output?)], acc} end,
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

    do_run_auto(thread, input, turn_opts, max_attempts, backoff, 1, [], %{})
  end

  defp do_run_auto(
         thread,
         input,
         turn_opts,
         max_attempts,
         backoff,
         attempt,
         acc_events,
         acc_usage
       ) do
    case run(thread, input, turn_opts) do
      {:ok, %Result{} = result} ->
        with {:ok, processed} <- handle_tool_requests(result, attempt) do
          merged_events = acc_events ++ processed.events
          merged_usage = merge_usage(acc_usage, processed.usage)

          cond do
            processed.thread.continuation_token && attempt < max_attempts ->
              backoff.(attempt)

              do_run_auto(
                processed.thread,
                input,
                turn_opts,
                max_attempts,
                backoff,
                attempt + 1,
                merged_events,
                merged_usage
              )

            processed.thread.continuation_token ->
              {:error,
               {:max_attempts_reached, max_attempts,
                %{continuation: processed.thread.continuation_token}}}

            true ->
              final_thread = %{processed.thread | usage: merged_usage}

              {:ok,
               %Result{
                 processed
                 | events: merged_events,
                   usage: merged_usage,
                   thread: final_thread,
                   attempts: attempt
               }}
          end
        end

      {:error, _} = error ->
        error
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
      filtered_turn_opts =
        turn_opts_map
        |> Map.delete(:output_schema)
        |> Map.delete("output_schema")

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

      {:ok, exec_opts, cleanup, %{structured_output?: not is_nil(schema)}}
    end
  end

  defp finalize_turn(thread, %{events: events} = exec_result, opts) do
    {updated_thread, final_response, usage} = fold_events(thread, events, opts)

    updated_thread =
      updated_thread
      |> Map.put(:usage, usage || thread.usage)
      |> Map.put(:pending_tool_outputs, [])
      |> Map.put(:pending_tool_failures, [])

    %Result{
      thread: updated_thread,
      events: events,
      final_response: final_response,
      usage: usage,
      raw: exec_result,
      attempts: 1
    }
  end

  defp fold_events(thread, events, opts) do
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

  defp merge_usage(nil, nil), do: %{}
  defp merge_usage(map, nil) when is_map(map), do: map
  defp merge_usage(nil, map) when is_map(map), do: map

  defp merge_usage(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn _key, l, r ->
      cond do
        is_number(l) and is_number(r) -> l + r
        true -> r || l
      end
    end)
  end

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

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp handle_tool_requests(%Result{} = result, attempt) do
    tool_events = Enum.filter(result.events, &match?(%Events.ToolCallRequested{}, &1))

    Enum.reduce_while(tool_events, {:ok, result}, fn event, {:ok, acc_result} ->
      case maybe_invoke_tool(acc_result.thread, event, attempt) do
        {:ok, output} ->
          outputs = Map.get(acc_result.raw, :tool_outputs, [])

          pending_outputs =
            acc_result.thread.pending_tool_outputs ++ [%{call_id: event.call_id, output: output}]

          updated_raw =
            Map.put(
              acc_result.raw,
              :tool_outputs,
              outputs ++ [%{call_id: event.call_id, output: output}]
            )

          updated_thread =
            Map.put(acc_result.thread, :pending_tool_outputs, pending_outputs)

          updated_result = %Result{acc_result | raw: updated_raw, thread: updated_thread}

          {:cont, {:ok, updated_result}}

        {:failure, reason} ->
          failures =
            Map.get(acc_result.raw, :tool_failures, []) ++
              [%{call_id: event.call_id, reason: normalize_tool_failure(reason)}]

          pending_failures =
            acc_result.thread.pending_tool_failures ++
              [%{call_id: event.call_id, reason: normalize_tool_failure(reason)}]

          updated_raw = Map.put(acc_result.raw, :tool_failures, failures)

          updated_thread =
            Map.put(acc_result.thread, :pending_tool_failures, pending_failures)

          updated_result = %Result{acc_result | raw: updated_raw, thread: updated_thread}

          {:cont, {:ok, updated_result}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp handle_tool_requests(result, _attempt), do: {:ok, result}

  defp maybe_invoke_tool(thread, %Events.ToolCallRequested{} = event, attempt) do
    context = build_tool_context(thread, event, attempt)

    # Prefer approval_hook over approval_policy
    policy_or_hook = thread.thread_opts.approval_hook || thread.thread_opts.approval_policy
    timeout = thread.thread_opts.approval_timeout_ms || 30_000

    case Approvals.review_tool(policy_or_hook, event, context, timeout: timeout) do
      :allow ->
        case Tools.invoke(event.tool_name, event.arguments, context) do
          {:ok, output} ->
            {:ok, output}

          {:error, reason} ->
            {:failure,
             Error.new(:tool_failure, "tool #{event.tool_name} failed", %{
               tool: event.tool_name,
               reason: reason
             })}
        end

      {:deny, reason} ->
        {:error, ApprovalError.new(event.tool_name, reason)}
    end
  end

  defp build_tool_context(thread, event, attempt) do
    metadata = thread.thread_opts.metadata || %{}

    tool_context =
      metadata[:tool_context] || metadata["tool_context"] || %{}

    %{
      thread: thread,
      metadata: metadata,
      context: tool_context,
      event: event,
      attempt: attempt,
      retry?: attempt > 1
    }
  end

  defp normalize_tool_failure(%Codex.Error{} = error) do
    %{
      message: error.message,
      kind: error.kind,
      details: error.details || %{}
    }
  end

  defp normalize_tool_failure(value) when is_map(value), do: value
  defp normalize_tool_failure(value) when is_binary(value), do: %{message: value}
  defp normalize_tool_failure(value), do: %{message: inspect(value)}
end
