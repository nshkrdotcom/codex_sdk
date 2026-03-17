defmodule Codex.Runtime.ErlexecTest do
  use ExUnit.Case, async: false

  alias Codex.Runtime.Erlexec

  setup do
    :ok = Erlexec.ensure_started()

    on_exit(fn ->
      resume_exec_app()
      :ok = Erlexec.ensure_started()
    end)

    :ok
  end

  test "ensure_started does not stop erlexec when the worker is temporarily missing" do
    app_pid = Process.whereis(:exec_app)
    exec_pid = Process.whereis(:exec)

    assert is_pid(app_pid)
    assert is_pid(exec_pid)

    app_ref = Process.monitor(app_pid)
    exec_ref = Process.monitor(exec_pid)

    :sys.suspend(app_pid)
    Process.exit(exec_pid, :kill)

    assert_receive {:DOWN, ^exec_ref, :process, ^exec_pid, _reason}
    assert is_nil(Process.whereis(:exec))

    assert {:error, :exec_not_running} = Erlexec.ensure_started()
    refute_received {:DOWN, ^app_ref, :process, ^app_pid, _reason}

    :sys.resume(app_pid)
    assert :ok = Erlexec.ensure_started()
  end

  defp resume_exec_app do
    case Process.whereis(:exec_app) do
      pid when is_pid(pid) ->
        try do
          :sys.resume(pid)
        catch
          :exit, _ -> :ok
        end

      _ ->
        :ok
    end
  end
end
