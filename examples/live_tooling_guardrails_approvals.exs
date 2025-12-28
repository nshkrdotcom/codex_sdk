# Covers ADR-002, ADR-003, ADR-011 (tool behaviors, guardrails, approvals)
Mix.Task.run("app.start")

alias Codex.{Agent, AgentRunner, Guardrail, Handoff, RunConfig, ToolGuardrail, Tools}
alias Codex.FunctionTool
alias Codex.Items.AgentMessage
alias Codex.StreamEvent.{GuardrailResult, ToolApproval}
alias Codex.RunResultStreaming
alias Codex.Events

defmodule CodexExamples.DemoApprovalHook do
  @moduledoc false
  @behaviour Codex.Approvals.Hook

  @impl true
  def prepare(_event, context), do: {:ok, Map.put(context, :demo, true)}

  @impl true
  def review_tool(event, _context, _opts) do
    case event.call_id do
      "deny" -> {:deny, "demo deny"}
      "async" -> {:async, make_ref()}
      _ -> :allow
    end
  end

  @impl true
  def await(_ref, timeout) do
    Process.sleep(min(timeout, 200))
    {:ok, :allow}
  end
end

defmodule CodexExamples.GuardedCalcTool do
  use FunctionTool,
    name: "guarded_calc",
    description: "Adds two integers and echoes the mode",
    parameters: %{left: :integer, right: :integer, mode: :string},
    handler: fn args, _ctx ->
      left = Map.get(args, "left", 1)
      right = Map.get(args, "right", 1)
      mode = Map.get(args, "mode", "allow")
      {:ok, %{"sum" => left + right, "mode" => mode}}
    end
end

