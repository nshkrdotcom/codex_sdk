defmodule Codex.MCP.Transport.StdioTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  alias CliSubprocessCore.ProtocolSession
  alias CliSubprocessCore.TestSupport.FakeSSH
  alias Codex.MCP.Transport.Stdio
  alias Codex.TestSupport.AppServerSubprocess

  test "recv waiters are drained when the protocol session exits" do
    harness = AppServerSubprocess.new!(owner: self())

    {:ok, transport} =
      Stdio.start_link(
        command: AppServerSubprocess.command_path(harness),
        env: AppServerSubprocess.process_env(harness)
      )

    on_exit(fn ->
      stop_transport(transport)
      AppServerSubprocess.cleanup(harness)
    end)

    :ok = AppServerSubprocess.attach(harness, transport)

    waiter = Task.async(fn -> Stdio.recv(transport, 5_000) end)
    wait_for_waiter(transport)
    monitor_ref = Process.monitor(transport)

    capture_log(fn ->
      :ok = AppServerSubprocess.exit(harness, 9)

      assert Task.await(waiter, 1_000) == {:error, :closed}
      assert_receive {:DOWN, ^monitor_ref, :process, ^transport, _reason}, 1_000
    end)

    refute Process.alive?(transport)
  end

  test "runtime is backed by ProtocolSession with line stdout and raw stdin" do
    harness = AppServerSubprocess.new!(owner: self())

    {:ok, transport} =
      Stdio.start_link(
        command: AppServerSubprocess.command_path(harness),
        env: AppServerSubprocess.process_env(harness)
      )

    on_exit(fn ->
      stop_transport(transport)
      AppServerSubprocess.cleanup(harness)
    end)

    :ok = AppServerSubprocess.attach(harness, transport)
    assert_receive {:app_server_subprocess_started, ^transport, _os_pid}, 1_000

    assert %{session: session} = :sys.get_state(transport)
    assert %{phase: :ready, channel: %{raw_session: raw_session}} = ProtocolSession.info(session)
    assert raw_session.stdout_mode == :line
    assert raw_session.stdin_mode == :raw
  end

  test "stdio requests and notifications run over fake SSH" do
    harness = AppServerSubprocess.new!(owner: self())
    fake_ssh = FakeSSH.new!()

    {:ok, transport} =
      Stdio.start_link(
        command: AppServerSubprocess.command_path(harness),
        env: AppServerSubprocess.process_env(harness),
        execution_surface: [
          surface_kind: :ssh_exec,
          transport_options:
            FakeSSH.transport_options(fake_ssh,
              destination: "mcp-stdio.test.example",
              port: 2222
            )
        ]
      )

    on_exit(fn ->
      stop_transport(transport)
      AppServerSubprocess.cleanup(harness)
      FakeSSH.cleanup(fake_ssh)
    end)

    :ok = AppServerSubprocess.attach(harness, transport)

    assert :ok =
             Stdio.send(transport, %{
               "jsonrpc" => "2.0",
               "id" => "req-1",
               "method" => "tools/list",
               "params" => %{"cursor" => nil}
             })

    assert_receive {:app_server_subprocess_send, ^transport, request_line}, 1_000

    assert {:ok,
            %{
              "jsonrpc" => "2.0",
              "id" => "req-1",
              "method" => "tools/list",
              "params" => %{"cursor" => nil}
            }} = Jason.decode(request_line)

    :ok =
      AppServerSubprocess.send_stdout(
        harness,
        Jason.encode!(%{
          "jsonrpc" => "2.0",
          "id" => "req-1",
          "result" => %{"data" => []}
        }) <> "\n"
      )

    assert {:ok, %{"id" => "req-1", "result" => %{"data" => []}}} = Stdio.recv(transport, 1_000)

    :ok =
      AppServerSubprocess.send_stdout(
        harness,
        Jason.encode!(%{
          "jsonrpc" => "2.0",
          "method" => "notifications/ping",
          "params" => %{"ts" => 1}
        }) <> "\n"
      )

    assert {:ok,
            %{
              "jsonrpc" => "2.0",
              "method" => "notifications/ping",
              "params" => %{"ts" => 1}
            }} = Stdio.recv(transport, 1_000)

    assert FakeSSH.wait_until_written(fake_ssh, 1_000) == :ok
    assert FakeSSH.read_manifest!(fake_ssh) =~ "destination=mcp-stdio.test.example"
  end

  defp wait_for_waiter(transport) do
    started = System.monotonic_time(:millisecond)

    wait_until(
      fn ->
        case :sys.get_state(transport) do
          %{waiters: [_ | _]} -> true
          _ -> false
        end
      end,
      started
    )
  end

  defp wait_until(fun, started) do
    if fun.() do
      :ok
    else
      if System.monotonic_time(:millisecond) - started > 500 do
        flunk("timed out waiting for waiter registration")
      else
        Process.sleep(10)
        wait_until(fun, started)
      end
    end
  end

  defp stop_transport(transport) when is_pid(transport) do
    if Process.alive?(transport) do
      GenServer.stop(transport, :normal)
    end

    :ok
  end
end
