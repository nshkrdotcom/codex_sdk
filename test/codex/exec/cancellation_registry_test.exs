defmodule Codex.Exec.CancellationRegistryTest do
  use ExUnit.Case, async: false

  alias Codex.Exec.CancellationRegistry

  test "registers transports and prunes dead pids" do
    token = "tok-#{System.unique_integer([:positive])}"
    pid = spawn(fn -> Process.sleep(:infinity) end)
    ref = Process.monitor(pid)

    assert :ok = CancellationRegistry.register(token, pid)
    assert [pid] == CancellationRegistry.transports_for_token(token)

    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^pid, _reason}

    assert [] == CancellationRegistry.transports_for_token(token)
    assert :ok = CancellationRegistry.unregister(token)
  end

  test "unregister/2 removes only the specified transport" do
    token = "tok-#{System.unique_integer([:positive])}"
    pid_a = spawn(fn -> Process.sleep(:infinity) end)
    pid_b = spawn(fn -> Process.sleep(:infinity) end)

    on_exit(fn ->
      Process.exit(pid_a, :kill)
      Process.exit(pid_b, :kill)
    end)

    assert :ok = CancellationRegistry.register(token, pid_a)
    assert :ok = CancellationRegistry.register(token, pid_b)

    assert :ok = CancellationRegistry.unregister(token, pid_a)
    assert CancellationRegistry.transports_for_token(token) == [pid_b]

    assert :ok = CancellationRegistry.unregister(token)
    assert [] == CancellationRegistry.transports_for_token(token)
  end
end
