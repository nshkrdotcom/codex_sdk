defmodule Codex.AgentRunnerTest do
  use ExUnit.Case, async: false

  alias Codex.Agent
  alias Codex.AgentRunner
  alias Codex.Items
  alias Codex.Options
  alias Codex.RunConfig
  alias Codex.Thread
  alias Codex.Thread.Options, as: ThreadOptions
  alias Codex.TestSupport.FixtureScripts
  alias Codex.Tools
  alias Codex.Approvals.StaticPolicy

  describe "Agent.new/1" do
    test "builds agent with defaults and validates inputs" do
      assert {:ok, %Agent{} = agent} =
               Agent.new(%{
                 name: "helper",
                 instructions: "Assist the user",
                 prompt: %{id: "prompt-1"},
                 handoff_description: "Routes tricky asks",
                 handoffs: [:support],
                 tools: [:search],
                 tool_use_behavior: :stop_on_first_tool,
                 reset_tool_choice: false,
                 input_guardrails: [:input_check],
                 output_guardrails: [:output_check],
                 hooks: %{on_result: :noop},
                 model: "gpt-4.1"
               })

      assert agent.name == "helper"
      assert agent.instructions == "Assist the user"
      assert agent.prompt == %{id: "prompt-1"}
      assert agent.handoff_description == "Routes tricky asks"
      assert agent.handoffs == [:support]
      assert agent.tools == [:search]
      assert agent.tool_use_behavior == :stop_on_first_tool
      refute agent.reset_tool_choice
      assert agent.input_guardrails == [:input_check]
      assert agent.output_guardrails == [:output_check]
      assert agent.hooks == %{on_result: :noop}
      assert agent.model == "gpt-4.1"
    end

    test "rejects invalid instructions" do
      assert {:error, {:invalid_instructions, 123}} = Agent.new(%{instructions: 123})
    end
  end

  describe "RunConfig.new/1" do
    test "applies defaults and validates max_turns" do
      assert {:ok, %RunConfig{} = config} = RunConfig.new(%{nest_handoff_history: false})

      assert config.max_turns == 10
      refute config.nest_handoff_history

      assert {:error, {:invalid_max_turns, 0}} = RunConfig.new(%{max_turns: 0})
    end
  end

  describe "AgentRunner.run/3" do
    setup do
      {script_path, state_file} =
        FixtureScripts.sequential_fixtures([
          "thread_auto_run_step1.jsonl",
          "thread_auto_run_step2.jsonl"
        ])

      on_exit(fn ->
        File.rm_rf(script_path)
        File.rm_rf(state_file)
      end)

      {:ok, codex_opts} =
        Options.new(%{
          api_key: "test",
          codex_path_override: script_path
        })

      {:ok, thread_opts} = ThreadOptions.new(%{})
      thread = Thread.build(codex_opts, thread_opts)

      {:ok, thread: thread}
    end

    test "runs multiple turns until completion", %{thread: thread} do
      assert {:ok, result} = AgentRunner.run(thread, "Hello Codex")

      assert %Items.AgentMessage{text: "All operations succeeded"} = result.final_response
      assert result.attempts == 2
      assert result.thread.continuation_token == nil
    end

    test "errors when exceeding max_turns", %{} do
      {pending_path, pending_state} =
        FixtureScripts.sequential_fixtures(["thread_auto_run_pending.jsonl"])

      on_exit(fn ->
        File.rm_rf(pending_path)
        File.rm_rf(pending_state)
      end)

      {:ok, codex_opts} =
        Options.new(%{
          api_key: "test",
          codex_path_override: pending_path
        })

      {:ok, thread_opts} = ThreadOptions.new(%{})
      pending_thread = Thread.build(codex_opts, thread_opts)

      assert {:error, {:max_turns_exceeded, 2, %{continuation: "cont-auto-run"}}} =
               AgentRunner.run(pending_thread, "Still running", %{max_turns: 2})
    end
  end

  describe "Thread facade" do
    test "delegates to agent runner with default max_turns" do
      {script_path, state_file} =
        FixtureScripts.sequential_fixtures([
          "thread_auto_run_step1.jsonl",
          "thread_auto_run_step2.jsonl"
        ])

      on_exit(fn ->
        File.rm_rf(script_path)
        File.rm_rf(state_file)
      end)

      {:ok, codex_opts} =
        Options.new(%{
          api_key: "test",
          codex_path_override: script_path
        })

      {:ok, thread_opts} = ThreadOptions.new(%{})
      thread = Thread.build(codex_opts, thread_opts)

      assert {:ok, result} = Thread.run(thread, "Hello Codex")
      assert result.attempts == 2
      assert result.thread.continuation_token == nil
    end
  end

  defmodule SumTool do
    use Codex.Tool, name: "math_tool", description: "adds provided numbers"

    @impl true
    def invoke(%{"x" => x, "y" => y}, _ctx), do: {:ok, %{"sum" => x + y}}
  end

  describe "tool_use_behavior" do
    setup do
      Tools.reset!()
      Tools.reset_metrics()

      {:ok, _} = Tools.register(SumTool, name: "math_tool")

      {:ok, base_opts} = ThreadOptions.new(%{})

      allow_opts =
        base_opts
        |> Map.put(:approval_policy, StaticPolicy.allow())

      {:ok, thread_opts: allow_opts}
    end

    test "stop_on_first_tool surfaces tool output without another turn", %{
      thread_opts: thread_opts
    } do
      {script_path, state_file} =
        FixtureScripts.sequential_fixtures(["thread_tool_auto_step1.jsonl"])

      on_exit(fn ->
        File.rm_rf(script_path)
        File.rm_rf(state_file)
      end)

      {:ok, codex_opts} =
        Options.new(%{
          api_key: "test",
          codex_path_override: script_path
        })

      thread = Thread.build(codex_opts, thread_opts)

      {:ok, result} =
        AgentRunner.run(thread, "Calc", %{
          agent: %{tool_use_behavior: :stop_on_first_tool}
        })

      assert result.attempts == 1
      assert result.thread.continuation_token == nil
      assert result.final_response == %{"sum" => 9}
    end

    test "stop_at_tool_names only halts when matching tool", %{thread_opts: thread_opts} do
      {script_path, state_file} =
        FixtureScripts.sequential_fixtures([
          "thread_tool_auto_step1.jsonl",
          "thread_tool_auto_step2.jsonl"
        ])

      on_exit(fn ->
        File.rm_rf(script_path)
        File.rm_rf(state_file)
      end)

      {:ok, codex_opts} =
        Options.new(%{
          api_key: "test",
          codex_path_override: script_path
        })

      thread = Thread.build(codex_opts, thread_opts)

      {:ok, result} =
        AgentRunner.run(thread, "Calc", %{
          agent: %{tool_use_behavior: %{stop_at_tool_names: ["other_tool"]}}
        })

      assert result.attempts == 2
      assert %Items.AgentMessage{text: "The sum is 9"} = result.final_response
    end

    test "custom tool_use_behavior function receives tool results", %{thread_opts: thread_opts} do
      {script_path, state_file} =
        FixtureScripts.sequential_fixtures(["thread_tool_auto_step1.jsonl"])

      on_exit(fn ->
        File.rm_rf(script_path)
        File.rm_rf(state_file)
      end)

      {:ok, codex_opts} =
        Options.new(%{
          api_key: "test",
          codex_path_override: script_path
        })

      thread = Thread.build(codex_opts, thread_opts)

      behavior = fn _ctx, tool_results ->
        send(self(), {:tool_results_seen, tool_results})
        %{is_final_output: true, final_output: "custom"}
      end

      {:ok, result} =
        AgentRunner.run(thread, "Calc", %{
          agent: %{tool_use_behavior: behavior}
        })

      assert result.attempts == 1
      assert result.final_response == "custom"
      assert_received {:tool_results_seen, [%{tool_name: "math_tool"} | _]}
    end
  end

  describe "reset_tool_choice handling" do
    test "clears tool_choice after tool use when enabled" do
      {:ok, agent} = Agent.new(%{name: "resetter"})

      turn_opts = %{tool_choice: :required, other: "keep"}
      tool_results = [%{tool_name: "math_tool", output: %{}}]

      assert %{tool_choice: nil, other: "keep"} =
               AgentRunner.maybe_reset_tool_choice(agent, turn_opts, tool_results)
    end

    test "preserves tool_choice when reset disabled" do
      {:ok, agent} = Agent.new(%{name: "no_reset", reset_tool_choice: false})

      turn_opts = %{tool_choice: :required}
      tool_results = [%{tool_name: "math_tool", output: %{}}]

      assert AgentRunner.maybe_reset_tool_choice(agent, turn_opts, tool_results) == turn_opts
    end
  end
end
