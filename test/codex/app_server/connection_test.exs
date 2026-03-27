defmodule Codex.AppServer.ConnectionTest do
  use ExUnit.Case, async: true
  @moduletag capture_log: true

  import ExUnit.CaptureLog

  alias CliSubprocessCore.RawSession
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

  test "launch options forward cwd and merged child env overrides", %{codex_opts: codex_opts} do
    {:ok, conn} =
      Connection.start_link(codex_opts,
        transport: {AppServerSubprocess, owner: self()},
        cwd: "/tmp/codex-app-server-fixture",
        env: [CODEX_HOME: "/tmp/ignored-home"],
        process_env: [
          CODEX_HOME: "/tmp/isolated-codex-home",
          HOME: "/tmp/isolated-codex-home",
          USERPROFILE: "/tmp/isolated-codex-home",
          EXTRA_FLAG: 123
        ],
        init_timeout_ms: 200
      )

    assert_receive {:app_server_subprocess_started, ^conn, os_pid}

    assert_receive {:app_server_subprocess_start_opts, ^conn, ^os_pid, start_opts}

    assert %CliSubprocessCore.Command{} = command = Keyword.fetch!(start_opts, :command)
    assert command.cwd == "/tmp/codex-app-server-fixture"

    env =
      Map.new(command.env)

    assert env["CODEX_HOME"] == "/tmp/isolated-codex-home"
    assert env["HOME"] == "/tmp/isolated-codex-home"
    assert env["USERPROFILE"] == "/tmp/isolated-codex-home"
    assert env["EXTRA_FLAG"] == "123"
    assert env["CODEX_API_KEY"] == "test"
    assert env["OPENAI_API_KEY"] == "test"
    assert env["CODEX_INTERNAL_ORIGINATOR_OVERRIDE"] == "codex_sdk_elixir"
  end

  test "transport start options include the codex event tag contract", %{codex_opts: codex_opts} do
    {:ok, conn} =
      Connection.start_link(codex_opts,
        transport: {AppServerSubprocess, owner: self()},
        init_timeout_ms: 200
      )

    assert_receive {:app_server_subprocess_started, ^conn, transport_ref}
    assert_receive {:app_server_subprocess_start_opts, ^conn, ^transport_ref, start_opts}
    assert start_opts[:event_tag] == :codex_io_transport
  end

  test "launch args include payload-derived local oss config overrides" do
    codex_opts = %Options{
      api_key: nil,
      codex_path_override: System.find_executable("bash") || "/bin/bash",
      model: "gpt-oss:20b",
      model_payload: %{
        provider_backend: :oss,
        backend_metadata: %{"oss_provider" => "ollama"}
      }
    }

    {:ok, conn} =
      Connection.start_link(codex_opts,
        transport: {AppServerSubprocess, owner: self()},
        init_timeout_ms: 200
      )

    assert_receive {:app_server_subprocess_started, ^conn, os_pid}
    assert_receive {:app_server_subprocess_start_opts, ^conn, ^os_pid, start_opts}

    assert %CliSubprocessCore.Command{} = command = Keyword.fetch!(start_opts, :command)

    assert command.args == [
             "app-server",
             "--config",
             "model_provider=\"ollama\"",
             "--config",
             "model=\"gpt-oss:20b\""
           ]
  end

  test "launch command resolves cwd-sensitive asdf shims to stable executables" do
    {root, shim_path, resolved_path} = build_fake_asdf_codex()

    try do
      previous_asdf_dir = System.get_env("ASDF_DIR")
      System.put_env("ASDF_DIR", Path.join(root, ".asdf"))

      on_exit(fn ->
        case previous_asdf_dir do
          nil -> System.delete_env("ASDF_DIR")
          value -> System.put_env("ASDF_DIR", value)
        end
      end)

      {:ok, codex_opts} = Options.new(%{api_key: "test", codex_path_override: shim_path})

      {:ok, conn} =
        Connection.start_link(codex_opts,
          transport: {AppServerSubprocess, owner: self()},
          cwd: "/tmp/codex-app-server-fixture",
          init_timeout_ms: 200
        )

      assert_receive {:app_server_subprocess_started, ^conn, os_pid}
      assert_receive {:app_server_subprocess_start_opts, ^conn, ^os_pid, start_opts}

      assert %CliSubprocessCore.Command{} = command = Keyword.fetch!(start_opts, :command)
      assert command.command == resolved_path
    after
      File.rm_rf(root)
    end
  end

  test "runtime is backed by a raw session with line stdout and raw stdin", %{
    codex_opts: codex_opts
  } do
    {:ok, conn} =
      Connection.start_link(codex_opts,
        transport: {AppServerSubprocess, owner: self()},
        init_timeout_ms: 200
      )

    assert_receive {:app_server_subprocess_started, ^conn, transport_ref}
    assert_receive {:app_server_subprocess_start_opts, ^conn, ^transport_ref, start_opts}
    assert start_opts[:stdout_mode] == :line
    assert start_opts[:stdin_mode] == :raw

    assert %{raw_session: %RawSession{} = raw_session} = :sys.get_state(conn)
    assert raw_session.event_tag == :codex_io_transport
    assert raw_session.stdout_mode == :line
    assert raw_session.stdin_mode == :raw
  end

  test "healthy child stderr does not produce live debug logs", %{codex_opts: codex_opts} do
    {:ok, conn} =
      Connection.start_link(codex_opts,
        transport: {AppServerSubprocess, owner: self()},
        init_timeout_ms: 200
      )

    assert_receive {:app_server_subprocess_started, ^conn, transport_ref}
    assert_receive {:app_server_subprocess_send, ^conn, init_line}
    assert {:ok, %{"id" => 0}} = Jason.decode(init_line)
    send(conn, {:stdout, transport_ref, Protocol.encode_response(0, %{})})
    assert :ok == Connection.await_ready(conn, 200)
    assert_receive {:app_server_subprocess_send, ^conn, _initialized_line}

    log =
      capture_log([level: :debug], fn ->
        send(conn, {:codex_io_transport, transport_ref, {:stderr, "non-fatal child stderr"}})
        Process.sleep(20)
      end)

    refute log =~ "codex app-server stderr:"
    assert Process.alive?(conn)
  end

  test "launch options reject invalid child env overrides", %{codex_opts: codex_opts} do
    assert {:error, {:invalid_env, ["/tmp/not-a-keyword"]}} =
             Connection.start_link(codex_opts,
               transport: {AppServerSubprocess, owner: self()},
               process_env: ["/tmp/not-a-keyword"],
               init_timeout_ms: 200
             )

    refute_receive {:app_server_subprocess_started, _, _}
  end

  test "launch options reject invalid cwd overrides", %{codex_opts: codex_opts} do
    assert {:error, {:invalid_cwd, 123}} =
             Connection.start_link(codex_opts,
               transport: {AppServerSubprocess, owner: self()},
               cwd: 123,
               init_timeout_ms: 200
             )

    refute_receive {:app_server_subprocess_started, _, _}
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

  test "transport exit during initialization returns a typed error with retained stderr context",
       %{
         codex_opts: codex_opts
       } do
    previous = Process.flag(:trap_exit, true)
    on_exit(fn -> Process.flag(:trap_exit, previous) end)

    {:ok, conn} =
      Connection.start_link(codex_opts,
        transport: {AppServerSubprocess, owner: self(), stderr: "bootstrap stderr"},
        init_timeout_ms: 200
      )

    monitor_ref = Process.monitor(conn)

    assert_receive {:app_server_subprocess_started, ^conn, transport_ref}
    assert_receive {:app_server_subprocess_send, ^conn, init_line}
    assert {:ok, %{"id" => 0, "method" => "initialize"}} = Jason.decode(init_line)

    ready_task = Task.async(fn -> Connection.await_ready(conn, 200) end)
    wait_for_ready_waiter(conn, 1)

    send(conn, {:codex_io_transport, transport_ref, {:exit, :boom}})

    assert {:error, {:app_server_down, %{reason: :boom, stderr: "bootstrap stderr"}}} =
             Task.await(ready_task, 200)

    assert_receive {:DOWN, ^monitor_ref, :process, ^conn,
                    {:shutdown, {:app_server_down, %{reason: :boom, stderr: "bootstrap stderr"}}}},
                   200
  end

  test "transport exit during initialization reads retained stderr from the raw session", %{
    codex_opts: codex_opts
  } do
    previous = Process.flag(:trap_exit, true)
    on_exit(fn -> Process.flag(:trap_exit, previous) end)

    {:ok, conn} =
      Connection.start_link(codex_opts,
        transport: {AppServerSubprocess, owner: self(), stderr: "retained stderr"},
        init_timeout_ms: 200
      )

    monitor_ref = Process.monitor(conn)

    assert_receive {:app_server_subprocess_started, ^conn, transport_ref}
    assert_receive {:app_server_subprocess_send, ^conn, init_line}
    assert {:ok, %{"id" => 0, "method" => "initialize"}} = Jason.decode(init_line)

    ready_task = Task.async(fn -> Connection.await_ready(conn, 200) end)
    wait_for_ready_waiter(conn, 1)

    send(conn, {:codex_io_transport, transport_ref, {:exit, :boom}})

    assert {:error, {:app_server_down, %{reason: :boom, stderr: "retained stderr"}}} =
             Task.await(ready_task, 200)

    assert_receive {:DOWN, ^monitor_ref, :process, ^conn,
                    {:shutdown, {:app_server_down, %{reason: :boom, stderr: "retained stderr"}}}},
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

  test "transport exit while a request is pending returns a typed error with retained stderr context",
       %{
         codex_opts: codex_opts
       } do
    previous = Process.flag(:trap_exit, true)
    on_exit(fn -> Process.flag(:trap_exit, previous) end)

    {:ok, conn} =
      Connection.start_link(codex_opts,
        transport: {AppServerSubprocess, owner: self(), stderr: "request stderr"},
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

  test "stderr context comes from the retained transport tail", %{codex_opts: codex_opts} do
    previous = Process.flag(:trap_exit, true)
    on_exit(fn -> Process.flag(:trap_exit, previous) end)

    cap = Defaults.transport_max_stderr_buffer_size()
    retained = String.duplicate("x", cap) <> "tail"

    {:ok, conn} =
      Connection.start_link(codex_opts,
        transport: {AppServerSubprocess, owner: self(), stderr: retained},
        init_timeout_ms: 200
      )

    monitor_ref = Process.monitor(conn)

    assert_receive {:app_server_subprocess_started, ^conn, transport_ref}
    assert_receive {:app_server_subprocess_send, ^conn, init_line}
    assert {:ok, %{"id" => 0, "method" => "initialize"}} = Jason.decode(init_line)

    ready_task = Task.async(fn -> Connection.await_ready(conn, 200) end)
    wait_for_ready_waiter(conn, 1)

    send(conn, {:codex_io_transport, transport_ref, {:exit, :boom}})

    assert {:error, {:app_server_down, %{reason: :boom, stderr: ^retained}}} =
             Task.await(ready_task, 200)

    assert_receive {:DOWN, ^monitor_ref, :process, ^conn,
                    {:shutdown, {:app_server_down, %{reason: :boom, stderr: ^retained}}}},
                   200
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

  defp build_fake_asdf_codex do
    root =
      Path.join(System.tmp_dir!(), "codex_app_server_asdf_#{System.unique_integer([:positive])}")

    asdf_root = Path.join(root, ".asdf")
    bin_dir = Path.join(asdf_root, "bin")
    shim_dir = Path.join(asdf_root, "shims")
    installs_dir = Path.join(root, "installs/nodejs/25.1.0/bin")

    File.mkdir_p!(bin_dir)
    File.mkdir_p!(shim_dir)
    File.mkdir_p!(installs_dir)

    resolved_path =
      Path.join(installs_dir, "codex")
      |> then(fn path ->
        File.write!(path, "#!/bin/bash\nexit 0\n")
        File.chmod!(path, 0o755)
        path
      end)

    asdf_path =
      Path.join(bin_dir, "asdf")
      |> then(fn path ->
        File.write!(
          path,
          """
          #!/bin/sh
          if [ "$1" = "which" ] && [ "$2" = "codex" ]; then
            printf '%s\\n' "#{resolved_path}"
            exit 0
          fi

          printf 'unsupported asdf invocation: %s %s\\n' "$1" "$2" >&2
          exit 1
          """
        )

        File.chmod!(path, 0o755)
        path
      end)

    shim_path =
      Path.join(shim_dir, "codex")
      |> then(fn path ->
        File.write!(
          path,
          """
          #!/bin/sh
          exec "#{asdf_path}" exec "codex" "$@"
          """
        )

        File.chmod!(path, 0o755)
        path
      end)

    {root, shim_path, resolved_path}
  end
end
