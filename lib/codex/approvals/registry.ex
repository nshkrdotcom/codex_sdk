defmodule Codex.Approvals.Registry do
  @moduledoc """
  ETS-based registry for tracking async approval requests.

  This module maintains state for pending approval requests that are awaiting
  decisions from external systems (e.g., Slack, Jira, custom webhooks).
  """

  use GenServer

  @table_name :codex_approval_registry

  @doc """
  Starts the approval registry.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Registers a new async approval request.
  """
  @spec register(reference(), map()) :: :ok
  def register(ref, metadata) when is_reference(ref) and is_map(metadata) do
    GenServer.call(__MODULE__, {:register, ref, metadata})
  end

  @doc """
  Looks up an approval request by reference.
  """
  @spec lookup(reference()) :: {:ok, map()} | {:error, :not_found}
  def lookup(ref) when is_reference(ref) do
    case :ets.lookup(@table_name, ref) do
      [{^ref, metadata}] -> {:ok, metadata}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Deletes an approval request from the registry.
  """
  @spec delete(reference()) :: :ok
  def delete(ref) when is_reference(ref) do
    GenServer.call(__MODULE__, {:delete, ref})
  end

  @doc """
  Cleans up expired approval requests.
  """
  @spec cleanup_expired(pos_integer()) :: non_neg_integer()
  def cleanup_expired(max_age_ms) do
    GenServer.call(__MODULE__, {:cleanup_expired, max_age_ms})
  end

  ## Callbacks

  @impl true
  def init(_opts) do
    table =
      :ets.new(@table_name, [
        :named_table,
        :set,
        :protected,
        read_concurrency: true,
        write_concurrency: true
      ])

    {:ok, %{table: table}}
  end

  @impl true
  def handle_call({:register, ref, metadata}, _from, state) do
    timestamp = System.system_time(:millisecond)
    entry = Map.put(metadata, :registered_at, timestamp)
    :ets.insert(@table_name, {ref, entry})
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:delete, ref}, _from, state) do
    :ets.delete(@table_name, ref)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:cleanup_expired, max_age_ms}, _from, state) do
    now = System.system_time(:millisecond)
    cutoff = now - max_age_ms

    deleted_count =
      :ets.select_delete(@table_name, [
        {
          {:"$1", :"$2"},
          [
            {:is_map, :"$2"},
            {:is_map_key, :registered_at, :"$2"},
            {:<, {:map_get, :registered_at, :"$2"}, cutoff}
          ],
          [true]
        }
      ])

    {:reply, deleted_count, state}
  end
end
