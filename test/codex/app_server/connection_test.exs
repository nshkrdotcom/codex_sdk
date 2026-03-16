defmodule Codex.AppServer.ConnectionTest do
  use ExUnit.Case, async: true

  alias Codex.AppServer.Connection
  alias Codex.AppServer.Protocol
  alias Codex.Config.Defaults
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
        transport: {AppServerSubprocess, owner: self()},
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

  test "handshake can opt into experimental app-server APIs", %{codex_opts: codex_opts} do
    {:ok, conn} =
      Connection.start_link(codex_opts,
        transport: {AppServerSubprocess, owner: self()},
        experimental_api: true,
        init_timeout_ms: 200
      )

    assert_receive {:app_server_subprocess_started, ^conn, os_pid}
    assert_receive {:app_server_subprocess_send, ^conn, init_line}

    assert {:ok, %{"id" => 0, "method" => "initialize", "params" => params}} =
             Jason.decode(init_line)

    assert params["capabilities"] == %{"experimentalApi" => true}

    send(conn, {:stdout, os_pid, Protocol.encode_response(0, %{"userAgent" => "codex/0.0.0"})})
    assert :ok == Connection.await_ready(conn, 200)
  end

  test "init failure stops subprocess when initialize send fails", %{codex_opts: codex_opts} do
    assert {:error, :send_failed} =
             Connection.start_link(codex_opts,
               transport:
                 {AppServerSubprocess,
                  owner: self(), send_result: {:error, :send_failed}, notify_stop: true},
               init_timeout_ms: 200
             )

    assert_receive {:app_server_subprocess_started, _conn, _os_pid}
    assert_receive {:app_server_subprocess_send, _conn, _init_line}
    assert_receive {:app_server_subprocess_stopped, _conn, _exec_pid}
  end

  test "initialize error surfaces via await_ready and shuts down the connection", %{
    codex_opts: codex_opts
  } do
    {:ok, conn} =
      Connection.start_link(codex_opts,
        transport: {AppServerSubprocess, owner: self(), notify_stop: true},
        init_timeout_ms: 200
      )

    monitor_ref = Process.monitor(conn)

    assert_receive {:app_server_subprocess_started, ^conn, os_pid}
    assert_receive {:app_server_subprocess_send, ^conn, init_line}
    assert {:ok, %{"id" => 0, "method" => "initialize"}} = Jason.decode(init_line)

    ready_task = Task.async(fn -> Connection.await_ready(conn, 200) end)
    wait_for_ready_waiter(conn, 1)

    send(
      conn,
      {:stdout, os_pid,
       [
         Jason.encode_to_iodata!(%{
           "id" => 0,
           "error" => %{"code" => -32_001, "message" => "initialize failed"}
         }),
         "\n"
       ]}
    )

    assert {:error, {:init_failed, %{"code" => -32_001, "message" => "initialize failed"}}} =
             Task.await(ready_task, 200)

    refute_receive {:app_server_subprocess_send, ^conn, _initialized_line}, 50

    assert_receive {:app_server_subprocess_stopped, ^conn, _exec_pid}, 200
    assert_receive {:DOWN, ^monitor_ref, :process, ^conn, :normal}, 200
    refute Process.alive?(conn)
  end

  test "transport exit during initialization returns a typed error with stderr context", %{
    codex_opts: codex_opts
  } do
    previous = Process.flag(:trap_exit, true)
    on_exit(fn -> Process.flag(:trap_exit, previous) end)

    {:ok, conn} =
      Connection.start_link(codex_opts,
        transport: {AppServerSubprocess, owner: self()},
        init_timeout_ms: 200
      )

    monitor_ref = Process.monitor(conn)

    assert_receive {:app_server_subprocess_started, ^conn, transport_ref}
    assert_receive {:app_server_subprocess_send, ^conn, init_line}
    assert {:ok, %{"id" => 0, "method" => "initialize"}} = Jason.decode(init_line)

    ready_task = Task.async(fn -> Connection.await_ready(conn, 200) end)
    wait_for_ready_waiter(conn, 1)

    send(conn, {:codex_io_transport, transport_ref, {:stderr, "bootstrap stderr"}})
    send(conn, {:codex_io_transport, transport_ref, {:exit, :boom}})

    assert {:error, {:app_server_down, %{reason: :boom, stderr: "bootstrap stderr"}}} =
             Task.await(ready_task, 200)

    assert_receive {:DOWN, ^monitor_ref, :process, ^conn,
                    {:shutdown, {:app_server_down, %{reason: :boom, stderr: "bootstrap stderr"}}}},
                   200
  end

  test "correlates request responses by id while interleaving notifications", %{
    codex_opts: codex_opts
  } do
    {:ok, conn} =
      Connection.start_link(codex_opts,
        transport: {AppServerSubprocess, owner: self()},
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
        transport: {AppServerSubprocess, owner: self()},
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

  test "transport exit while a request is pending returns a typed error with stderr context", %{
    codex_opts: codex_opts
  } do
    previous = Process.flag(:trap_exit, true)
    on_exit(fn -> Process.flag(:trap_exit, previous) end)

    {:ok, conn} =
      Connection.start_link(codex_opts,
        transport: {AppServerSubprocess, owner: self()},
        init_timeout_ms: 200
      )

    monitor_ref = Process.monitor(conn)

    assert_receive {:app_server_subprocess_started, ^conn, transport_ref}
    assert_receive {:app_server_subprocess_send, ^conn, init_line}
    assert {:ok, %{"id" => 0}} = Jason.decode(init_line)
    send(conn, {:stdout, transport_ref, Protocol.encode_response(0, %{})})
    assert :ok == Connection.await_ready(conn, 200)
    assert_receive {:app_server_subprocess_send, ^conn, _initialized_line}

    task =
      Task.async(fn ->
        Connection.request(conn, "thread/list", %{}, timeout_ms: 200)
      end)

    assert_receive {:app_server_subprocess_send, ^conn, request_line}
    assert {:ok, %{"method" => "thread/list"}} = Jason.decode(request_line)

    send(conn, {:codex_io_transport, transport_ref, {:stderr, "request stderr"}})
    send(conn, {:codex_io_transport, transport_ref, {:exit, :boom}})

    assert {:error, {:app_server_down, %{reason: :boom, stderr: "request stderr"}}} =
             Task.await(task, 200)

    assert_receive {:DOWN, ^monitor_ref, :process, ^conn,
                    {:shutdown, {:app_server_down, %{reason: :boom, stderr: "request stderr"}}}},
                   200
  end

  test "subscribe returns not_connected after the connection has gone down", %{
    codex_opts: codex_opts
  } do
    previous = Process.flag(:trap_exit, true)
    on_exit(fn -> Process.flag(:trap_exit, previous) end)

    {:ok, conn} =
      Connection.start_link(codex_opts,
        transport: {AppServerSubprocess, owner: self()},
        init_timeout_ms: 200
      )

    monitor_ref = Process.monitor(conn)

    assert_receive {:app_server_subprocess_started, ^conn, transport_ref}
    assert_receive {:app_server_subprocess_send, ^conn, init_line}
    assert {:ok, %{"id" => 0}} = Jason.decode(init_line)
    send(conn, {:stdout, transport_ref, Protocol.encode_response(0, %{})})
    assert :ok == Connection.await_ready(conn, 200)
    assert_receive {:app_server_subprocess_send, ^conn, _initialized_line}

    send(conn, {:codex_io_transport, transport_ref, {:exit, :boom}})

    assert_receive {:DOWN, ^monitor_ref, :process, ^conn,
                    {:shutdown, {:app_server_down, %{reason: :boom}}}},
                   200

    assert {:error, :not_connected} = Connection.subscribe(conn)
  end

  test "respond returns not_connected after the connection has gone down", %{
    codex_opts: codex_opts
  } do
    previous = Process.flag(:trap_exit, true)
    on_exit(fn -> Process.flag(:trap_exit, previous) end)

    {:ok, conn} =
      Connection.start_link(codex_opts,
        transport: {AppServerSubprocess, owner: self()},
        init_timeout_ms: 200
      )

    monitor_ref = Process.monitor(conn)

    assert_receive {:app_server_subprocess_started, ^conn, transport_ref}
    assert_receive {:app_server_subprocess_send, ^conn, init_line}
    assert {:ok, %{"id" => 0}} = Jason.decode(init_line)
    send(conn, {:stdout, transport_ref, Protocol.encode_response(0, %{})})
    assert :ok == Connection.await_ready(conn, 200)
    assert_receive {:app_server_subprocess_send, ^conn, _initialized_line}

    send(conn, {:codex_io_transport, transport_ref, {:exit, :boom}})

    assert_receive {:DOWN, ^monitor_ref, :process, ^conn,
                    {:shutdown, {:app_server_down, %{reason: :boom}}}},
                   200

    assert {:error, :not_connected} = Connection.respond(conn, 123, %{"ok" => true})
  end

  test "unsubscribe is a no-op after the connection has gone down", %{codex_opts: codex_opts} do
    previous = Process.flag(:trap_exit, true)
    on_exit(fn -> Process.flag(:trap_exit, previous) end)

    {:ok, conn} =
      Connection.start_link(codex_opts,
        transport: {AppServerSubprocess, owner: self()},
        init_timeout_ms: 200
      )

    monitor_ref = Process.monitor(conn)

    assert_receive {:app_server_subprocess_started, ^conn, transport_ref}
    assert_receive {:app_server_subprocess_send, ^conn, init_line}
    assert {:ok, %{"id" => 0}} = Jason.decode(init_line)
    send(conn, {:stdout, transport_ref, Protocol.encode_response(0, %{})})
    assert :ok == Connection.await_ready(conn, 200)
    assert_receive {:app_server_subprocess_send, ^conn, _initialized_line}

    send(conn, {:codex_io_transport, transport_ref, {:exit, :boom}})

    assert_receive {:DOWN, ^monitor_ref, :process, ^conn,
                    {:shutdown, {:app_server_down, %{reason: :boom}}}},
                   200

    assert :ok = Connection.unsubscribe(conn)
  end

  test "stderr retention is capped to the configured tail size", %{codex_opts: codex_opts} do
    {:ok, conn} =
      Connection.start_link(codex_opts,
        transport: {AppServerSubprocess, owner: self()},
        init_timeout_ms: 200
      )

    assert_receive {:app_server_subprocess_started, ^conn, os_pid}
    assert_receive {:app_server_subprocess_send, ^conn, init_line}
    assert {:ok, %{"id" => 0}} = Jason.decode(init_line)
    send(conn, {:stdout, os_pid, Protocol.encode_response(0, %{})})
    assert :ok == Connection.await_ready(conn, 200)
    assert_receive {:app_server_subprocess_send, ^conn, _initialized_line}

    cap = Defaults.transport_max_stderr_buffer_size()
    data = String.duplicate("x", cap) <> "tail"

    send(conn, {:stderr, os_pid, data})

    state = :sys.get_state(conn)
    assert byte_size(state.stderr) <= cap
    assert String.ends_with?(state.stderr, "tail")
  end

  test "ignores invalid subscriber filters without crashing", %{codex_opts: codex_opts} do
    {:ok, conn} =
      Connection.start_link(codex_opts,
        transport: {AppServerSubprocess, owner: self()},
        init_timeout_ms: 200
      )

    assert_receive {:app_server_subprocess_started, ^conn, os_pid}
    assert_receive {:app_server_subprocess_send, ^conn, init_line}
    assert {:ok, %{"id" => 0}} = Jason.decode(init_line)
    send(conn, {:stdout, os_pid, Protocol.encode_response(0, %{})})
    assert :ok == Connection.await_ready(conn, 200)
    assert_receive {:app_server_subprocess_send, ^conn, _initialized_line}

    :ok = Connection.subscribe(conn, methods: :bad, thread_id: 123)

    send(
      conn,
      {:stdout, os_pid, Protocol.encode_notification("turn/started", %{"threadId" => "thr_1"})}
    )

    refute_receive {:codex_notification, _, _}, 50
    assert Process.alive?(conn)
  end

  defp wait_for_ready_waiter(conn, expected) do
    started = System.monotonic_time(:millisecond)
    do_wait_for_ready_waiter(conn, expected, started)
  end

  defp do_wait_for_ready_waiter(conn, expected, started) do
    if ready_waiter_count(conn) == expected do
      :ok
    else
      if System.monotonic_time(:millisecond) - started > 500 do
        flunk("timed out waiting for ready waiter count #{expected}")
      else
        Process.sleep(10)
        do_wait_for_ready_waiter(conn, expected, started)
      end
    end
  end

  defp ready_waiter_count(conn) do
    conn
    |> :sys.get_state()
    |> Map.fetch!(:ready_waiters)
    |> length()
  end
end
