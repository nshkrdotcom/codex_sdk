defmodule Codex.Exec.CancellationRegistry do
  @moduledoc false

  use GenServer

  @name __MODULE__
  @table :codex_exec_cancellation_tokens

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, @name))
  end

  @spec register(String.t(), pid()) :: :ok
  def register(token, transport) when is_binary(token) and token != "" and is_pid(transport) do
    call_registry({:register, token, transport}, :ok)
  end

  def register(_token, _transport), do: :ok

  @spec unregister(String.t(), pid() | nil) :: :ok
  def unregister(token, transport \\ nil)

  def unregister(token, transport)
      when is_binary(token) and token != "" and (is_nil(transport) or is_pid(transport)) do
    call_registry({:unregister, token, transport}, :ok)
  end

  def unregister(_token, _transport), do: :ok

  @spec transports_for_token(String.t()) :: [pid()]
  def transports_for_token(token) when is_binary(token) and token != "" do
    call_registry({:transports_for_token, token}, [])
  end

  def transports_for_token(_token), do: []

  @impl true
  def init(:ok) do
    table =
      :ets.new(@table, [
        :named_table,
        :protected,
        :bag,
        {:read_concurrency, true},
        {:write_concurrency, true}
      ])

    {:ok, %{table: table, monitors: %{}}}
  end

  @impl true
  def handle_call({:register, token, transport}, _from, state) do
    true = :ets.insert(state.table, {token, transport})
    {:reply, :ok, ensure_monitor(state, transport)}
  end

  def handle_call({:unregister, token, transport}, _from, state) do
    {transports, state} =
      if is_pid(transport) do
        :ets.delete_object(state.table, {token, transport})
        {[transport], maybe_drop_monitor(state, transport)}
      else
        transports = lookup_transports(state.table, token)

        Enum.each(transports, fn pid ->
          :ets.delete_object(state.table, {token, pid})
        end)

        {transports, Enum.reduce(transports, state, &maybe_drop_monitor(&2, &1))}
      end

    _ = transports
    {:reply, :ok, state}
  end

  def handle_call({:transports_for_token, token}, _from, state) do
    {alive, state} =
      Enum.reduce(:ets.lookup(state.table, token), {MapSet.new(), state}, fn
        {^token, transport}, {acc, state} when is_pid(transport) ->
          if Process.alive?(transport) do
            {MapSet.put(acc, transport), state}
          else
            :ets.delete_object(state.table, {token, transport})
            {acc, maybe_drop_monitor(state, transport)}
          end

        _entry, acc ->
          acc
      end)

    {:reply, MapSet.to_list(alive), state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, transport, _reason}, state) do
    state =
      case Map.get(state.monitors, transport) do
        ^ref ->
          Process.demonitor(ref, [:flush])
          %{state | monitors: Map.delete(state.monitors, transport)}

        _other ->
          state
      end

    :ets.match_delete(state.table, {:_, transport})
    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp lookup_transports(table, token) do
    table
    |> :ets.lookup(token)
    |> Enum.reduce([], fn
      {^token, transport}, acc when is_pid(transport) -> [transport | acc]
      _entry, acc -> acc
    end)
    |> Enum.uniq()
  end

  defp ensure_monitor(state, transport) do
    case Map.has_key?(state.monitors, transport) do
      true ->
        state

      false ->
        ref = Process.monitor(transport)
        %{state | monitors: Map.put(state.monitors, transport, ref)}
    end
  end

  defp maybe_drop_monitor(state, transport) do
    case has_transport_entries?(state.table, transport) do
      true ->
        state

      false ->
        case Map.pop(state.monitors, transport) do
          {nil, _monitors} ->
            state

          {ref, monitors} ->
            Process.demonitor(ref, [:flush])
            %{state | monitors: monitors}
        end
    end
  end

  defp has_transport_entries?(table, transport) do
    match_spec = [{{:_, transport}, [], [true]}]
    :ets.select_count(table, match_spec) > 0
  end

  defp call_registry(message, fallback) do
    case Process.whereis(@name) do
      nil ->
        fallback

      _pid ->
        GenServer.call(@name, message)
    end
  catch
    :exit, _reason -> fallback
  end
end
