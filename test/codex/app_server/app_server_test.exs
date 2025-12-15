defmodule Codex.AppServerTest do
  use ExUnit.Case, async: true

  alias Codex.AppServer
  alias Codex.AppServer.Protocol
  alias Codex.Options
  alias Codex.TestSupport.AppServerSubprocess

  test "connect/2 performs the handshake under the supervisor" do
    bash = System.find_executable("bash") || "/bin/bash"
    {:ok, codex_opts} = Options.new(%{api_key: "test", codex_path_override: bash})
    owner = self()

    task =
      Task.async(fn ->
        AppServer.connect(codex_opts,
          subprocess: {AppServerSubprocess, owner: owner},
          client_name: "codex_sdk_test",
          client_version: "0.0.0",
          init_timeout_ms: 200
        )
      end)

    assert_receive {:app_server_subprocess_started, conn_pid, os_pid}
    assert_receive {:app_server_subprocess_send, ^conn_pid, init_line}
    assert {:ok, %{"id" => 0, "method" => "initialize"}} = Jason.decode(init_line)

    send(
      conn_pid,
      {:stdout, os_pid, Protocol.encode_response(0, %{"userAgent" => "codex/0.0.0"})}
    )

    assert {:ok, conn} = Task.await(task, 200)
    assert conn == conn_pid

    assert_receive {:app_server_subprocess_send, ^conn_pid, initialized_line}
    assert {:ok, %{"method" => "initialized"}} = Jason.decode(initialized_line)

    ref = Process.monitor(conn)
    :ok = AppServer.disconnect(conn)
    assert_receive {:DOWN, ^ref, :process, ^conn, _reason}
  end
end
