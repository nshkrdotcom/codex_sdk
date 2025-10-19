defmodule Codex.ThreadAutoRunTest do
  use ExUnit.Case, async: true

  alias Codex.Thread.Options, as: ThreadOptions
  alias Codex.TestSupport.FixtureScripts
  alias Codex.ApprovalError
  alias Codex.Approvals.StaticPolicy
  alias Codex.{Options, Thread, Tools}

  defmodule MathTool do
    use Codex.Tool, name: "math_tool", description: "adds provided numbers"

    def start_link(agent), do: Agent.start_link(fn -> nil end, name: agent)

    @impl true
    def invoke(%{"x" => x, "y" => y}, %{context: %{agent: agent}}) do
      Agent.update(agent, fn _ -> %{x: x, y: y} end)
      {:ok, %{"sum" => x + y}}
    end
  end

  setup do
    {:ok, thread_opts} = ThreadOptions.new(%{})

    Tools.reset!()

    {:ok, thread_opts: thread_opts}
  end

  describe "run_auto/3" do
    test "continues execution until continuation token is cleared", %{thread_opts: thread_opts} do
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

      thread = Thread.build(codex_opts, thread_opts)

      assert {:ok, result} =
               Thread.run_auto(thread, "Hello Codex", max_attempts: 3, backoff: fn _ -> :ok end)

      assert result.final_response == %{"type" => "text", "text" => "All operations succeeded"}
      assert result.thread.continuation_token == nil

      assert result.thread.usage == %{
               "input_tokens" => 15,
               "cached_input_tokens" => 0,
               "output_tokens" => 11,
               "total_tokens" => 26
             }

      assert result.attempts == 2
      assert Enum.count(result.events) == 7
    end

    test "errors when continuation persists after max attempts", %{thread_opts: thread_opts} do
      {script_path, state_file} =
        FixtureScripts.sequential_fixtures(["thread_auto_run_pending.jsonl"])

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

      assert {:error, {:max_attempts_reached, 2, %{continuation: "cont-auto-run"}}} =
               Thread.run_auto(thread, "Still running", max_attempts: 2, backoff: fn _ -> :ok end)
    end
  end

  describe "tool orchestration" do
    setup %{thread_opts: thread_opts} do
      {:ok, agent} = MathTool.start_link(:math_tool_agent)
      on_exit(fn -> if Process.alive?(agent), do: Agent.stop(agent) end)

      {:ok, _handle} = Tools.register(MathTool, name: "math_tool")

      tool_thread_opts =
        thread_opts
        |> Map.put(:approval_policy, StaticPolicy.allow())
        |> Map.update(:metadata, %{tool_context: %{agent: agent}}, fn metadata ->
          Map.put(metadata, :tool_context, %{agent: agent})
        end)

      {:ok, thread_opts: tool_thread_opts, agent: agent}
    end

    test "auto-run invokes registered tool and continues", %{
      thread_opts: thread_opts,
      agent: agent
    } do
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

      assert {:ok, result} =
               Thread.run_auto(thread, "Calculate", max_attempts: 3, backoff: fn _ -> :ok end)

      assert Agent.get(agent, & &1) == %{x: 4, y: 5}

      assert Enum.any?(result.events, fn
               %Codex.Events.ToolCallRequested{tool_name: "math_tool"} -> true
               _ -> false
             end)

      assert Enum.any?(result.events, fn
               %Codex.Events.ToolCallCompleted{tool_name: "math_tool", output: %{"sum" => 9}} ->
                 true

               _ ->
                 false
             end)
    end

    test "auto-run stops when approval denies tool invocation", %{thread_opts: thread_opts} do
      Tools.reset!()
      {:ok, _} = Tools.register(MathTool, name: "math_tool")

      deny_opts = Map.put(thread_opts, :approval_policy, StaticPolicy.deny(reason: "blocked"))

      {script_path, state_file} =
        FixtureScripts.sequential_fixtures(["thread_tool_auto_pending.jsonl"])

      on_exit(fn ->
        File.rm_rf(script_path)
        File.rm_rf(state_file)
      end)

      {:ok, codex_opts} =
        Options.new(%{api_key: "test", codex_path_override: script_path})

      thread = Thread.build(codex_opts, deny_opts)

      assert {:error, %ApprovalError{tool: "math_tool", reason: "blocked"}} =
               Thread.run_auto(thread, "Blocked", max_attempts: 1, backoff: fn _ -> :ok end)
    end
  end
end
