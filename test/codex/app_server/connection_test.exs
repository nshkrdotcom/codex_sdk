defmodule Codex.AppServer.ConnectionTest do
  use ExUnit.Case, async: true

  alias Codex.AppServer.Connection
  alias Codex.AppServer.Protocol
  alias Codex.Options
  alias Codex.TestSupport.AppServerSubprocess

  setup do
    bash = System.find_executable("bash") || "/bin/bash"
    {:ok, codex_opts} = Options.new(%{api_key: "test", codex_path_override: bash})
    {:ok, codex_opts: codex_opts}
  end

  test "handshake: sends initialize then initialized", %{codex_opts: codex_opts} do
    {:ok, conn} =
      Connection.start_link(codex_opts,
        subprocess: {AppServerSubprocess, owner: self()},
        client_name: "codex_sdk_test",
        client_version: "0.0.0",
        init_timeout_ms: 200
      )

    assert_receive {:app_server_subprocess_started, ^conn, os_pid}

    assert_receive {:app_server_subprocess_send, ^conn, init_line}

    assert {:ok, %{"id" => 0, "method" => "initialize", "params" => params}} =
             Jason.decode(init_line)

    assert params["clientInfo"]["name"] == "codex_sdk_test"
    assert params["clientInfo"]["version"] == "0.0.0"

    send(conn, {:stdout, os_pid, Protocol.encode_response(0, %{"userAgent" => "codex/0.0.0"})})

    assert :ok == Connection.await_ready(conn, 200)

    assert_receive {:app_server_subprocess_send, ^conn, initialized_line}
    assert {:ok, %{"method" => "initialized"}} = Jason.decode(initialized_line)
  end

  test "correlates request responses by id while interleaving notifications", %{
    codex_opts: codex_opts
  } do
    {:ok, conn} =
      Connection.start_link(codex_opts,
        subprocess: {AppServerSubprocess, owner: self()},
        init_timeout_ms: 200
      )

    assert_receive {:app_server_subprocess_started, ^conn, os_pid}
    assert_receive {:app_server_subprocess_send, ^conn, init_line}
    assert {:ok, %{"id" => 0}} = Jason.decode(init_line)
    send(conn, {:stdout, os_pid, Protocol.encode_response(0, %{})})
    assert :ok == Connection.await_ready(conn, 200)
    assert_receive {:app_server_subprocess_send, ^conn, _initialized_line}

    :ok = Connection.subscribe(conn)

    task =
      Task.async(fn ->
        Connection.request(conn, "thread/list", %{}, timeout_ms: 200)
      end)

    assert_receive {:app_server_subprocess_send, ^conn, request_line}
    assert {:ok, %{"id" => request_id, "method" => "thread/list"}} = Jason.decode(request_line)

    chunk = [
      Protocol.encode_notification("turn/started", %{
        "threadId" => "thr_1",
        "turn" => %{"id" => "t1"}
      }),
      Protocol.encode_response(request_id, %{"data" => [], "nextCursor" => nil})
    ]

    send(conn, {:stdout, os_pid, chunk})

    assert_receive {:codex_notification, "turn/started", %{"threadId" => "thr_1"}}
    assert {:ok, %{"data" => [], "nextCursor" => nil}} = Task.await(task, 200)
  end

  test "request timeouts clean up in-flight state", %{codex_opts: codex_opts} do
    {:ok, conn} =
      Connection.start_link(codex_opts,
        subprocess: {AppServerSubprocess, owner: self()},
        init_timeout_ms: 200
      )

    assert_receive {:app_server_subprocess_started, ^conn, os_pid}
    assert_receive {:app_server_subprocess_send, ^conn, init_line}
    assert {:ok, %{"id" => 0}} = Jason.decode(init_line)
    send(conn, {:stdout, os_pid, Protocol.encode_response(0, %{})})
    assert :ok == Connection.await_ready(conn, 200)
    assert_receive {:app_server_subprocess_send, ^conn, _initialized_line}

    assert {:error, {:timeout, "thread/list", 10}} =
             Connection.request(conn, "thread/list", %{}, timeout_ms: 10)
  end
end
