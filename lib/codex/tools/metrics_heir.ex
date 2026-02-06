defmodule Codex.Tools.MetricsHeir do
  @moduledoc false

  use GenServer

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))
  end

  @impl true
  def init(:ok), do: {:ok, %{}}

  @impl true
  def handle_info({:"ETS-TRANSFER", _table, _from, _meta}, state) do
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}
end
