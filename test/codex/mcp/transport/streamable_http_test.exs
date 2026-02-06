defmodule Codex.MCP.Transport.StreamableHTTPTest do
  use ExUnit.Case, async: false

  alias Codex.MCP.Transport.StreamableHTTP

  setup do
    previous_flag = Process.flag(:trap_exit, true)

    {:ok, transport} =
      StreamableHTTP.start_link(
        url: "http://127.0.0.1:1/mcp",
        server_name: "test_server"
      )

    on_exit(fn ->
      Process.flag(:trap_exit, previous_flag)

      if Process.alive?(transport) do
        GenServer.stop(transport, :normal)
      end
    end)

    {:ok, transport: transport}
  end

  test "handles 2-element worker errors without crashing", %{transport: transport} do
    test_pid = self()
    from_ref = make_ref()

    :sys.replace_state(transport, fn state ->
      %{
        state
        | in_flight: %{
            pid: test_pid,
            ref: make_ref(),
            job: {:send, {test_pid, from_ref}, %{"method" => "notifications/ping"}, 10}
          }
      }
    end)

    send(transport, {:work_result, test_pid, {:error, :boom}})

    assert_receive {^from_ref, {:error, :boom}}
    assert Process.alive?(transport)
  end

  test "terminate replies queued send callers with closed error", %{transport: transport} do
    blocker =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    blocker_ref = Process.monitor(blocker)

    :sys.replace_state(transport, fn state ->
      %{
        state
        | in_flight: %{
            pid: blocker,
            ref: blocker_ref,
            job: {:send, {self(), make_ref()}, %{"method" => "notifications/active"}, 10}
          }
      }
    end)

    caller =
      Task.async(fn ->
        StreamableHTTP.send(transport, %{"jsonrpc" => "2.0", "method" => "notifications/ping"})
      end)

    Process.sleep(25)
    GenServer.stop(transport, :shutdown)

    assert Task.await(caller, 1_000) == {:error, :closed}
    refute Process.alive?(blocker)
  end

  test "terminate replies in-flight caller with closed error", %{transport: transport} do
    test_pid = self()
    from_ref = make_ref()

    worker =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    worker_ref = Process.monitor(worker)

    :sys.replace_state(transport, fn state ->
      %{
        state
        | in_flight: %{
            pid: worker,
            ref: worker_ref,
            job: {:send, {test_pid, from_ref}, %{"method" => "notifications/ping"}, 10}
          }
      }
    end)

    GenServer.stop(transport, :shutdown)

    assert_receive {^from_ref, {:error, :closed}}
    refute Process.alive?(worker)
  end
end
