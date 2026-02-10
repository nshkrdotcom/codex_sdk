defmodule Codex.MCP.Transport.StdioTest do
  use ExUnit.Case, async: false

  alias Codex.MCP.Transport.Stdio

  defmodule FakeTransport do
    @behaviour Codex.IO.Transport
    use GenServer

    @impl true
    def start(opts), do: GenServer.start(__MODULE__, opts)

    @impl true
    def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

    @impl true
    def send(_pid, _message), do: :ok

    @impl true
    def subscribe(pid, subscriber) when is_pid(subscriber),
      do: subscribe(pid, subscriber, :legacy)

    @impl true
    def subscribe(pid, subscriber, tag) when is_pid(subscriber),
      do: GenServer.call(pid, {:subscribe, subscriber, tag})

    @impl true
    def close(pid) when is_pid(pid) do
      GenServer.stop(pid, :normal)
    catch
      :exit, _ -> :ok
    end

    @impl true
    def force_close(pid) when is_pid(pid) do
      GenServer.stop(pid, :normal)
      :ok
    catch
      :exit, _ -> :ok
    end

    @impl true
    def status(pid) when is_pid(pid) do
      if Process.alive?(pid), do: :connected, else: :disconnected
    end

    @impl true
    def end_input(_pid), do: :ok

    @impl true
    def stderr(_pid), do: ""

    def emit_exit(pid, reason) when is_pid(pid), do: GenServer.cast(pid, {:emit_exit, reason})

    @impl true
    def init(opts) do
      owner = Keyword.fetch!(opts, :owner)
      subscriber = Keyword.fetch!(opts, :subscriber)
      send(owner, {:stdio_fake_started, self(), subscriber})
      {:ok, %{subscriber: subscriber}}
    end

    @impl true
    def handle_call({:subscribe, pid, tag}, _from, _state) do
      {:reply, :ok, %{subscriber: {pid, tag}}}
    end

    @impl true
    def handle_cast({:emit_exit, reason}, %{subscriber: {pid, tag}} = state)
        when is_reference(tag) do
      send(pid, {:codex_io_transport, tag, {:exit, reason}})
      {:noreply, state}
    end

    def handle_cast({:emit_exit, reason}, %{subscriber: pid} = state) do
      send(pid, {:transport_exit, reason})
      {:noreply, state}
    end
  end

  test "recv waiters are drained when transport exits" do
    {:ok, transport} =
      Stdio.start_link(
        command: "mock",
        transport: {FakeTransport, owner: self()}
      )

    assert_receive {:stdio_fake_started, ^transport, {_pid, ref}} when is_reference(ref)

    waiter = Task.async(fn -> Stdio.recv(transport, 5_000) end)
    wait_for_waiter(transport)

    FakeTransport.emit_exit(transport, {:exit_status, 9})

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
