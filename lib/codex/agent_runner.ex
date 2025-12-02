defmodule Codex.AgentRunner do
  @moduledoc """
  Multi-turn runner that orchestrates agent execution over Codex threads.
  """

  alias Codex.Agent
  alias Codex.Guardrail
  alias Codex.GuardrailError
  alias Codex.Handoff
  alias Codex.Options
  alias Codex.RunConfig
  alias Codex.ToolGuardrail
  alias Codex.Thread
  alias Codex.Turn.Result

  @spec run(Thread.t(), String.t(), map() | keyword()) ::
          {:ok, Result.t()} | {:error, term()}
  def run(%Thread{} = thread, input, opts \\ %{}) when is_binary(input) do
    {agent_opts, run_config_opts, turn_opts, backoff} = normalize_opts(opts)

    with {:ok, %Agent{} = agent} <- Agent.new(agent_opts),
         {:ok, %RunConfig{} = run_config} <- RunConfig.new(run_config_opts) do
      tuned_thread = apply_model_override(thread, run_config)
      guardrails = build_guardrails(agent, run_config)

      with :ok <-
             run_guardrails(:input, guardrails.input, input, %{
               agent: agent,
               run_config: run_config
             }) do
        do_run(
          tuned_thread,
          input,
          agent,
          run_config,
          guardrails,
          turn_opts,
          backoff || (&default_backoff/1),
          1,
          [],
          %{}
        )
      end
    end
  end

  @spec run_streamed(Thread.t(), String.t(), map() | keyword()) ::
          {:ok, Enumerable.t()} | {:error, term()}
  def run_streamed(%Thread{} = thread, input, opts \\ %{}) when is_binary(input) do
    {agent_opts, run_config_opts, turn_opts, _backoff} = normalize_opts(opts)

    with {:ok, %Agent{}} <- Agent.new(agent_opts),
         {:ok, %RunConfig{} = run_config} <- RunConfig.new(run_config_opts) do
      tuned_thread = apply_model_override(thread, run_config)
      Thread.run_turn_streamed(tuned_thread, input, turn_opts)
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
          end
        end

      {:error, _} = error ->
        error
    end
  end

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

  defp run_guardrails(_stage, guardrails, _payload, _context) when guardrails in [nil, []],
    do: :ok

  defp run_guardrails(stage, guardrails, payload, context) do
    Enum.reduce_while(guardrails, :ok, fn guardrail, :ok ->
      case run_guardrail(stage, guardrail, payload, context) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp run_guardrail(stage, %Guardrail{} = guardrail, payload, context) do
    case Guardrail.run(guardrail, payload, context) do
      :ok ->
        :ok

      {:reject, message} ->
        {:error,
         %GuardrailError{
           stage: stage,
           guardrail: guardrail.name,
           message: message,
           type: :reject
         }}

      {:tripwire, message} ->
        {:error,
         %GuardrailError{
           stage: stage,
           guardrail: guardrail.name,
           message: message,
           type: :tripwire
         }}
    end
  end

  defp run_guardrail(_stage, %ToolGuardrail{} = guardrail, payload, context) do
    tool_stage = if guardrail.stage == :output, do: :tool_output, else: :tool_input

    case ToolGuardrail.run(guardrail, Map.get(context, :event), payload, context) do
      :ok ->
        :ok

      {:reject, message} ->
        {:error,
         %GuardrailError{
           stage: tool_stage,
           guardrail: guardrail.name,
           message: message,
           type: :reject
         }}

      {:tripwire, message} ->
        {:error,
         %GuardrailError{
           stage: tool_stage,
           guardrail: guardrail.name,
           message: message,
           type: :tripwire
         }}
    end
  end

  defp run_guardrail(_stage, _guardrail, _payload, _context), do: :ok

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

  defp safe_backoff(fun, attempt) when is_function(fun, 1), do: fun.(attempt)
  defp safe_backoff(_fun, _attempt), do: :ok

  defp default_backoff(_attempt), do: :ok
end
