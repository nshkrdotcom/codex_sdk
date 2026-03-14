defmodule Codex.ProcessExitTest do
  use ExUnit.Case, async: true

  alias Codex.ProcessExit

  test "extracts exit status from nested wrappers" do
    assert {:ok, 9} =
             ProcessExit.exit_status(
               {:shutdown, {:send_failed, {{:exit_status, 9 * 256}, {GenServer, :call, []}}}}
             )
  end

  test "normalizes wrapped exit status reasons for downstream consumers" do
    assert {:exit_code, 9} =
             ProcessExit.normalize_reason({:shutdown, {:exit_status, 9 * 256}})
  end

  test "converts signal reasons to shell-style exit codes" do
    assert {:ok, 137} = ProcessExit.exit_status({:signal, 9, false})
  end
end
