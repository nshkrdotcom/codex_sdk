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
    thread = maybe_reset_for_new(thread, input)
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
            events = exec_result.events
            failure = extract_turn_failure(events)
            early_exit? = early_exit?(events)

            Telemetry.emit(
              [:codex, :thread, :stop],
              %{duration: duration, system_time: System.system_time()},
              meta
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
    thread = maybe_reset_for_new(thread, input)

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
    {updated_thread, final_response, usage} = fold_events(thread, events, opts)

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

    warnings =
      Map.get(event, :sandbox_warnings) || Map.get(event, "sandbox_warnings") ||
        Map.get(event, :warnings) || Map.get(event, "warnings")

    capabilities = Map.get(event, :capabilities) || Map.get(event, "capabilities")

    %{
      thread: thread,
      metadata: metadata,
      context: tool_context,
      event: event,
      attempt: attempt,
      retry?: attempt > 1
    }
    |> maybe_put(:capabilities, capabilities)
    |> maybe_put(:sandbox_warnings, warnings)
  end

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
end
