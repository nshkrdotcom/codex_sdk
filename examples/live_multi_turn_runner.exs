# Covers ADR-001, ADR-002, ADR-009, ADR-010 (multi-turn runner, tool behavior, usage/tracing)
Mix.Task.run("app.start")

alias Codex.{Agent, AgentRunner, Handoff, RunConfig, Tools}
alias Codex.Events
alias Codex.FunctionTool
alias Codex.Items.AgentMessage

defmodule CodexExamples.LiveMultiTurnRunner do
  @moduledoc false

  @default_prompt """
  Use the repo_fact tool before you answer. If you want help tightening the reply, delegate once to the helper handoff.
  Keep the final answer to one or two sentences.
  """

  defmodule RepoFactTool do
    use FunctionTool,
      name: "repo_fact",
      description: "Returns a quick fact about the repo to seed your answer",
      parameters: %{topic: :string},
      handler: fn %{"topic" => topic}, _ctx ->
        {:ok, %{"fact" => "codex_sdk demo fact for #{topic}: live multi-turn runner"}}
      end
  end

  def main(argv) do
    {opts, args, _} =
      OptionParser.parse(argv,
        switches: [max_turns: :integer, stop_on_tool: :boolean],
        aliases: [m: :max_turns]
      )

    prompt = parse_prompt(args)

    Codex.Tools.reset!()
    {:ok, _handle} = Tools.register(RepoFactTool)

    {:ok, helper_agent} =
      Agent.new(%{
        name: "TightenHelper",
        instructions: "Rewrite the provided note as one tight sentence and return it directly."
      })

    handoff =
      Handoff.wrap(helper_agent,
        tool_name: "handoff_helper",
        tool_description: "Delegate a draft reply for condensation",
        input_schema: %{
          "type" => "object",
          "properties" => %{"note" => %{"type" => "string"}},
          "required" => ["note"]
        }
      )

    tool_behavior =
      if opts[:stop_on_tool],
        do: :stop_on_first_tool,
        else: %{stop_at_tool_names: ["handoff_helper"]}

    {:ok, agent} =
      Agent.new(%{
        name: "Planner",
        instructions:
          "Always call repo_fact before answering. Optionally use handoff_helper if the note needs to be condensed.",
        tools: ["repo_fact"],
        handoffs: [handoff],
        tool_use_behavior: tool_behavior,
        reset_tool_choice: true
      })

    {:ok, run_config} =
      RunConfig.new(%{
        max_turns: opts[:max_turns] || 3,
        workflow: "live-multi-turn",
        group: "examples",
        trace_id: "multi-#{System.unique_integer([:positive])}",
        trace_include_sensitive_data: false
      })

    {:ok, codex_opts} =
      Codex.Options.new(%{
        codex_path_override: fetch_codex_path!()
      })

    {:ok, thread} = Codex.start_thread(codex_opts)

    IO.puts("""
    Running multi-turn loop against live Codex CLI.
      Prompt: #{String.trim(prompt)}
      Tool behavior: #{inspect(tool_behavior)}
      Max turns: #{run_config.max_turns}
    """)

    case AgentRunner.run(thread, prompt, %{agent: agent, run_config: run_config}) do
      {:ok, result} ->
        summarize_events(result.events)
        IO.puts("Attempts used: #{result.attempts}")
        IO.puts("Usage: #{inspect(result.thread.usage || %{})}")
        IO.puts("Final response:\n#{render_response(result.final_response)}")

      {:error, {:max_turns_exceeded, limit, context}} ->
        IO.puts("Hit max_turns=#{limit}, continuation=#{inspect(context)}")

      {:error, reason} ->
        Mix.raise("Multi-turn run failed: #{inspect(reason)}")
    end
  end

  defp summarize_events(events) do
    events
    |> Enum.filter(
      &(match?(%Events.ToolCallRequested{}, &1) or match?(%Events.ToolCallCompleted{}, &1))
    )
    |> Enum.each(fn
      %Events.ToolCallRequested{tool_name: name, call_id: id, requires_approval: req?} ->
        IO.puts("Tool requested: #{name} (call_id=#{id}, requires_approval=#{req?})")

      %Events.ToolCallCompleted{tool_name: name, call_id: id, output: output} ->
        IO.puts("Tool completed: #{name} (call_id=#{id}) output=#{inspect(output)}")
    end)

    case Enum.find(events, &match?(%Events.TurnContinuation{}, &1)) do
      %Events.TurnContinuation{continuation_token: token, reason: reason} ->
        IO.puts("Continuation suggested (reason=#{reason || "none"}): #{token}")

      _ ->
        :ok
    end
  end

  defp render_response(%AgentMessage{text: text}), do: text
  defp render_response(%{"text" => text}), do: text
  defp render_response(nil), do: "<no response>"
  defp render_response(other), do: inspect(other)

  defp parse_prompt([]), do: String.trim(@default_prompt)
  defp parse_prompt(values), do: Enum.join(values, " ")

  defp fetch_codex_path! do
    System.get_env("CODEX_PATH") ||
      System.find_executable("codex") ||
      Mix.raise("""
      Unable to locate the `codex` CLI.
      Install the Codex CLI and ensure it is on your PATH or set CODEX_PATH.
      """)
  end
end

CodexExamples.LiveMultiTurnRunner.main(System.argv())
