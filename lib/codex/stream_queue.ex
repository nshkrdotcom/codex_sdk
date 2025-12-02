defmodule Codex.StreamQueue do
  @moduledoc false

  use GenServer

  @type t :: pid()

  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  @spec push(t(), term()) :: :ok
  def push(queue, value) when is_pid(queue) do
    GenServer.cast(queue, {:push, value})
  end

  @spec close(t()) :: :ok
  def close(queue) when is_pid(queue) do
    GenServer.cast(queue, :close)
  end

  @spec pop(t(), timeout()) :: {:ok, term()} | :done
  def pop(queue, timeout \\ 5_000) when is_pid(queue) do
    GenServer.call(queue, :pop, timeout)
  end

  @spec stream(t()) :: Enumerable.t()
  def stream(queue) when is_pid(queue) do
    Stream.resource(
      fn -> queue end,
      fn q ->
        case pop(q, :infinity) do
          {:ok, value} -> {[value], q}
          :done -> {:halt, q}
        end
      end,
      fn _ -> :ok end
    )
  end

  @impl true
  def init(:ok) do
    {:ok, %{queue: :queue.new(), closed?: false, waiters: :queue.new()}}
  end

  @impl true
  def handle_cast({:push, value}, %{queue: queue, closed?: closed?, waiters: waiters} = state) do
    case :queue.out(waiters) do
      {{:value, from}, remaining} ->
        GenServer.reply(from, {:ok, value})
        {:noreply, %{state | waiters: remaining}}

      {:empty, _} ->
        {:noreply, %{state | queue: :queue.in(value, queue), closed?: closed?}}
    end
  end

  def handle_cast(:close, %{closed?: true} = state), do: {:noreply, state}

  def handle_cast(:close, %{queue: queue, waiters: waiters} = state) do
    Enum.each(:queue.to_list(waiters), &GenServer.reply(&1, :done))
    {:noreply, %{state | closed?: true, waiters: :queue.new(), queue: queue}}
  end

  @impl true
  def handle_call(:pop, from, %{queue: queue, closed?: closed?, waiters: waiters} = state) do
    case :queue.out(queue) do
      {{:value, value}, remaining} ->
        {:reply, {:ok, value}, %{state | queue: remaining}}

      {:empty, _} ->
        if closed? do
          {:reply, :done, state}
        else
          {:noreply, %{state | waiters: :queue.in(from, waiters)}}
        end
    end
  end
end
