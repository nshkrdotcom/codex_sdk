defmodule Codex.Thread do
  @moduledoc """
  Represents a Codex conversation thread and exposes turn execution APIs.
  """

  alias Codex.ApprovalError
  alias Codex.Approvals
  alias Codex.Error
  alias Codex.Events
  alias Codex.Options
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
            usage: %{}

  @type t :: %__MODULE__{
          thread_id: String.t() | nil,
          codex_opts: Options.t(),
          thread_opts: ThreadOptions.t(),
          metadata: map(),
          labels: map(),
          continuation_token: String.t() | nil,
          usage: map()
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
          usage: %{}
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
    meta = %{thread_id: thread.thread_id, input: input}
    Telemetry.emit([:codex, :thread, :start], %{system_time: System.system_time()}, meta)
    started_monotonic = System.monotonic_time()

    with {:ok, exec_opts} <- build_exec_options(thread, turn_opts) do
      case Codex.Exec.run(input, exec_opts) do
        {:ok, exec_result} ->
          duration = System.monotonic_time() - started_monotonic

          Telemetry.emit(
            [:codex, :thread, :stop],
            %{duration: duration},
            Map.put(meta, :result, :ok)
          )

          {:ok, finalize_turn(thread, exec_result)}

        {:error, reason} ->
          duration = System.monotonic_time() - started_monotonic

          Telemetry.emit(
            [:codex, :thread, :exception],
            %{duration: duration},
            Map.put(meta, :reason, reason)
          )

          {:error, reason}
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
    with {:ok, exec_opts} <- build_exec_options(thread, turn_opts),
         {:ok, stream} <- Codex.Exec.run_stream(input, exec_opts) do
      {:ok, stream}
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
        with {:ok, processed} <- handle_tool_requests(result) do
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
    {:ok,
     Map.merge(
       %{
         codex_opts: thread.codex_opts,
         thread: thread,
         turn_opts: Map.new(turn_opts),
         continuation_token: thread.continuation_token,
         attachments: thread.thread_opts.attachments
       },
       %{}
     )}
  end

  defp finalize_turn(thread, %{events: events} = exec_result) do
    {updated_thread, final_response, usage} = fold_events(thread, events)

    updated_thread = %{
      updated_thread
      | usage: usage || thread.usage
    }

    %Result{
      thread: updated_thread,
      events: events,
      final_response: final_response,
      usage: usage,
      raw: exec_result,
      attempts: 1
    }
  end

  defp fold_events(thread, events) do
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
                %{"type" => "text", "text" => text}

              %{"text" => text} when is_binary(text) ->
                %{"type" => "text", "text" => text}

              _ ->
                response
            end

          {acc_thread, new_response || response, usage, continuation}

        %Events.ItemCompleted{item: item} ->
          new_response =
            case item do
              %{"type" => "agent_message", "text" => text} ->
                %{"type" => "text", "text" => text}

              _ ->
                response
            end

          {acc_thread, new_response || response, usage, continuation}

        %Events.TurnCompleted{} = completed ->
          new_usage = completed.usage || usage
          new_response = completed.final_response || response

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

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp handle_tool_requests(%Result{} = result) do
    tool_events = Enum.filter(result.events, &match?(%Events.ToolCallRequested{}, &1))

    Enum.reduce_while(tool_events, {:ok, result}, fn event, {:ok, acc_result} ->
      case maybe_invoke_tool(acc_result.thread, event) do
        {:ok, output} ->
          outputs = Map.get(acc_result.raw, :tool_outputs, [])

          updated_raw =
            Map.put(
              acc_result.raw,
              :tool_outputs,
              outputs ++ [%{call_id: event.call_id, output: output}]
            )

          {:cont, {:ok, %Result{acc_result | raw: updated_raw}}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp handle_tool_requests(result), do: {:ok, result}

  defp maybe_invoke_tool(thread, %Events.ToolCallRequested{} = event) do
    context = build_tool_context(thread, event)

    # Prefer approval_hook over approval_policy
    policy_or_hook = thread.thread_opts.approval_hook || thread.thread_opts.approval_policy
    timeout = thread.thread_opts.approval_timeout_ms || 30_000

    case Approvals.review_tool(policy_or_hook, event, context, timeout: timeout) do
      :allow ->
        case Tools.invoke(event.tool_name, event.arguments, context) do
          {:ok, output} ->
            {:ok, output}

          {:error, reason} ->
            {:error,
             Error.new(:tool_failure, "tool #{event.tool_name} failed", %{
               tool: event.tool_name,
               reason: reason
             })}
        end

      {:deny, reason} ->
        {:error, ApprovalError.new(event.tool_name, reason)}
    end
  end

  defp build_tool_context(thread, event) do
    metadata = thread.thread_opts.metadata || %{}

    tool_context =
      metadata[:tool_context] || metadata["tool_context"] || %{}

    %{
      thread: thread,
      metadata: metadata,
      context: tool_context,
      event: event
    }
  end
end
