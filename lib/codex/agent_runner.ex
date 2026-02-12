defmodule Codex.AgentRunner do
  @moduledoc """
  Multi-turn runner that orchestrates agent execution over Codex threads.
  """

  alias Codex.Agent
  alias Codex.Exec
  alias Codex.FileSearch
  alias Codex.Guardrail
  alias Codex.GuardrailError
  alias Codex.Handoff
  alias Codex.Models
  alias Codex.Options
  alias Codex.RunConfig
  alias Codex.RunResultStreaming
  alias Codex.RunResultStreaming.Control, as: StreamingControl
  alias Codex.Session
  alias Codex.StreamEvent.{AgentUpdated, GuardrailResult, RawResponses, RunItem, ToolApproval}
  alias Codex.StreamQueue
  alias Codex.Thread
  alias Codex.ToolGuardrail
  alias Codex.Turn.Result

  defmodule State do
    @moduledoc false

    @enforce_keys [
      :thread,
      :input,
      :agent,
      :run_config,
      :guardrails,
      :turn_opts,
      :backoff,
      :attempt,
      :events,
      :usage
    ]

    defstruct [
      :thread,
      :input,
      :agent,
      :run_config,
      :guardrails,
      :turn_opts,
      :backoff,
      :attempt,
      :events,
      :usage,
      :queue,
      :control
    ]

    @type t :: %__MODULE__{
            thread: Thread.t(),
            input: String.t() | [map()],
            agent: Agent.t(),
            run_config: RunConfig.t(),
            guardrails: map(),
            turn_opts: map() | keyword(),
            backoff: term(),
            attempt: non_neg_integer(),
            events: [term()],
            usage: map(),
            queue: pid() | nil,
            control: pid() | nil
          }
  end

  @spec run(Thread.t(), String.t() | [map()], map() | keyword()) ::
          {:ok, Result.t()} | {:error, term()}
  def run(thread, input, opts \\ %{})

  def run(%Thread{} = thread, input, opts)
      when is_binary(input) or is_list(input) do
    {agent_opts, run_config_opts, turn_opts, backoff} = normalize_opts(opts)

    with {:ok, %Agent{} = agent} <- Agent.new(agent_opts),
         {:ok, %RunConfig{} = run_config} <- RunConfig.new(run_config_opts) do
      tuned_thread =
        thread
        |> apply_model_override(run_config)
        |> apply_tracing_metadata(run_config)
        |> apply_file_search_config(run_config)

      guardrails = build_guardrails(agent, run_config)

      {prepared_input, session, _history} =
        maybe_prepare_session(run_config, input)

      with :ok <-
             run_guardrails(:input, guardrails.input, prepared_input, %{
               agent: agent,
               run_config: run_config
             }) do
        result =
          do_run(%State{
            thread: tuned_thread,
            input: prepared_input,
            agent: agent,
            run_config: run_config,
            guardrails: guardrails,
            turn_opts: turn_opts,
            backoff: backoff || (&default_backoff/1),
            attempt: 1,
            events: [],
            usage: %{}
          })

        maybe_store_session(
          session,
          prepared_input,
          finalize_run_config(run_config, result),
          result
        )
      end
    end
  end

  def run(%Thread{}, input, _opts), do: {:error, {:invalid_input, input}}

  @spec run_streamed(Thread.t(), String.t() | [map()], map() | keyword()) ::
          {:ok, RunResultStreaming.t()} | {:error, term()}
  def run_streamed(thread, input, opts \\ %{})

  def run_streamed(%Thread{} = thread, input, opts)
      when is_binary(input) or is_list(input) do
    {agent_opts, run_config_opts, turn_opts, backoff} = normalize_opts(opts)
    {turn_opts, cancellation_token} = ensure_cancellation_token(turn_opts)

    with {:ok, %Agent{} = agent} <- Agent.new(agent_opts),
         {:ok, %RunConfig{} = run_config} <- RunConfig.new(run_config_opts),
         {:ok, queue} <- StreamQueue.start_link(),
         {:ok, control} <- StreamingControl.start_link() do
      :ok = StreamingControl.attach_queue(control, queue)

      :ok =
        StreamingControl.set_cancel_handler(control, fn
          :immediate -> Exec.cancel(cancellation_token)
          :after_turn -> :ok
        end)

      tuned_thread =
        thread
        |> apply_model_override(run_config)
        |> apply_tracing_metadata(run_config)
        |> apply_file_search_config(run_config)

      guardrails = build_guardrails(agent, run_config)
      {prepared_input, session, history} = maybe_prepare_session(run_config, input)

      start_fun =
        fn ->
          stream_run(%State{
            thread: tuned_thread,
            input: prepared_input,
            agent: agent,
            run_config: run_config,
            guardrails: guardrails,
            turn_opts: turn_opts,
            backoff: backoff || (&default_backoff/1),
            attempt: 1,
            events: [],
            usage: %{},
            queue: queue,
            control: control
          })
          |> maybe_store_session(prepared_input, run_config, session, history)
        end

      {:ok, RunResultStreaming.new(queue, control, start_fun)}
    end
  end

  def run_streamed(%Thread{}, input, _opts), do: {:error, {:invalid_input, input}}

  defp stream_run(%State{} = state) do
    emit_agent_update(state.queue, state.agent, state.run_config)

    guardrail_hook = %{on_result: &emit_guardrail_event(state.queue, &1, &2, &3, &4)}

    case run_guardrails(
           :input,
           state.guardrails.input,
           state.input,
           %{agent: state.agent, run_config: state.run_config},
           guardrail_hook
         ) do
      :ok ->
        do_run_streamed(state)

      {:error, reason} ->
        close_queue(state.queue, {:error, reason})
    end
  end

  defp maybe_store_session(result, _input, _run_config, nil, _history), do: result

  defp maybe_store_session(result, input, %RunConfig{} = run_config, session, _history) do
    maybe_store_session(session, input, finalize_run_config(run_config, result), result)
  end

  defp do_run(%State{} = state) do
    state = %{state | thread: annotate_conversation(state.thread, state.run_config)}

    with {:ok, %Result{} = turn_result} <-
           Thread.run_turn(state.thread, state.input, state.turn_opts),
         {:ok, %Result{} = processed} <- handle_tools(turn_result, state) do
      state = update_after_turn(state, processed)

      tool_results = tool_results_from_raw(processed.raw)

      case check_tool_use_behavior(state.agent, state.run_config, tool_results) do
        {:final, final_output} -> finalize_tool_stop(state, processed, final_output)
        :continue -> continue_run(state, processed, tool_results)
        {:error, _} = error -> error
      end
    end
  end

  defp handle_tools(%Result{} = turn_result, %State{} = state) do
    Thread.handle_tool_requests(turn_result, state.attempt, %{
      tool_input: state.guardrails.tool_input,
      tool_output: state.guardrails.tool_output
    })
  end

  defp update_after_turn(%State{} = state, %Result{} = processed) do
    merged_events = state.events ++ processed.events
    merged_usage = Thread.merge_usage(state.usage, processed.usage)

    run_config = maybe_chain_previous_response_id(state.run_config, processed.last_response_id)

    %{state | events: merged_events, usage: merged_usage, run_config: run_config}
  end

  defp finalize_tool_stop(%State{} = state, %Result{} = processed, final_output) do
    with :ok <-
           run_guardrails(:output, state.guardrails.output, final_output, %{agent: state.agent}) do
      final_thread =
        finalize_processed_thread(processed.thread, state.usage, state.run_config,
          clear_continuation?: true
        )

      {:ok,
       %Result{
         processed
         | events: state.events,
           usage: state.usage,
           thread: final_thread,
           final_response: final_output,
           attempts: state.attempt
       }}
    end
  end

  defp continue_run(%State{} = state, %Result{} = processed, tool_results) do
    next_turn_opts = maybe_reset_tool_choice(state.agent, state.turn_opts, tool_results) || %{}

    case processed.thread.continuation_token do
      token when is_binary(token) and token != "" ->
        continue_with_continuation(state, processed, token, next_turn_opts)

      _ ->
        finalize_without_continuation(state, processed)
    end
  end

  defp continue_with_continuation(%State{} = state, %Result{} = processed, token, next_turn_opts) do
    if state.attempt < state.run_config.max_turns do
      safe_backoff(state.backoff, state.attempt)
      next_thread = %{processed.thread | usage: state.usage}

      do_run(%State{
        state
        | thread: next_thread,
          turn_opts: next_turn_opts,
          attempt: state.attempt + 1
      })
    else
      {:error, {:max_turns_exceeded, state.run_config.max_turns, %{continuation: token}}}
    end
  end

  defp finalize_without_continuation(%State{} = state, %Result{} = processed) do
    with :ok <-
           run_guardrails(:output, state.guardrails.output, processed.final_response, %{
             agent: state.agent
           }) do
      final_thread =
        processed.thread
        |> Map.put(:usage, state.usage)
        |> annotate_conversation(state.run_config)

      {:ok,
       %Result{
         processed
         | events: state.events,
           usage: state.usage,
           thread: final_thread,
           attempts: state.attempt
       }}
    end
  end

  defp do_run_streamed(%State{queue: queue, control: control} = state)
       when is_pid(queue) and is_pid(control) do
    case StreamingControl.cancel_mode(state.control) do
      :immediate -> close_queue(state.queue, {:error, :cancelled})
      _ -> do_run_streamed_active(state)
    end
  end

  defp do_run_streamed_active(%State{} = state) do
    case Thread.run_turn_streamed(state.thread, state.input, state.turn_opts) do
      {:ok, stream} -> do_run_streamed_with_stream(state, stream)
      {:error, _reason} = error -> close_queue(state.queue, error)
    end
  end

  defp do_run_streamed_with_stream(%State{} = state, stream) do
    hooks = stream_hooks(state)
    structured_output? = structured_output?(state.turn_opts)

    try do
      {events, status} = collect_stream_events(stream, state.queue, state.control)

      {updated_thread, response, usage} =
        Thread.reduce_events(state.thread, events, %{structured_output?: structured_output?})

      merged_usage = Thread.merge_usage(state.usage, usage)
      StreamingControl.put_usage(state.control, merged_usage)

      StreamQueue.push(state.queue, %RawResponses{events: events, usage: usage})

      turn_result =
        streamed_turn_result(
          updated_thread,
          events,
          response,
          usage,
          state.attempt,
          structured_output?
        )

      case status do
        :cancelled ->
          close_queue(state.queue, {:ok, turn_result})

        _ ->
          handle_streamed_continuation(
            state,
            turn_result,
            hooks
          )
      end
    rescue
      error ->
        close_queue(state.queue, {:error, error})
    catch
      kind, reason ->
        close_queue(state.queue, {:error, {kind, reason}})
    end
  end

  defp stream_hooks(%State{} = state) do
    %{
      on_guardrail: &emit_guardrail_event(state.queue, &1, &2, &3, &4),
      on_approval: &emit_approval_event(state.queue, &1, &2, &3)
    }
  end

  defp structured_output?(turn_opts) do
    schema =
      turn_opts
      |> Map.new()
      |> then(fn map -> Map.get(map, :output_schema) || Map.get(map, "output_schema") end)

    not is_nil(schema)
  end

  defp streamed_turn_result(updated_thread, events, response, usage, attempt, structured_output?) do
    %Result{
      thread: updated_thread,
      events: events,
      final_response: response,
      usage: usage,
      raw: %{events: events, structured_output?: structured_output?},
      attempts: attempt,
      last_response_id: Thread.last_response_id(events)
    }
  end

  defp handle_streamed_continuation(%State{} = state, %Result{} = turn_result, hooks) do
    case handle_tools_streamed(turn_result, state, hooks) do
      {:ok, %Result{} = processed} ->
        state = update_after_turn(state, processed)
        StreamingControl.put_usage(state.control, state.usage)

        tool_results = tool_results_from_raw(processed.raw)

        case check_tool_use_behavior(state.agent, state.run_config, tool_results) do
          {:final, final_output} -> finalize_streamed_tool_stop(state, processed, final_output)
          :continue -> continue_streamed_run(state, processed, tool_results, hooks)
          {:error, _} = error -> close_queue(state.queue, error)
        end

      {:error, _reason} = error ->
        close_queue(state.queue, error)
    end
  end

  defp handle_tools_streamed(%Result{} = turn_result, %State{} = state, hooks) do
    Thread.handle_tool_requests(turn_result, state.attempt, %{
      tool_input: state.guardrails.tool_input,
      tool_output: state.guardrails.tool_output,
      hooks: hooks
    })
  end

  defp finalize_streamed_tool_stop(%State{} = state, %Result{} = processed, final_output) do
    case run_guardrails(
           :output,
           state.guardrails.output,
           final_output,
           %{agent: state.agent},
           %{on_result: &emit_guardrail_event(state.queue, &1, &2, &3, &4)}
         ) do
      :ok ->
        final_thread =
          finalize_processed_thread(processed.thread, state.usage, state.run_config,
            clear_continuation?: true
          )

        close_queue(
          state.queue,
          {:ok,
           %Result{
             processed
             | events: state.events,
               usage: state.usage,
               thread: final_thread,
               final_response: final_output,
               attempts: state.attempt
           }}
        )

      {:error, reason} ->
        close_queue(state.queue, {:error, reason})
    end
  end

  defp continue_streamed_run(%State{} = state, %Result{} = processed, tool_results, hooks) do
    next_turn_opts = maybe_reset_tool_choice(state.agent, state.turn_opts, tool_results) || %{}

    case next_stream_action(state, processed) do
      :stop_after_turn ->
        close_queue(
          state.queue,
          {:ok,
           %Result{
             processed
             | events: state.events,
               usage: state.usage,
               thread: %{processed.thread | usage: state.usage},
               attempts: state.attempt
           }}
        )

      :continue ->
        next_thread = %{processed.thread | usage: state.usage}

        do_run_streamed(%State{
          state
          | thread: next_thread,
            turn_opts: next_turn_opts,
            attempt: state.attempt + 1
        })

      {:error, continuation} ->
        close_queue(
          state.queue,
          {:error,
           {:max_turns_exceeded, state.run_config.max_turns, %{continuation: continuation}}}
        )

      :final ->
        finalize_streamed_without_continuation(state, processed, hooks)
    end
  end

  defp next_stream_action(%State{} = state, %Result{} = processed) do
    cond do
      StreamingControl.cancel_mode(state.control) == :after_turn ->
        :stop_after_turn

      is_binary(processed.thread.continuation_token) and processed.thread.continuation_token != "" and
          state.attempt < state.run_config.max_turns ->
        safe_backoff(state.backoff, state.attempt)
        :continue

      is_binary(processed.thread.continuation_token) and processed.thread.continuation_token != "" ->
        {:error, processed.thread.continuation_token}

      true ->
        :final
    end
  end

  defp finalize_processed_thread(%Thread{} = thread, usage, run_config, opts) do
    thread
    |> maybe_clear_continuation(Keyword.get(opts, :clear_continuation?, false))
    |> Map.put(:usage, usage)
    |> Thread.clear_pending_tool_payloads()
    |> annotate_conversation(run_config)
  end

  defp maybe_clear_continuation(%Thread{} = thread, true) do
    %{thread | continuation_token: nil}
  end

  defp maybe_clear_continuation(%Thread{} = thread, false), do: thread

  defp finalize_streamed_without_continuation(%State{} = state, %Result{} = processed, _hooks) do
    case run_guardrails(
           :output,
           state.guardrails.output,
           processed.final_response,
           %{agent: state.agent},
           %{on_result: &emit_guardrail_event(state.queue, &1, &2, &3, &4)}
         ) do
      :ok ->
        final_thread =
          processed.thread
          |> Map.put(:usage, state.usage)
          |> annotate_conversation(state.run_config)

        close_queue(
          state.queue,
          {:ok,
           %Result{
             processed
             | events: state.events,
               usage: state.usage,
               thread: final_thread,
               attempts: state.attempt
           }}
        )

      {:error, reason} ->
        close_queue(state.queue, {:error, reason})
    end
  end

  defp close_queue(nil, result), do: result

  defp close_queue(queue, {:error, reason} = error) when is_pid(queue) do
    if stream_error?(reason) do
      StreamQueue.close(queue, error)
    else
      StreamQueue.close(queue)
    end

    error
  end

  defp close_queue(queue, result) when is_pid(queue) do
    StreamQueue.close(queue)
    result
  end

  defp stream_error?(%Codex.TransportError{}), do: true
  defp stream_error?(%Codex.Error{}), do: true
  defp stream_error?(%Codex.ApprovalError{}), do: false
  defp stream_error?(%Codex.GuardrailError{}), do: false
  defp stream_error?(reason) when is_exception(reason), do: true
  defp stream_error?(_reason), do: false

  defp collect_stream_events(stream, queue, control) do
    stream
    |> Enum.reduce_while({[], :ok}, fn event, {acc, _status} ->
      emit_run_item(queue, event)

      case StreamingControl.cancel_mode(control) do
        :immediate -> {:halt, {[event | acc], :cancelled}}
        _ -> {:cont, {[event | acc], :ok}}
      end
    end)
    |> then(fn {events, status} -> {Enum.reverse(events), status} end)
  end

  defp emit_agent_update(queue, agent, run_config) do
    StreamQueue.push(queue, %AgentUpdated{agent: agent, run_config: run_config})
  end

  defp emit_run_item(queue, event) do
    StreamQueue.push(queue, %RunItem{event: event, type: normalize_event_type(event)})
  end

  defp emit_guardrail_event(queue, stage, guardrail, result, message) do
    guardrail_name = Map.get(guardrail, :name)

    StreamQueue.push(queue, %GuardrailResult{
      stage: stage,
      guardrail: guardrail_name,
      result: result,
      message: message
    })
  end

  defp emit_approval_event(queue, event, decision, reason) do
    StreamQueue.push(queue, %ToolApproval{
      tool_name: Map.get(event, :tool_name),
      call_id: Map.get(event, :call_id),
      decision: decision,
      reason: reason
    })
  end

  defp normalize_event_type(%Codex.Events.ThreadStarted{}), do: :thread_started
  defp normalize_event_type(%Codex.Events.TurnStarted{}), do: :turn_started
  defp normalize_event_type(%Codex.Events.TurnContinuation{}), do: :turn_continuation
  defp normalize_event_type(%Codex.Events.TurnCompleted{}), do: :turn_completed
  defp normalize_event_type(%Codex.Events.ItemCompleted{}), do: :item_completed
  defp normalize_event_type(%Codex.Events.ItemStarted{}), do: :item_started
  defp normalize_event_type(%Codex.Events.ItemUpdated{}), do: :item_updated
  defp normalize_event_type(%Codex.Events.ItemAgentMessageDelta{}), do: :item_delta
  defp normalize_event_type(%Codex.Events.ItemInputTextDelta{}), do: :item_delta
  defp normalize_event_type(%Codex.Events.ToolCallRequested{}), do: :tool_call
  defp normalize_event_type(%Codex.Events.ToolCallCompleted{}), do: :tool_call_completed
  defp normalize_event_type(%Codex.Events.TurnDiffUpdated{}), do: :turn_diff
  defp normalize_event_type(%Codex.Events.TurnCompaction{}), do: :turn_compaction
  defp normalize_event_type(%Codex.Events.ThreadTokenUsageUpdated{}), do: :usage
  defp normalize_event_type(_), do: :event

  defp normalize_opts(opts) when is_list(opts), do: opts |> Map.new() |> normalize_opts()

  defp normalize_opts(%RunConfig{} = config), do: {%{}, config, %{}, nil}
  defp normalize_opts(%Agent{} = agent), do: {agent, %{}, %{}, nil}

  defp normalize_opts(opts) when is_map(opts) do
    agent_opts = Map.get(opts, :agent, Map.get(opts, "agent", %{}))

    max_turns =
      Map.get(opts, :max_turns) ||
        Map.get(opts, "max_turns")

    run_config_opts =
      Map.get(opts, :run_config, Map.get(opts, "run_config", %{}))
      |> case do
        %RunConfig{} = config when is_nil(max_turns) -> config
        %RunConfig{} = config -> %{config | max_turns: max_turns}
        other when is_nil(max_turns) -> other
        other -> Map.new(other) |> Map.put(:max_turns, max_turns)
      end

    backoff = Map.get(opts, :backoff, Map.get(opts, "backoff"))

    turn_opts =
      opts
      |> Map.get(:turn_opts, Map.get(opts, "turn_opts"))
      |> normalize_turn_opts(opts)
      |> Map.delete(:agent)
      |> Map.delete("agent")
      |> Map.delete(:run_config)
      |> Map.delete("run_config")
      |> Map.delete(:max_turns)
      |> Map.delete("max_turns")
      |> Map.delete(:backoff)
      |> Map.delete("backoff")
      |> Map.delete(:turn_opts)
      |> Map.delete("turn_opts")

    {agent_opts, run_config_opts, turn_opts, backoff}
  end

  defp normalize_opts(_opts), do: {%{}, %{}, %{}, nil}

  defp ensure_cancellation_token(turn_opts) when is_map(turn_opts) do
    case Map.get(turn_opts, :cancellation_token, Map.get(turn_opts, "cancellation_token")) do
      token when is_binary(token) and token != "" ->
        {turn_opts, token}

      _ ->
        token = "codex_sdk_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
        {Map.put(turn_opts, :cancellation_token, token), token}
    end
  end

  defp normalize_turn_opts(nil, fallback),
    do: Map.drop(fallback, [:agent, :run_config, :max_turns, :backoff])

  defp normalize_turn_opts(opts, _fallback) when is_list(opts), do: Map.new(opts)
  defp normalize_turn_opts(opts, _fallback) when is_map(opts), do: opts

  defp normalize_turn_opts(_opts, fallback),
    do: Map.drop(fallback, [:agent, :run_config, :max_turns, :backoff])

  defp build_guardrails(agent, run_config) do
    %{
      input: merge_guardrails(agent.input_guardrails, run_config.input_guardrails),
      output: merge_guardrails(agent.output_guardrails, run_config.output_guardrails),
      tool_input: List.wrap(agent.tool_input_guardrails),
      tool_output: List.wrap(agent.tool_output_guardrails)
    }
  end

  defp merge_guardrails(left, right), do: List.wrap(left) ++ List.wrap(right)

  defp run_guardrails(stage, guardrails, payload, context, hooks \\ %{})

  defp run_guardrails(_stage, guardrails, _payload, _context, _hooks)
       when guardrails in [nil, []],
       do: :ok

  defp run_guardrails(stage, guardrails, payload, context, hooks) do
    {parallel, sequential} = Enum.split_with(guardrails, & &1.run_in_parallel)

    case run_guardrails_sequential(stage, sequential, payload, context, hooks) do
      :ok -> run_guardrails_parallel(stage, parallel, payload, context, hooks)
      {:error, reason} -> {:error, reason}
    end
  end

  defp run_guardrails_sequential(_stage, [], _payload, _context, _hooks), do: :ok

  defp run_guardrails_sequential(stage, guardrails, payload, context, hooks) do
    Enum.reduce_while(guardrails, :ok, fn guardrail, :ok ->
      case run_guardrail(stage, guardrail, payload, context, hooks) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp run_guardrails_parallel(_stage, [], _payload, _context, _hooks), do: :ok

  defp run_guardrails_parallel(stage, guardrails, payload, context, hooks) do
    guardrails
    |> Task.async_stream(
      fn guardrail ->
        run_guardrail(stage, guardrail, payload, context, hooks)
      end,
      ordered: true
    )
    |> Enum.reduce_while(:ok, fn
      {:ok, :ok}, :ok ->
        {:cont, :ok}

      {:ok, {:error, reason}}, :ok ->
        {:halt, {:error, reason}}

      {:exit, reason}, :ok ->
        {:halt,
         {:error,
          %GuardrailError{
            stage: stage,
            guardrail: "parallel_guardrail",
            message: inspect(reason),
            type: :tripwire
          }}}
    end)
  end

  defp run_guardrail(stage, guardrail, payload, context, hooks)

  defp run_guardrail(stage, %Guardrail{} = guardrail, payload, context, hooks) do
    case Guardrail.run(guardrail, payload, context) do
      :ok ->
        notify_guardrail(hooks, stage, guardrail, :ok, nil)
        :ok

      {:reject, message} ->
        notify_guardrail(hooks, stage, guardrail, :reject, message)

        {:error,
         %GuardrailError{
           stage: stage,
           guardrail: guardrail.name,
           message: message,
           type: :reject
         }}

      {:tripwire, message} ->
        notify_guardrail(hooks, stage, guardrail, :tripwire, message)

        {:error,
         %GuardrailError{
           stage: stage,
           guardrail: guardrail.name,
           message: message,
           type: :tripwire
         }}
    end
  end

  defp run_guardrail(_stage, %ToolGuardrail{} = guardrail, payload, context, hooks) do
    tool_stage = if guardrail.stage == :output, do: :tool_output, else: :tool_input

    case ToolGuardrail.run(guardrail, Map.get(context, :event), payload, context) do
      :ok ->
        notify_guardrail(hooks, tool_stage, guardrail, :ok, nil)
        :ok

      {:reject, message} ->
        notify_guardrail(hooks, tool_stage, guardrail, :reject, message)

        {:error,
         %GuardrailError{
           stage: tool_stage,
           guardrail: guardrail.name,
           message: message,
           type: if(guardrail.behavior == :raise_exception, do: :tripwire, else: :reject)
         }}

      {:tripwire, message} ->
        notify_guardrail(hooks, tool_stage, guardrail, :tripwire, message)

        {:error,
         %GuardrailError{
           stage: tool_stage,
           guardrail: guardrail.name,
           message: message,
           type: :tripwire
         }}
    end
  end

  defp run_guardrail(_stage, _guardrail, _payload, _context, _hooks), do: :ok

  defp notify_guardrail(%{on_result: fun}, stage, guardrail, result, message)
       when is_function(fun, 4) do
    fun.(stage, guardrail, result, message)
  end

  defp notify_guardrail(_hooks, _stage, _guardrail, _result, _message), do: :ok

  @doc """
  Resolves and filters handoffs configured on the agent, returning only enabled entries.
  """
  @spec get_handoffs(Agent.t(), map()) :: {:ok, [Handoff.t()]}
  def get_handoffs(%Agent{} = agent, context \\ %{}) do
    handoffs =
      agent.handoffs
      |> List.wrap()
      |> Enum.map(&normalize_handoff(&1, agent))
      |> Enum.reject(&is_nil/1)
      |> Enum.filter(&Handoff.enabled?(&1, context, &1.agent || agent))

    {:ok, handoffs}
  end

  defp normalize_handoff(%Handoff{} = handoff, _agent), do: handoff
  defp normalize_handoff(%Agent{} = agent, _parent), do: Handoff.wrap(agent)
  defp normalize_handoff(_other, _agent), do: nil

  defp tool_results_from_raw(raw) do
    raw
    |> Map.get(:tool_outputs, Map.get(raw, "tool_outputs", []))
    |> List.wrap()
    |> Enum.map(&normalize_tool_result/1)
  end

  defp normalize_tool_result(%{} = result) do
    %{
      call_id: Map.get(result, :call_id) || Map.get(result, "call_id"),
      tool_name: Map.get(result, :tool_name) || Map.get(result, "tool_name"),
      output: Map.get(result, :output) || Map.get(result, "output")
    }
  end

  defp normalize_tool_result(other), do: %{call_id: nil, tool_name: nil, output: other}

  @doc false
  @spec check_tool_use_behavior(Agent.t(), RunConfig.t(), [map()]) ::
          :continue | {:final, term()} | {:error, term()}
  def check_tool_use_behavior(_agent, _config, []), do: :continue

  def check_tool_use_behavior(%Agent{tool_use_behavior: :run_llm_again}, _config, _results),
    do: :continue

  def check_tool_use_behavior(%Agent{tool_use_behavior: :stop_on_first_tool}, _config, results) do
    first = Enum.find(results, &match?(%{}, &1)) || List.first(results)
    {:final, first && Map.get(first, :output)}
  end

  def check_tool_use_behavior(
        %Agent{tool_use_behavior: %{stop_at_tool_names: names}},
        _config,
        results
      )
      when is_list(names) do
    names = Enum.map(names, &to_string/1)

    case Enum.find(results, fn result ->
           tool = result |> Map.get(:tool_name) |> to_string()
           tool in names
         end) do
      nil -> :continue
      match -> {:final, Map.get(match, :output)}
    end
  end

  def check_tool_use_behavior(%Agent{tool_use_behavior: fun} = agent, config, results)
      when is_function(fun) do
    context = %{agent: agent, run_config: config}

    case safe_apply(fun, context, results) do
      %{is_final_output: true} = outcome ->
        {:final, Map.get(outcome, :final_output)}

      %{is_final_output: false} ->
        :continue

      %{is_final_output: other} = outcome when is_boolean(other) ->
        if other, do: {:final, Map.get(outcome, :final_output)}, else: :continue

      other ->
        {:error, {:invalid_tool_use_behavior_result, other}}
    end
  end

  def check_tool_use_behavior(%Agent{tool_use_behavior: other}, _config, _results),
    do: {:error, {:invalid_tool_use_behavior, other}}

  defp safe_apply(fun, context, results) when is_function(fun, 2), do: fun.(context, results)
  defp safe_apply(fun, _context, results) when is_function(fun, 1), do: fun.(results)
  defp safe_apply(fun, _context, _results) when is_function(fun, 0), do: fun.()

  @doc false
  @spec maybe_reset_tool_choice(Agent.t(), map() | nil, [map()]) :: map() | nil
  def maybe_reset_tool_choice(%Agent{reset_tool_choice: false}, turn_opts, _tool_results),
    do: turn_opts

  def maybe_reset_tool_choice(_agent, turn_opts, _tool_results) when turn_opts in [%{}, nil],
    do: turn_opts

  def maybe_reset_tool_choice(_agent, turn_opts, []), do: turn_opts

  def maybe_reset_tool_choice(%Agent{reset_tool_choice: true}, turn_opts, _tool_results)
      when is_map(turn_opts) do
    tool_choice = Map.get(turn_opts, :tool_choice) || Map.get(turn_opts, "tool_choice")

    if is_nil(tool_choice) do
      turn_opts
    else
      turn_opts
      |> Map.put(:tool_choice, nil)
      |> Map.delete("tool_choice")
    end
  end

  def maybe_reset_tool_choice(_agent, turn_opts, _tool_results), do: turn_opts

  defp maybe_prepare_session(%RunConfig{session: nil}, input), do: {input, nil, []}

  defp maybe_prepare_session(
         %RunConfig{session: session, session_input_callback: callback},
         input
       ) do
    case Session.load(session) do
      {:ok, history} ->
        prepared = apply_session_callback(callback, input, history)
        {prepared, session, history}

      {:error, _reason} ->
        {input, session, []}
    end
  end

  defp apply_session_callback(nil, input, _history), do: input

  defp apply_session_callback(fun, input, history) when is_function(fun) do
    case safe_session_callback(fun, input, history) do
      {:ok, new_input} when is_binary(new_input) or is_list(new_input) -> new_input
      {:ok, new_input, _ctx} when is_binary(new_input) or is_list(new_input) -> new_input
      value when is_binary(value) or is_list(value) -> value
      _ -> input
    end
  end

  defp safe_session_callback(fun, input, history) when is_function(fun, 3),
    do: fun.(input, history, %{})

  defp safe_session_callback(fun, input, history) when is_function(fun, 2),
    do: fun.(input, history)

  defp safe_session_callback(fun, input, _history) when is_function(fun, 1), do: fun.(input)
  defp safe_session_callback(fun, _input, _history) when is_function(fun, 0), do: fun.()

  defp maybe_store_session(nil, _input, _run_config, result), do: result

  defp maybe_store_session(session, input, %RunConfig{} = run_config, {:ok, %Result{} = result}) do
    entry = %{
      input: input,
      response: result.final_response,
      conversation_id: run_config.conversation_id || result.thread.thread_id,
      previous_response_id: run_config.previous_response_id
    }

    _ = Session.save(session, entry)
    {:ok, result}
  end

  defp maybe_store_session(_session, _input, _run_config, other), do: other

  defp finalize_run_config(%RunConfig{} = run_config, {:ok, %Result{} = result}) do
    maybe_chain_previous_response_id(run_config, result.last_response_id)
  end

  defp finalize_run_config(%RunConfig{} = run_config, _other), do: run_config

  defp maybe_chain_previous_response_id(
         %RunConfig{auto_previous_response_id: true} = run_config,
         value
       )
       when is_binary(value) and value != "" do
    %{run_config | previous_response_id: value}
  end

  defp maybe_chain_previous_response_id(%RunConfig{} = run_config, _value), do: run_config

  defp apply_model_override(%Thread{codex_opts: %Options{} = opts} = thread, %RunConfig{
         model: model
       }) do
    if is_binary(model) and model != "" do
      coerced = Models.coerce_reasoning_effort(model, opts.reasoning_effort)
      %{thread | codex_opts: %{opts | model: model, reasoning_effort: coerced}}
    else
      thread
    end
  end

  defp apply_model_override(thread, _run_config), do: thread

  defp apply_tracing_metadata(%Thread{} = thread, %RunConfig{} = run_config) do
    tracing_meta =
      %{}
      |> maybe_put(:workflow, run_config.workflow)
      |> maybe_put(:group, run_config.group)
      |> maybe_put(:trace_id, run_config.trace_id)
      |> maybe_put(:trace_sensitive, run_config.trace_include_sensitive_data)
      |> maybe_put(:tracing_disabled, run_config.tracing_disabled)

    updated_metadata =
      thread.metadata
      |> Map.merge(tracing_meta, fn _key, existing, updated -> updated || existing end)

    Map.put(thread, :metadata, updated_metadata)
  end

  defp apply_file_search_config(%Thread{thread_opts: thread_opts} = thread, %RunConfig{} = config) do
    merged = FileSearch.merge(thread_opts.file_search, config.file_search)

    %{thread | thread_opts: %{thread_opts | file_search: merged}}
  end

  defp apply_file_search_config(thread, _run_config), do: thread

  defp safe_backoff(fun, attempt) when is_function(fun, 1), do: fun.(attempt)
  defp safe_backoff(_fun, _attempt), do: :ok

  defp default_backoff(_attempt), do: :ok

  defp annotate_conversation(thread, %RunConfig{} = run_config) do
    conversation_meta =
      %{}
      |> maybe_put(:conversation_id, run_config.conversation_id)
      |> maybe_put(:previous_response_id, run_config.previous_response_id)

    updated_metadata =
      thread.metadata
      |> Map.merge(conversation_meta)

    Map.put(thread, :metadata, updated_metadata)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
