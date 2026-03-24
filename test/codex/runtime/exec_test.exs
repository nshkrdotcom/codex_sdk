defmodule Codex.Runtime.ExecTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias CliSubprocessCore.{Event, Payload, ProcessExit}
  alias Codex.{Events, Options}
  alias Codex.Exec.Options, as: ExecOptions
  alias Codex.Runtime.Exec
  alias Codex.TestSupport.FixtureScripts

  import Codex.Test.ModelFixtures

  test "project_event projects raw Codex events and enriches thread metadata" do
    {:ok, codex_opts} =
      Options.new(%{
        api_key: "test",
        model: default_model(),
        reasoning_effort: :medium
      })

    raw = %{
      "type" => "thread.started",
      "thread_id" => "thr_runtime",
      "metadata" => %{"labels" => %{"topic" => "demo"}}
    }

    core_event =
      Event.new(:raw,
        raw: raw,
        payload: Payload.Raw.new(stream: :stdout, content: raw)
      )

    assert {[%Events.ThreadStarted{} = projected], %{exec_opts: ^codex_opts}} =
             Exec.project_event(core_event, %{exec_opts: codex_opts})

    assert projected.thread_id == "thr_runtime"
    assert projected.metadata["labels"] == %{"topic" => "demo"}
    assert projected.metadata["model"] == default_model()
    assert projected.metadata["reasoning_effort"] == "medium"
    assert get_in(projected.metadata, ["config", "model_reasoning_effort"]) == "medium"
  end

  test "project_event drops core synthetic session lifecycle events" do
    run_started =
      Event.new(:run_started,
        payload: Payload.RunStarted.new(command: "codex", args: ["exec", "--json"])
      )

    exit_result =
      Event.new(:result,
        raw: %{exit: %ProcessExit{status: :success, code: 0, reason: :normal}},
        payload: Payload.Result.new(status: :completed)
      )

    assert {[], :state} = Exec.project_event(run_started, :state)
    assert {[], :state} = Exec.project_event(exit_result, :state)
  end

  test "project_event logs parse errors emitted by the core session" do
    invalid_line = <<255>>

    core_event =
      Event.new(:error,
        raw: invalid_line,
        payload:
          Payload.Error.new(
            message: "unexpected byte at position 0: 0xFF",
            code: "parse_error",
            metadata: %{line: invalid_line}
          )
      )

    log =
      capture_log(fn ->
        assert {[], :state} = Exec.project_event(core_event, :state)
      end)

    assert log =~ "Failed to decode codex event"
    assert log =~ "<<255>>"
  end

  test "build_session_options pins the exec lane to a Codex-owned session tag" do
    script_path =
      "thread_basic.jsonl"
      |> FixtureScripts.cat_fixture()
      |> tap(&on_exit(fn -> File.rm_rf(&1) end))

    {:ok, codex_opts} = Options.new(%{api_key: "test", codex_path_override: script_path})
    {:ok, exec_opts} = ExecOptions.new(%{codex_opts: codex_opts})

    assert {:ok, session_opts} = Exec.build_session_options(exec_opts: exec_opts)
    assert Keyword.fetch!(session_opts, :session_event_tag) == Exec.session_event_tag()
  end
end
