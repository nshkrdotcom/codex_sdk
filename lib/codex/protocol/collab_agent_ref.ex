defmodule Codex.Protocol.CollabAgentRef do
  @moduledoc """
  Typed reference to a collaboration agent thread.
  """

  use TypedStruct

  typedstruct do
    field(:thread_id, String.t(), enforce: true)
    field(:agent_nickname, String.t() | nil)
    field(:agent_role, String.t() | nil)
  end

  @spec from_map(map() | t()) :: t()
  def from_map(%__MODULE__{} = ref), do: ref

  def from_map(%{} = value) do
    normalized = normalize_keys(value)

    %__MODULE__{
      thread_id: Map.get(normalized, "thread_id") || "",
      agent_nickname: Map.get(normalized, "agent_nickname"),
      agent_role: Map.get(normalized, "agent_role")
    }
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = ref) do
    %{"thread_id" => ref.thread_id}
    |> maybe_put("agent_nickname", ref.agent_nickname)
    |> maybe_put("agent_role", ref.agent_role)
  end

  defp normalize_keys(%{} = map) do
    map
    |> Enum.map(fn {key, value} ->
      {normalize_key(key), value}
    end)
    |> Map.new()
  end

  defp normalize_key(key) when is_atom(key), do: key |> Atom.to_string() |> normalize_key()
  defp normalize_key("threadId"), do: "thread_id"
  defp normalize_key("agentNickname"), do: "agent_nickname"
  defp normalize_key("agentRole"), do: "agent_role"
  defp normalize_key("agentType"), do: "agent_role"
  defp normalize_key(key) when is_binary(key), do: key

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
