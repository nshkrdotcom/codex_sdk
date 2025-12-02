defmodule Codex.AgentRunner do
  @moduledoc """
  Multi-turn runner that orchestrates agent execution over Codex threads.
  """

  alias Codex.Agent
  alias Codex.FileSearch
  alias Codex.Guardrail
  alias Codex.GuardrailError
  alias Codex.Handoff
  alias Codex.Options
  alias Codex.RunResultStreaming
  alias Codex.RunResultStreaming.Control, as: StreamingControl
  alias Codex.RunConfig
  alias Codex.Session
  alias Codex.StreamEvent.{AgentUpdated, GuardrailResult, RunItem, RawResponses, ToolApproval}
  alias Codex.StreamQueue
  alias Codex.ToolGuardrail
  alias Codex.Thread
  alias Codex.Turn.Result

  @spec run(Thread.t(), String.t(), map() | keyword()) ::
          {:ok, Result.t()} | {:error, term()}
  def run(%Thread{} = thread, input, opts \\ %{}) when is_binary(input) do
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
          do_run(
            tuned_thread,
            prepared_input,
            agent,
            run_config,
            guardrails,
            turn_opts,
            backoff || (&default_backoff/1),
            1,
            [],
            %{}
          )

        maybe_store_session(session, prepared_input, run_config, result)
      end
    end
  end

  @spec run_streamed(Thread.t(), String.t(), map() | keyword()) ::
          {:ok, RunResultStreaming.t()} | {:error, term()}
  def run_streamed(%Thread{} = thread, input, opts \\ %{}) when is_binary(input) do
    {agent_opts, run_config_opts, turn_opts, backoff} = normalize_opts(opts)

    with {:ok, %Agent{} = agent} <- Agent.new(agent_opts),
         {:ok, %RunConfig{} = run_config} <- RunConfig.new(run_config_opts),
         {:ok, queue} <- StreamQueue.start_link(),
         {:ok, control} <- StreamingControl.start_link() do
      tuned_thread =
        thread
        |> apply_model_override(run_config)
        |> apply_tracing_metadata(run_config)
        |> apply_file_search_config(run_config)

      guardrails = build_guardrails(agent, run_config)
      {prepared_input, session, history} = maybe_prepare_session(run_config, input)

      start_fun =
        fn ->
          stream_run(
            tuned_thread,
            prepared_input,
            agent,
            run_config,
            guardrails,
            turn_opts,
            backoff || (&default_backoff/1),
            queue,
            control,
            session,
            history
          )
        end

      {:ok, RunResultStreaming.new(queue, control, start_fun)}
    end
  end

  defp stream_run(
         thread,
         input,
         agent,
         run_config,
         guardrails,
         turn_opts,
         backoff,
         queue,
         control,
         session,
         _history
       ) do
    emit_agent_update(queue, agent, run_config)

    guardrail_hook = %{on_result: &emit_guardrail_event(queue, &1, &2, &3, &4)}

    with :ok <-
           run_guardrails(
             :input,
             guardrails.input,
             input,
             %{agent: agent, run_config: run_config},
             guardrail_hook
           ) do
      result =
        do_run_streamed(
          thread,
          input,
          agent,
          run_config,
          guardrails,
          turn_opts,
          backoff,
          1,
          [],
          %{},
          queue,
          control
        )

      maybe_store_session(session, input, run_config, result)
    else
      {:error, reason} ->
        StreamQueue.close(queue)
        {:error, reason}
    end
  end

  defp do_run(
         thread,
         input,
         agent,
         run_config,
         guardrails,
         turn_opts,
         backoff,
         attempt,
         acc_events,
         acc_usage
       ) do
    case Thread.run_turn(thread, input, turn_opts) do
      {:ok, %Result{} = result} ->
        with {:ok, processed} <-
               Thread.handle_tool_requests(result, attempt, %{
                 tool_input: guardrails.tool_input,
                 tool_output: guardrails.tool_output
               }) do
          tool_results = tool_results_from_raw(processed.raw)
          merged_events = acc_events ++ processed.events
          merged_usage = Thread.merge_usage(acc_usage, processed.usage)

          case check_tool_use_behavior(agent, run_config, tool_results) do
            {:final, final_output} ->
              with :ok <-
                     run_guardrails(:output, guardrails.output, final_output, %{agent: agent}) do
                final_thread =
                  processed.thread
                  |> Map.put(:continuation_token, nil)
                  |> Map.put(:usage, merged_usage)
                  |> Map.put(:pending_tool_outputs, [])
                  |> Map.put(:pending_tool_failures, [])
                  |> annotate_conversation(run_config)

                {:ok,
                 %Result{
                   processed
                   | events: merged_events,
                     usage: merged_usage,
                     thread: final_thread,
                     final_response: final_output,
                     attempts: attempt
                 }}
              end

            {:error, _} = error ->
              error

            :continue ->
              next_turn_opts = maybe_reset_tool_choice(agent, turn_opts, tool_results)
              next_turn_opts = next_turn_opts || %{}

              cond do
                processed.thread.continuation_token && attempt < run_config.max_turns ->
                  safe_backoff(backoff, attempt)
                  next_thread = %{processed.thread | usage: merged_usage}

                  do_run(
                    next_thread,
                    input,
                    agent,
                    run_config,
                    guardrails,
                    next_turn_opts,
                    backoff,
                    attempt + 1,
                    merged_events,
                    merged_usage
                  )

                processed.thread.continuation_token ->
                  {:error,
                   {:max_turns_exceeded, run_config.max_turns,
                    %{continuation: processed.thread.continuation_token}}}

                true ->
                  with :ok <-
                         run_guardrails(
                           :output,
                           guardrails.output,
                           processed.final_response,
                           %{agent: agent}
                         ) do
                    final_thread =
                      processed.thread
                      |> Map.put(:usage, merged_usage)
                      |> annotate_conversation(run_config)

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
          end
        end

      {:error, _} = error ->
        error
    end
  end

  defp do_run_streamed(
         thread,
         input,
         agent,
         run_config,
         guardrails,
         turn_opts,
         backoff,
         attempt,
         acc_events,
         acc_usage,
         queue,
         control
       ) do
    case StreamingControl.cancel_mode(control) do
      :immediate ->
        StreamQueue.close(queue)
        {:error, :cancelled}

      _ ->
        case Thread.run_turn_streamed(thread, input, turn_opts) do
          {:ok, stream} ->
            hooks = %{
              on_guardrail: &emit_guardrail_event(queue, &1, &2, &3, &4),
              on_approval: &emit_approval_event(queue, &1, &2, &3)
            }

            structured? =
              turn_opts
              |> Map.new()
              |> then(fn map ->
                Map.get(map, :output_schema) || Map.get(map, "output_schema")
              end)

            {events, status} = collect_stream_events(stream, queue, control)

            {updated_thread, response, usage} =
              Thread.reduce_events(thread, events, %{structured_output?: not is_nil(structured?)})

            merged_usage = Thread.merge_usage(acc_usage, usage)
            StreamingControl.put_usage(control, merged_usage)

            StreamQueue.push(queue, %RawResponses{events: events, usage: usage})

            turn_result = %Result{
              thread: updated_thread,
              events: events,
              final_response: response,
              usage: usage,
              raw: %{events: events, structured_output?: not is_nil(structured?)},
              attempts: attempt
            }

            if status == :cancelled do
              StreamQueue.close(queue)
              {:ok, turn_result}
            else
              with {:ok, processed} <-
                     Thread.handle_tool_requests(turn_result, attempt, %{
                       tool_input: guardrails.tool_input,
                       tool_output: guardrails.tool_output,
                       hooks: hooks
                     }) do
                tool_results = tool_results_from_raw(processed.raw)
                merged_events = acc_events ++ processed.events
                merged_usage = Thread.merge_usage(acc_usage, processed.usage)
                StreamingControl.put_usage(control, merged_usage)

                case check_tool_use_behavior(agent, run_config, tool_results) do
                  {:final, final_output} ->
                    case run_guardrails(
                           :output,
                           guardrails.output,
                           final_output,
                           %{agent: agent},
                           %{on_result: &emit_guardrail_event(queue, &1, &2, &3, &4)}
                         ) do
                      :ok ->
                        final_thread =
                          processed.thread
                          |> Map.put(:continuation_token, nil)
                          |> Map.put(:usage, merged_usage)
                          |> Map.put(:pending_tool_outputs, [])
                          |> Map.put(:pending_tool_failures, [])
                          |> annotate_conversation(run_config)

                        StreamQueue.close(queue)

                        {:ok,
                         %Result{
                           processed
                           | events: merged_events,
                             usage: merged_usage,
                             thread: final_thread,
                             final_response: final_output,
                             attempts: attempt
                         }}

                      {:error, reason} ->
                        StreamQueue.close(queue)
                        {:error, reason}
                    end

                  {:error, _} = error ->
                    StreamQueue.close(queue)
                    error

                  :continue ->
                    next_turn_opts = maybe_reset_tool_choice(agent, turn_opts, tool_results)
                    next_turn_opts = next_turn_opts || %{}

                    cond do
                      StreamingControl.cancel_mode(control) == :after_turn ->
                        StreamQueue.close(queue)

                        {:ok,
                         %Result{
                           processed
                           | events: merged_events,
                             usage: merged_usage,
                             thread: %{processed.thread | usage: merged_usage},
                             attempts: attempt
                         }}

                      processed.thread.continuation_token &&
                          attempt < run_config.max_turns ->
                        safe_backoff(backoff, attempt)
                        next_thread = %{processed.thread | usage: merged_usage}

                        do_run_streamed(
                          next_thread,
                          input,
                          agent,
                          run_config,
                          guardrails,
                          next_turn_opts,
                          backoff,
                          attempt + 1,
                          merged_events,
                          merged_usage,
                          queue,
                          control
                        )

                      processed.thread.continuation_token ->
                        StreamQueue.close(queue)

                        {:error,
                         {:max_turns_exceeded, run_config.max_turns,
                          %{continuation: processed.thread.continuation_token}}}

                      true ->
                        case run_guardrails(
                               :output,
                               guardrails.output,
                               processed.final_response,
                               %{agent: agent},
                               %{on_result: &emit_guardrail_event(queue, &1, &2, &3, &4)}
                             ) do
                          :ok ->
                            final_thread =
                              processed.thread
                              |> Map.put(:usage, merged_usage)
                              |> annotate_conversation(run_config)

                            StreamQueue.close(queue)

                            {:ok,
                             %Result{
                               processed
                               | events: merged_events,
                                 usage: merged_usage,
                                 thread: final_thread,
                                 attempts: attempt
                             }}

                          {:error, reason} ->
                            StreamQueue.close(queue)
                            {:error, reason}
                        end
                    end
                end
              else
                {:error, _reason} = error ->
                  StreamQueue.close(queue)
                  error
              end
            end

          {:error, _} = error ->
            StreamQueue.close(queue)
            error
        end
    end
  end

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
    Enum.reduce_while(guardrails, :ok, fn guardrail, :ok ->
      case run_guardrail(stage, guardrail, payload, context, hooks) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
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
           type: :reject
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
      {:ok, new_input} -> new_input
      {:ok, new_input, _ctx} -> new_input
      value when is_binary(value) -> value
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

  defp apply_model_override(%Thread{codex_opts: %Options{} = opts} = thread, %RunConfig{
         model: model
       }) do
    cond do
      is_binary(model) and model != "" ->
        %{thread | codex_opts: %{opts | model: model}}

      true ->
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