defmodule CodexExamples.LiveToolingGuardrailsApprovals do
  @moduledoc false

  @default_command "echo guardrails ok"

  def main(argv) do
    demo_approvals()

    {opts, args, _} =
      OptionParser.parse(argv,
        switches: [deny: :boolean, tripwire: :boolean, stop_on_tool: :boolean],
        aliases: [d: :deny, t: :tripwire]
      )

    command = if opts[:deny], do: "rm -rf /tmp/denied", else: @default_command
    prompt = build_prompt(args, command, opts[:tripwire])

    Tools.reset!()
    {:ok, _} = Tools.register(CodexExamples.GuardedCalcTool)

    {:ok, _} =
      Codex.Tools.ShellTool
      |> Tools.register(Keyword.merge([name: "guarded_shell"], shell_options(opts)))

    {:ok, helper_agent} =
      Agent.new(%{
        name: "GuardrailHelper",
        instructions: "Condense the provided draft reply into one short sentence."
      })

    handoff =
      Handoff.wrap(helper_agent,
        tool_name: "handoff_guard",
        tool_description: "Tighten the reply if needed",
        input_schema: %{
          "type" => "object",
          "properties" => %{"note" => %{"type" => "string"}},
          "required" => ["note"]
        }
      )

    tool_use_behavior =
      if opts[:stop_on_tool],
        do: :stop_on_first_tool,
        else: %{stop_at_tool_names: ["handoff_guard"]}

    {:ok, agent} =
      Agent.new(%{
        name: "GuardedAgent",
        instructions:
          "Provide a short status update about guardrails and approvals for this run. Use handoff_guard only if you need help tightening wording.",
        tools: ["guarded_shell", "guarded_calc"],
        handoffs: [handoff],
        tool_use_behavior: tool_use_behavior,
        input_guardrails: [input_guardrail(opts[:tripwire])],
        output_guardrails: [output_guardrail(opts[:tripwire])],
        tool_input_guardrails: [tool_input_guardrail(opts[:deny])],
        tool_output_guardrails: [tool_output_guardrail()]
      })

    {:ok, run_config} =
      RunConfig.new(%{
        max_turns: 2,
        workflow: "live-tooling-guardrails",
        trace_id: "guardrails-#{System.unique_integer([:positive])}"
      })

    {:ok, codex_opts} =
      Codex.Options.new(%{
        codex_path_override: fetch_codex_path!()
      })

    {:ok, thread_opts} =
      Codex.Thread.Options.new(%{
        approval_hook: CodexExamples.DemoApprovalHook,
        approval_timeout_ms: 500
      })

    {:ok, thread} = Codex.start_thread(codex_opts, thread_opts)

    IO.puts("""
    Streaming live Codex run with guardrails + approvals
      Prompt: #{String.trim(prompt)}
      Command: #{command}
      Tool behavior: #{inspect(tool_use_behavior)}
    """)

    case AgentRunner.run_streamed(thread, prompt, %{agent: agent, run_config: run_config}) do
      {:ok, stream} ->
        consume_stream(stream)

      {:error, reason} ->
        IO.puts("Run failed early: #{inspect(reason)}")
    end
  end

  defp demo_approvals do
    base_event = %Events.ToolCallRequested{
      thread_id: "demo",
      turn_id: "t1",
      call_id: "allow",
      tool_name: "demo_tool",
      arguments: %{},
      requires_approval: true
    }

    allow = Codex.Approvals.review_tool(CodexExamples.DemoApprovalHook, base_event, %{})

    deny =
      Codex.Approvals.review_tool(
        CodexExamples.DemoApprovalHook,
        %{base_event | call_id: "deny"},
        %{}
      )

    async =
      Codex.Approvals.review_tool(
        CodexExamples.DemoApprovalHook,
        %{base_event | call_id: "async"},
        %{}
      )

    IO.puts(
      "Approval hook demo: allow=#{inspect(allow)} deny=#{inspect(deny)} async=#{inspect(async)}"
    )
  end

  defp consume_stream(stream) do
    state =
      stream
      |> RunResultStreaming.events()
      |> Enum.reduce(%{final: nil}, fn
        %GuardrailResult{stage: stage, guardrail: guardrail, result: result, message: message},
        acc ->
          IO.puts("Guardrail #{guardrail} (#{stage}) -> #{result} #{message || ""}")
          acc

        %ToolApproval{tool_name: tool, decision: decision, reason: reason}, acc ->
          IO.puts("Approval decision for #{tool}: #{decision} #{reason || ""}")
          acc

        %Codex.StreamEvent.RunItem{event: %Events.ItemCompleted{item: %AgentMessage{text: text}}},
        acc ->
          %{acc | final: text || acc.final}

        %Codex.StreamEvent.RunItem{
          event: %Events.TurnCompleted{final_response: %AgentMessage{text: text}}
        },
        acc ->
          %{acc | final: text || acc.final}

        %Codex.StreamEvent.RunItem{
          event: %Events.TurnCompleted{final_response: %{"text" => text}}
        },
        acc ->
          %{acc | final: text || acc.final}

        _other, acc ->
          acc
      end)

    IO.puts("Usage so far: #{inspect(RunResultStreaming.usage(stream))}")
    IO.puts("Final response: #{state.final || "<none>"}")
  end

  defp input_guardrail(tripwire?) do
    Guardrail.new(
      name: "input-scan",
      handler: fn input, _context ->
        downcased = String.downcase(to_string(input))

        cond do
          tripwire? -> {:tripwire, "tripwire requested"}
          String.contains?(downcased, "block") -> {:reject, "blocked input"}
          true -> :ok
        end
      end
    )
  end

  defp output_guardrail(tripwire?) do
    Guardrail.new(
      name: "output-scan",
      stage: :output,
      handler: fn output, _context ->
        rendered = output |> inspect() |> String.downcase()

        cond do
          tripwire? -> {:tripwire, "output tripwire requested"}
          String.contains?(rendered, "forbidden") -> {:reject, "forbidden content"}
          true -> :ok
        end
      end
    )
  end

  defp tool_input_guardrail(deny?) do
    ToolGuardrail.new(
      name: "tool-input",
      stage: :input,
      handler: fn _event, args, _ctx ->
        cmd = args |> Map.get("command") |> to_string()

        if deny? or String.contains?(cmd, "rm -rf") do
          {:reject, "dangerous command"}
        else
          :ok
        end
      end
    )
  end

  defp tool_output_guardrail do
    ToolGuardrail.new(
      name: "tool-output",
      stage: :output,
      handler: fn _event, payload, _ctx ->
        rendered = payload |> inspect() |> String.downcase()

        if String.contains?(rendered, "timeout") do
          {:tripwire, "tool output mentions timeout"}
        else
          :ok
        end
      end
    )
  end

  defp shell_options(opts) do
    [
      executor: fn %{"command" => command}, _context ->
        {:ok, %{"command" => command, "stdout" => "simulated shell: #{command}"}}
      end,
      approval: fn %{"command" => command}, _context, _metadata ->
        cond do
          String.contains?(command, "timeout") -> {:deny, "approval timeout"}
          opts[:deny] -> {:deny, "blocked by approval hook"}
          true -> :allow
        end
      end,
      max_output_bytes: 400
    ]
  end

  defp build_prompt([], _command, tripwire?) do
    base = "Provide a short status update about guardrails and approvals for this run."
    if tripwire?, do: base <> " Mention tripwire to trigger the guardrails.", else: base
  end

  defp build_prompt(values, _command, _tripwire?) do
    Enum.join(values, " ")
  end

  defp fetch_codex_path! do
    System.get_env("CODEX_PATH") ||
      System.find_executable("codex") ||
      Mix.raise("""
      Unable to locate the `codex` CLI.
      Install the Codex CLI and ensure it is on your PATH or set CODEX_PATH.
      """)
  end
end

CodexExamples.LiveToolingGuardrailsApprovals.main(System.argv())
