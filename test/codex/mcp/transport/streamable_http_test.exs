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

  test "fallback worker crash does not crash the transport process" do
    {:ok, listener} =
      :gen_tcp.listen(0, [
        :binary,
        active: false,
        packet: :raw,
        reuseaddr: true
      ])

    {:ok, port} = :inet.port(listener)

    socket_holder =
      spawn(fn ->
        case :gen_tcp.accept(listener) do
          {:ok, socket} ->
            receive do
              :close -> :ok
            after
              5_000 -> :ok
            end

            :gen_tcp.close(socket)

          {:error, _reason} ->
            :ok
        end
      end)

    on_exit(fn ->
      send(socket_holder, :close)
      :gen_tcp.close(listener)
    end)

    remove_task_supervisor()

    on_exit(fn ->
      restore_task_supervisor()
    end)

    {:ok, transport} =
      StreamableHTTP.start_link(
        url: "http://127.0.0.1:#{port}/mcp",
        server_name: "fallback_worker_crash_test"
      )

    on_exit(fn ->
      if Process.alive?(transport) do
        GenServer.stop(transport, :normal)
      end
    end)

    caller =
      Task.async(fn ->
        StreamableHTTP.send(transport, %{"jsonrpc" => "2.0", "method" => "notifications/ping"})
      end)

    worker_pid = wait_for_in_flight_pid(transport)
    Process.exit(worker_pid, :boom)

    assert Task.await(caller, 1_000) == {:error, {:worker_down, :boom}}
    assert Process.alive?(transport)
  end

  defp wait_for_in_flight_pid(transport) do
    start = System.monotonic_time(:millisecond)

    wait_until(start, fn ->
      case :sys.get_state(transport) do
        %{in_flight: %{pid: pid}} when is_pid(pid) -> {:ok, pid}
        _ -> :retry
      end
    end)
  end

  defp wait_until(start, fun) do
    case fun.() do
      {:ok, value} ->
        value

      :retry ->
        if System.monotonic_time(:millisecond) - start > 1_000 do
          flunk("timed out waiting for worker start")
        else
          Process.sleep(10)
          wait_until(start, fun)
        end
    end
  end

  defp remove_task_supervisor do
    case Process.whereis(Codex.Supervisor) do
      nil ->
        :ok

      _pid ->
        case Process.whereis(Codex.TaskSupervisor) do
          nil ->
            :ok

          _ ->
            :ok = Supervisor.terminate_child(Codex.Supervisor, Codex.TaskSupervisor)
            :ok = Supervisor.delete_child(Codex.Supervisor, Codex.TaskSupervisor)
        end
    end
  end

  defp restore_task_supervisor do
    cond do
      is_nil(Process.whereis(Codex.Supervisor)) ->
        :ok

      is_pid(Process.whereis(Codex.TaskSupervisor)) ->
        :ok

      true ->
        case Supervisor.start_child(
               Codex.Supervisor,
               {Task.Supervisor, name: Codex.TaskSupervisor}
             ) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
        end
    end
  end
end
