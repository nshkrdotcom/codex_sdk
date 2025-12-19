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

  @spec close(t(), term()) :: :ok
  def close(queue, reason \\ :normal) when is_pid(queue) do
    GenServer.cast(queue, {:close, reason})
  end

  @spec pop(t(), timeout()) :: {:ok, term()} | {:error, term()} | :done
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
          {:error, reason} when is_exception(reason) -> raise reason
          {:error, reason} -> raise RuntimeError, "stream closed with error: #{inspect(reason)}"
        end
      end,
      fn _ -> :ok end
    )
  end

  @impl true
  def init(:ok) do
    {:ok, %{queue: :queue.new(), closed?: false, waiters: :queue.new(), error: nil}}
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

  def handle_cast({:close, _reason}, %{closed?: true} = state), do: {:noreply, state}

  def handle_cast({:close, reason}, %{queue: queue, waiters: waiters} = state) do
    error = close_error(reason)
    reply = if error, do: {:error, error}, else: :done

    Enum.each(:queue.to_list(waiters), &GenServer.reply(&1, reply))
    {:noreply, %{state | closed?: true, waiters: :queue.new(), queue: queue, error: error}}
  end

  @impl true
  def handle_call(:pop, _from, %{queue: queue, closed?: true, error: error} = state) do
    reply =
      case error do
        nil -> :done
        reason -> {:error, reason}
      end

    case :queue.out(queue) do
      {{:value, value}, remaining} ->
        {:reply, {:ok, value}, %{state | queue: remaining}}

      {:empty, _} ->
        {:reply, reply, state}
    end
  end

  def handle_call(:pop, from, %{queue: queue, closed?: false, waiters: waiters} = state) do
    case :queue.out(queue) do
      {{:value, value}, remaining} ->
        {:reply, {:ok, value}, %{state | queue: remaining}}

      {:empty, _} ->
        {:noreply, %{state | waiters: :queue.in(from, waiters)}}
    end
  end

  defp close_error({:error, reason}), do: reason
  defp close_error(_), do: nil
end
