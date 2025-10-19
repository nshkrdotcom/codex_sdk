defmodule Mix.Tasks.CodexTasksTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  test "codex.parity lists python fixtures" do
    output = capture_io(fn -> Mix.Tasks.Codex.Parity.run([]) end)

    assert output =~ "Found"
    assert output =~ "thread_basic.jsonl"
  end

  test "codex.verify dry run prints planned commands" do
    output = capture_io(fn -> Mix.Tasks.Codex.Verify.run(["--dry-run"]) end)

    assert output =~ "[dry-run] compile --warnings-as-errors"
    assert output =~ "[dry-run] format --check-formatted"
    assert output =~ "[dry-run] test"
  end
end
