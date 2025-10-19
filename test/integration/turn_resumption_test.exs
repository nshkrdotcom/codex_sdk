defmodule Codex.Integration.TurnResumptionTest do
  use ExUnit.Case, async: false

  alias Codex.Thread.Options, as: ThreadOptions
  alias Codex.TestSupport.FixtureScripts
  alias Codex.{Options, Thread}

  @moduletag :integration

  test "resumes using continuation tokens from prior turn" do
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

    {:ok, partial} = Thread.run(thread, "Start turn")
    assert partial.thread.thread_id == "thread_auto_123"
    assert partial.thread.continuation_token == "cont-auto-run"
    assert partial.final_response == nil

    {:ok, resumed} = Thread.run(partial.thread, "resume automatically")

    assert resumed.thread.thread_id == "thread_auto_123"
    assert resumed.thread.continuation_token == nil
    assert resumed.final_response == %{"type" => "text", "text" => "All operations succeeded"}
  end
end
