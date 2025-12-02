defmodule Codex.AgentRunner do
  @moduledoc """
  Multi-turn runner that orchestrates agent execution over Codex threads.
  """

  alias Codex.Agent
  alias Codex.Options
  alias Codex.RunConfig
  alias Codex.Thread
  alias Codex.Turn.Result

  @spec run(Thread.t(), String.t(), map() | keyword()) ::
          {:ok, Result.t()} | {:error, term()}
  def run(%Thread{} = thread, input, opts \\ %{}) when is_binary(input) do
    {agent_opts, run_config_opts, turn_opts, backoff} = normalize_opts(opts)

    with {:ok, %Agent{} = _agent} <- Agent.new(agent_opts),
         {:ok, %RunConfig{} = run_config} <- RunConfig.new(run_config_opts) do
      tuned_thread = apply_model_override(thread, run_config)

      do_run(
        tuned_thread,
        input,
        run_config,
        turn_opts,
        backoff || (&default_backoff/1),
        1,
        [],
        %{}
      )
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
         run_config,
         turn_opts,
         backoff,
         attempt,
         acc_events,
         acc_usage
       ) do
    case Thread.run_turn(thread, input, turn_opts) do
      {:ok, %Result{} = result} ->
        with {:ok, processed} <- Thread.handle_tool_requests(result, attempt) do
          merged_events = acc_events ++ processed.events
          merged_usage = Thread.merge_usage(acc_usage, processed.usage)

          cond do
            processed.thread.continuation_token && attempt < run_config.max_turns ->
              safe_backoff(backoff, attempt)
              next_thread = %{processed.thread | usage: merged_usage}

              do_run(
                next_thread,
                input,
                run_config,
                turn_opts,
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
