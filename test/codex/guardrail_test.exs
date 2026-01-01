defmodule Codex.GuardrailTest do
  use ExUnit.Case, async: false

  alias Codex.AgentRunner
  alias Codex.Approvals.StaticPolicy
  alias Codex.Guardrail
  alias Codex.GuardrailError
  alias Codex.Options
  alias Codex.TestSupport.FixtureScripts
  alias Codex.Thread
  alias Codex.Thread.Options, as: ThreadOptions
  alias Codex.ToolGuardrail
  alias Codex.Tools

  defmodule MathTool do
    use Codex.Tool, name: "math_tool", description: "adds provided numbers"

    @impl true
    def invoke(%{"x" => x, "y" => y}, _ctx), do: {:ok, %{"sum" => x + y}}
  end

  setup do
    {:ok, thread_opts} = ThreadOptions.new(%{})
    {:ok, thread_opts: thread_opts}
  end

  test "input guardrail tripwire halts run", %{thread_opts: thread_opts} do
    script_path =
      FixtureScripts.cat_fixture("thread_basic.jsonl")
      |> tap(&on_exit(fn -> File.rm_rf(&1) end))

    {:ok, codex_opts} = Options.new(%{api_key: "test", codex_path_override: script_path})
    thread = Thread.build(codex_opts, thread_opts)

    guardrail =
      Guardrail.new(
        name: "block",
        stage: :input,
        handler: fn input, _ctx ->
          if String.contains?(input, "Hello"), do: {:tripwire, "blocked"}, else: :ok
        end
      )

    assert {:error, %GuardrailError{stage: :input, guardrail: "block", message: "blocked"}} =
             AgentRunner.run(thread, "Hello Codex", %{agent: %{input_guardrails: [guardrail]}})
  end

  test "parallel input guardrail rejects run", %{thread_opts: thread_opts} do
    script_path =
      FixtureScripts.cat_fixture("thread_basic.jsonl")
      |> tap(&on_exit(fn -> File.rm_rf(&1) end))

    {:ok, codex_opts} = Options.new(%{api_key: "test", codex_path_override: script_path})
    thread = Thread.build(codex_opts, thread_opts)

    guardrail =
      Guardrail.new(
        name: "block-parallel",
        stage: :input,
        run_in_parallel: true,
        handler: fn _input, _ctx -> {:reject, "blocked"} end
      )

    assert {:error, %GuardrailError{stage: :input, guardrail: "block-parallel", type: :reject}} =
             AgentRunner.run(thread, "Hello Codex", %{agent: %{input_guardrails: [guardrail]}})
  end

  test "tool input guardrail blocks tool execution", %{thread_opts: thread_opts} do
    Tools.reset!()
    Tools.reset_metrics()
    {:ok, _} = Tools.register(MathTool, name: "math_tool")

    allow_opts = Map.put(thread_opts, :approval_policy, StaticPolicy.allow())

    {script_path, state_file} =
      FixtureScripts.sequential_fixtures(["thread_tool_auto_step1.jsonl"])

    on_exit(fn ->
      File.rm_rf(script_path)
      File.rm_rf(state_file)
    end)

    {:ok, codex_opts} = Options.new(%{api_key: "test", codex_path_override: script_path})
    thread = Thread.build(codex_opts, allow_opts)

    guardrail =
      ToolGuardrail.new(
        name: "tool-block",
        stage: :input,
        handler: fn event, _payload, _ctx ->
          if event.tool_name == "math_tool", do: {:tripwire, "no tools"}, else: :ok
        end
      )

    assert {:error, %GuardrailError{stage: :tool_input, guardrail: "tool-block"}} =
             AgentRunner.run(thread, "Calc", %{
               agent: %{tool_input_guardrails: [guardrail]}
             })
  end
end
