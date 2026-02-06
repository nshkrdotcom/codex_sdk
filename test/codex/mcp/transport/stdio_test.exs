defmodule Codex.MCP.Transport.StdioTest do
  use ExUnit.Case, async: false

  alias Codex.MCP.Transport.Stdio

  defmodule FakeSubprocess do
    def start(_command, _run_opts, opts) do
      owner = Keyword.fetch!(opts, :owner)
      os_pid = Keyword.fetch!(opts, :os_pid)

      exec_pid =
        spawn(fn ->
          receive do
            :stop -> :ok
          end
        end)

      send(owner, {:stdio_fake_started, self(), exec_pid, os_pid})
      {:ok, exec_pid, os_pid}
    end

    def send(_pid, _data, _opts), do: :ok

    def stop(pid, opts) do
      owner = Keyword.get(opts, :owner)

      if is_pid(pid) and Process.alive?(pid) do
        send(pid, :stop)
      end

      if is_pid(owner) do
        send(owner, {:stdio_fake_stopped, self(), pid})
      end

      :ok
    end
  end

  test "recv waiters are drained when subprocess DOWN arrives keyed by os_pid" do
    {:ok, transport} =
      Stdio.start_link(
        command: "mock",
        subprocess_mod: FakeSubprocess,
        subprocess_opts: [owner: self(), os_pid: 77]
      )

    assert_receive {:stdio_fake_started, ^transport, _exec_pid, 77}

    waiter = Task.async(fn -> Stdio.recv(transport, 5_000) end)
    wait_for_waiter(transport)

    send(transport, {:DOWN, 77, :process, make_ref(), {:exit_status, 9}})

    assert Task.await(waiter, 500) == {:error, :closed}
    refute Process.alive?(transport)
  end

  defp wait_for_waiter(transport) do
    start = System.monotonic_time(:millisecond)

    wait_until(
      fn ->
        case :sys.get_state(transport) do
          %{waiters: [_ | _]} -> true
          _ -> false
        end
      end,
      start
    )
  end

  defp wait_until(fun, start) do
    if fun.() do
      :ok
    else
      now = System.monotonic_time(:millisecond)

      if now - start > 500 do
        flunk("timed out waiting for waiter registration")
      else
        Process.sleep(10)
        wait_until(fun, start)
      end
    end
  end
end
