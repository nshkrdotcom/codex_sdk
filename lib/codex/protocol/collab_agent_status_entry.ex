defmodule Codex.Protocol.CollabAgentStatusEntry do
  @moduledoc """
  Typed association between an agent reference and its lifecycle state.
  """

  use TypedStruct

  alias Codex.Protocol.CollabAgentRef
  alias Codex.Protocol.CollabAgentState

  typedstruct do
    field(:thread_id, String.t(), enforce: true)
    field(:agent_nickname, String.t() | nil)
    field(:agent_role, String.t() | nil)
    field(:status, CollabAgentState.t(), enforce: true)
  end

  @spec from_map(map() | t()) :: t()
  def from_map(%__MODULE__{} = entry), do: entry

  def from_map(%{} = value) do
    ref = CollabAgentRef.from_map(value)

    %__MODULE__{
      thread_id: ref.thread_id,
      agent_nickname: ref.agent_nickname,
      agent_role: ref.agent_role,
      status: value |> fetch_status() |> CollabAgentState.from_map()
    }
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = entry) do
    %{
      "thread_id" => entry.thread_id,
      "status" => CollabAgentState.to_event_value(entry.status)
    }
    |> maybe_put("agent_nickname", entry.agent_nickname)
    |> maybe_put("agent_role", entry.agent_role)
  end

  defp fetch_status(%{} = value), do: Map.get(value, "status") || Map.get(value, :status)

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
