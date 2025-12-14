defmodule Codex.Integration.TurnResumptionTest do
  use ExUnit.Case, async: false

  alias Codex.{Items, Options, Thread}
  alias Codex.TestSupport.FixtureScripts
  alias Codex.Thread.Options, as: ThreadOptions

  @moduletag :integration

  test "follows continuation tokens across turns automatically" do
    {:ok, thread_opts} = ThreadOptions.new(%{})

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

    {:ok, result} = Thread.run(thread, "Start turn")
    assert result.thread.thread_id == "thread_auto_123"
    assert result.thread.continuation_token == nil
    assert result.attempts == 2
    assert %Items.AgentMessage{text: "All operations succeeded"} = result.final_response
  end
end
