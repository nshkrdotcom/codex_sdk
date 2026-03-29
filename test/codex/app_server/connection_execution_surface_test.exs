defmodule Codex.AppServer.ConnectionExecutionSurfaceTest do
  use ExUnit.Case, async: false

  alias CliSubprocessCore.ProtocolSession
  alias CliSubprocessCore.TestSupport.FakeSSH
  alias Codex.AppServer.Connection
  alias Codex.AppServer.Protocol
  alias Codex.Options
  alias Codex.TestSupport.AppServerSubprocess

  test "app-server connection handshakes and requests over fake SSH" do
    harness = AppServerSubprocess.new!(owner: self())
    fake_ssh = FakeSSH.new!()

    on_exit(fn ->
      AppServerSubprocess.cleanup(harness)
      FakeSSH.cleanup(fake_ssh)
    end)

    {:ok, base_opts} = Options.new(%{api_key: "test"})
    codex_opts = AppServerSubprocess.codex_opts(base_opts, harness)

    {:ok, conn} =
      Connection.start_link(codex_opts,
        init_timeout_ms: 500,
        process_env: AppServerSubprocess.process_env(harness),
        execution_surface: [
          surface_kind: :ssh_exec,
          transport_options:
            FakeSSH.transport_options(fake_ssh,
              destination: "app-server.test.example",
              port: 2222
            )
        ]
      )

    :ok = AppServerSubprocess.attach(harness, conn)

    assert_receive {:app_server_subprocess_started, ^conn, _os_pid}, 1_000
    assert_receive {:app_server_subprocess_send, ^conn, init_line}, 1_000

    assert {:ok, %{"id" => 0, "method" => "initialize"}} = Jason.decode(init_line)

    :ok =
      AppServerSubprocess.send_stdout(
        harness,
        Protocol.encode_response(0, %{"userAgent" => "codex/0.0.0"})
      )

    assert :ok == Connection.await_ready(conn, 1_000)
    assert_receive {:app_server_subprocess_send, ^conn, initialized_line}, 1_000
    assert {:ok, %{"method" => "initialized"}} = Jason.decode(initialized_line)

    task =
      Task.async(fn ->
        Connection.request(conn, "thread/list", %{}, timeout_ms: 1_000)
      end)

    assert_receive {:app_server_subprocess_send, ^conn, request_line}, 1_000
    assert {:ok, %{"id" => request_id, "method" => "thread/list"}} = Jason.decode(request_line)

    :ok =
      AppServerSubprocess.send_stdout(
        harness,
        Protocol.encode_response(request_id, %{"data" => [], "nextCursor" => nil})
      )

    assert {:ok, %{"data" => [], "nextCursor" => nil}} = Task.await(task, 1_000)

    assert %{session: session} = :sys.get_state(conn)
    assert %{phase: :ready, channel: %{raw_session: raw_session}} = ProtocolSession.info(session)
    assert raw_session.stdout_mode == :line
    assert raw_session.stdin_mode == :raw

    assert FakeSSH.wait_until_written(fake_ssh, 1_000) == :ok
    assert FakeSSH.read_manifest!(fake_ssh) =~ "destination=app-server.test.example"
  end
end
