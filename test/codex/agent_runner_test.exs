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

  describe "Agent.new/1" do
    test "builds agent with defaults and validates inputs" do
      assert {:ok, %Agent{} = agent} =
               Agent.new(%{
                 name: "helper",
                 instructions: "Assist the user",
                 prompt: %{id: "prompt-1"},
                 handoffs: [:support],
                 tools: [:search],
                 tool_use_behavior: :auto,
                 input_guardrails: [:input_check],
                 output_guardrails: [:output_check],
                 hooks: %{on_result: :noop},
                 model: "gpt-4.1"
               })

      assert agent.name == "helper"
      assert agent.instructions == "Assist the user"
      assert agent.prompt == %{id: "prompt-1"}
      assert agent.handoffs == [:support]
      assert agent.tools == [:search]
      assert agent.tool_use_behavior == :auto
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
end
