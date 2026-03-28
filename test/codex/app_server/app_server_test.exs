defmodule Codex.AppServerTest do
  use ExUnit.Case, async: true

  alias Codex.AppServer
  alias Codex.AppServer.Protocol
  alias Codex.Options
  alias Codex.TestSupport.AppServerSubprocess

  test "connect/2 performs the handshake under the supervisor" do
    harness =
      AppServerSubprocess.new!(owner: self())
      |> AppServerSubprocess.put_current!()

    on_exit(fn -> AppServerSubprocess.cleanup(harness) end)

    {:ok, base_opts} = Options.new(%{api_key: "test"})
    codex_opts = AppServerSubprocess.codex_opts(base_opts, harness)

    task =
      Task.async(fn ->
        AppServer.connect(codex_opts,
          client_name: "codex_sdk_test",
          client_version: "0.0.0",
          init_timeout_ms: 200,
          process_env: AppServerSubprocess.process_env(harness)
        )
      end)

    conn_pid = await_supervised_connection!()
    :ok = AppServerSubprocess.attach(harness, conn_pid)

    assert_receive {:app_server_subprocess_started, ^conn_pid, os_pid}
    assert_receive {:app_server_subprocess_send, ^conn_pid, init_line}
    assert {:ok, %{"id" => 0, "method" => "initialize"}} = Jason.decode(init_line)

    :ok =
      AppServerSubprocess.send_stdout(
        Protocol.encode_response(0, %{"userAgent" => "codex/0.0.0"})
      )

    assert {:ok, conn} = Task.await(task, 200)
    assert conn == conn_pid

    assert_receive {:app_server_subprocess_send, ^conn_pid, initialized_line}
    assert {:ok, %{"method" => "initialized"}} = Jason.decode(initialized_line)

    ref = Process.monitor(conn)
    :ok = AppServer.disconnect(conn)
    assert_receive {:DOWN, ^ref, :process, ^conn, _reason}
  end

  test "connect/2 fails when app-server supervisor is unavailable" do
    harness =
      AppServerSubprocess.new!(owner: self())
      |> AppServerSubprocess.put_current!()

    on_exit(fn -> AppServerSubprocess.cleanup(harness) end)

    {:ok, base_opts} = Options.new(%{api_key: "test"})
    codex_opts = AppServerSubprocess.codex_opts(base_opts, harness)

    remove_connection_supervisor()

    on_exit(fn ->
      restore_connection_supervisor()
    end)

    assert {:error, :supervisor_unavailable} =
             AppServer.connect(codex_opts,
               init_timeout_ms: 200,
               process_env: AppServerSubprocess.process_env(harness)
             )
  end

  defp remove_connection_supervisor do
    if Process.whereis(Codex.Supervisor) && Process.whereis(Codex.AppServer.Supervisor) do
      :ok = Supervisor.terminate_child(Codex.Supervisor, Codex.AppServer.Supervisor)
      :ok = Supervisor.delete_child(Codex.Supervisor, Codex.AppServer.Supervisor)
    end
  end

  defp restore_connection_supervisor do
    if pid = Process.whereis(Codex.AppServer.Supervisor) do
      Process.exit(pid, :shutdown)
      Process.sleep(20)
    end

    if Process.whereis(Codex.Supervisor) && is_nil(Process.whereis(Codex.AppServer.Supervisor)) do
      {:ok, _pid} = Supervisor.start_child(Codex.Supervisor, {Codex.AppServer.Supervisor, []})
    end
  end

  defp await_supervised_connection! do
    started = System.monotonic_time(:millisecond)
    do_await_supervised_connection!(started)
  end

  defp do_await_supervised_connection!(started) do
    case DynamicSupervisor.which_children(Codex.AppServer.Supervisor) do
      [{_id, pid, :worker, [_module]} | _] when is_pid(pid) ->
        pid

      _other ->
        if System.monotonic_time(:millisecond) - started > 500 do
          flunk("timed out waiting for supervised app-server connection")
        else
          Process.sleep(10)
          do_await_supervised_connection!(started)
        end
    end
  end
end
