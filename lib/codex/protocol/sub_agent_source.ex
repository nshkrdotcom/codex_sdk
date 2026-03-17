defmodule Codex.Protocol.SubAgentSource do
  @moduledoc """
  Typed representation of sub-agent session source metadata.
  """

  use TypedStruct

  @type variant ::
          :review
          | :compact
          | :memory_consolidation
          | :thread_spawn
          | :other

  typedstruct do
    field(:variant, variant(), enforce: true)
    field(:parent_thread_id, String.t() | nil)
    field(:depth, integer() | nil)
    field(:agent_nickname, String.t() | nil)
    field(:agent_role, String.t() | nil)
    field(:other, String.t() | nil)
  end

  @spec from_map(map() | atom() | String.t() | t() | nil) :: t()
  def from_map(%__MODULE__{} = source), do: source
  def from_map(nil), do: %__MODULE__{variant: :other, other: "unknown"}
  def from_map(value) when is_atom(value), do: value |> Atom.to_string() |> from_map()

  def from_map(value) when is_binary(value) do
    case value do
      "review" ->
        %__MODULE__{variant: :review}

      "compact" ->
        %__MODULE__{variant: :compact}

      "memory_consolidation" ->
        %__MODULE__{variant: :memory_consolidation}

      other ->
        %__MODULE__{variant: :other, other: other}
    end
  end

  def from_map(%{} = value) do
    normalized = normalize_keys(value)

    cond do
      Map.has_key?(normalized, "thread_spawn") ->
        spawn = Map.get(normalized, "thread_spawn") || %{}

        %__MODULE__{
          variant: :thread_spawn,
          parent_thread_id: Map.get(spawn, "parent_thread_id"),
          depth: Map.get(spawn, "depth"),
          agent_nickname: Map.get(spawn, "agent_nickname"),
          agent_role: Map.get(spawn, "agent_role"),
          other: nil
        }

      Map.has_key?(normalized, "other") ->
        %__MODULE__{variant: :other, other: Map.get(normalized, "other")}

      true ->
        %__MODULE__{variant: :other, other: inspect(value)}
    end
  end

  @spec to_map(t()) :: map() | String.t()
  def to_map(%__MODULE__{variant: :review}), do: "review"
  def to_map(%__MODULE__{variant: :compact}), do: "compact"
  def to_map(%__MODULE__{variant: :memory_consolidation}), do: "memory_consolidation"

  def to_map(%__MODULE__{variant: :thread_spawn} = source) do
    %{
      "thread_spawn" =>
        %{
          "parent_thread_id" => source.parent_thread_id,
          "depth" => source.depth
        }
        |> maybe_put("agent_nickname", source.agent_nickname)
        |> maybe_put("agent_role", source.agent_role)
    }
  end

  def to_map(%__MODULE__{variant: :other, other: other}) do
    %{"other" => other || "unknown"}
  end

  defp normalize_keys(%{} = map) do
    map
    |> Enum.map(fn {key, value} ->
      {normalize_key(key), normalize_value(value)}
    end)
    |> Map.new()
  end

  defp normalize_value(%{} = value), do: normalize_keys(value)
  defp normalize_value(value), do: value

  defp normalize_key(key) when is_atom(key), do: key |> Atom.to_string() |> normalize_key()
  defp normalize_key("threadSpawn"), do: "thread_spawn"
  defp normalize_key("parentThreadId"), do: "parent_thread_id"
  defp normalize_key("agentNickname"), do: "agent_nickname"
  defp normalize_key("agentRole"), do: "agent_role"
  defp normalize_key("agentType"), do: "agent_role"
  defp normalize_key("agent_type"), do: "agent_role"
  defp normalize_key(key) when is_binary(key), do: key

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
