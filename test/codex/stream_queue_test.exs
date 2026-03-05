defmodule Codex.StreamQueueTest do
  use ExUnit.Case, async: true

  alias Codex.StreamQueue

  test "removes dead pop waiters on caller DOWN" do
    {:ok, queue} = StreamQueue.start_link()

    waiter_pid =
      spawn(fn ->
        _ = StreamQueue.pop(queue, :infinity)
      end)

    wait_for_waiter_count(queue, 1)

    Process.exit(waiter_pid, :kill)
    Process.sleep(50)

    assert waiter_count(queue) == 0
  end

  test "close: preserves buffered items and drops pushes after close" do
    {:ok, queue} = StreamQueue.start_link()

    :ok = StreamQueue.push(queue, :buffered)
    :ok = StreamQueue.close(queue)
    :ok = StreamQueue.push(queue, :late)

    state = :sys.get_state(queue)
    assert state.closed?

    assert {:ok, :buffered} = StreamQueue.try_pop(queue)
    assert :done = StreamQueue.try_pop(queue)
  end

  defp wait_for_waiter_count(queue, expected) do
    started = System.monotonic_time(:millisecond)
    do_wait_for_waiter_count(queue, expected, started)
  end

  defp do_wait_for_waiter_count(queue, expected, started) do
    if waiter_count(queue) == expected do
      :ok
    else
      if System.monotonic_time(:millisecond) - started > 500 do
        flunk("timed out waiting for waiter count #{expected}")
      else
        Process.sleep(10)
        do_wait_for_waiter_count(queue, expected, started)
      end
    end
  end

  defp waiter_count(queue) do
    state = :sys.get_state(queue)
    :queue.len(state.waiters)
  end
end
