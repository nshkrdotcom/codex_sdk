defmodule Codex.Protocol.SessionSource do
  @moduledoc """
  Typed representation of thread/session source metadata returned by Codex.

  This normalizes both core-session source values such as `"mcp"` and
  app-server v2 values such as `"appServer"` into a single SDK-facing shape.
  """

  use TypedStruct

  alias Codex.Protocol.SubAgentSource

  @type kind :: :cli | :vscode | :exec | :app_server | :sub_agent | :unknown

  @type source_kind ::
          :cli
          | :vscode
          | :exec
          | :app_server
          | :sub_agent
          | :sub_agent_review
          | :sub_agent_compact
          | :sub_agent_thread_spawn
          | :sub_agent_other
          | :unknown

  typedstruct do
    field(:kind, kind(), enforce: true)
    field(:sub_agent, SubAgentSource.t() | nil)
  end

  @spec from_map(map() | atom() | String.t() | t() | nil) :: t()
  def from_map(%__MODULE__{} = source), do: source
  def from_map(nil), do: %__MODULE__{kind: :unknown}
  def from_map(value) when is_atom(value), do: value |> Atom.to_string() |> from_map()

  def from_map(value) when is_binary(value) do
    case normalize_source_kind(value) do
      :cli -> %__MODULE__{kind: :cli}
      :vscode -> %__MODULE__{kind: :vscode}
      :exec -> %__MODULE__{kind: :exec}
      :app_server -> %__MODULE__{kind: :app_server}
      :sub_agent -> %__MODULE__{kind: :sub_agent, sub_agent: %SubAgentSource{variant: :other}}
      _ -> %__MODULE__{kind: :unknown}
    end
  end

  def from_map(%{} = value) do
    normalized = normalize_keys(value)

    if Map.has_key?(normalized, "sub_agent") do
      %__MODULE__{
        kind: :sub_agent,
        sub_agent: normalized |> Map.get("sub_agent") |> SubAgentSource.from_map()
      }
    else
      normalized
      |> Map.get("type")
      |> from_map()
    end
  end

  @spec to_map(t()) :: map() | String.t()
  def to_map(%__MODULE__{kind: :cli}), do: "cli"
  def to_map(%__MODULE__{kind: :vscode}), do: "vscode"
  def to_map(%__MODULE__{kind: :exec}), do: "exec"
  def to_map(%__MODULE__{kind: :app_server}), do: "appServer"
  def to_map(%__MODULE__{kind: :unknown}), do: "unknown"

  def to_map(%__MODULE__{kind: :sub_agent, sub_agent: %SubAgentSource{} = source}) do
    %{"subAgent" => SubAgentSource.to_map(source)}
  end

  def to_map(%__MODULE__{kind: :sub_agent, sub_agent: nil}) do
    %{"subAgent" => %{"other" => "unknown"}}
  end

  @spec source_kind(map() | atom() | String.t() | t() | nil) :: source_kind()
  def source_kind(value) do
    case from_map(value) do
      %__MODULE__{kind: kind} when kind in [:cli, :vscode, :exec, :app_server] ->
        kind

      %__MODULE__{kind: :sub_agent, sub_agent: sub_agent} ->
        sub_agent_source_kind(sub_agent)

      %__MODULE__{} ->
        :unknown
    end
  end

  @spec normalize_source_kind(atom() | String.t() | nil) :: source_kind() | nil
  def normalize_source_kind(nil), do: nil

  def normalize_source_kind(value) when is_atom(value),
    do: normalize_source_kind(Atom.to_string(value))

  def normalize_source_kind("cli"), do: :cli
  def normalize_source_kind("vscode"), do: :vscode
  def normalize_source_kind("vs_code"), do: :vscode
  def normalize_source_kind("exec"), do: :exec
  def normalize_source_kind("mcp"), do: :app_server
  def normalize_source_kind("appServer"), do: :app_server
  def normalize_source_kind("app_server"), do: :app_server
  def normalize_source_kind("subAgent"), do: :sub_agent
  def normalize_source_kind("sub_agent"), do: :sub_agent
  def normalize_source_kind("subAgentReview"), do: :sub_agent_review
  def normalize_source_kind("sub_agent_review"), do: :sub_agent_review
  def normalize_source_kind("subAgentCompact"), do: :sub_agent_compact
  def normalize_source_kind("sub_agent_compact"), do: :sub_agent_compact
  def normalize_source_kind("subAgentThreadSpawn"), do: :sub_agent_thread_spawn
  def normalize_source_kind("sub_agent_thread_spawn"), do: :sub_agent_thread_spawn
  def normalize_source_kind("subAgentOther"), do: :sub_agent_other
  def normalize_source_kind("sub_agent_other"), do: :sub_agent_other
  def normalize_source_kind("unknown"), do: :unknown
  def normalize_source_kind(_), do: :unknown

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
  defp normalize_key("subAgent"), do: "sub_agent"
  defp normalize_key("subagent"), do: "sub_agent"
  defp normalize_key(key) when is_binary(key), do: key

  defp sub_agent_source_kind(%SubAgentSource{variant: :review}), do: :sub_agent_review
  defp sub_agent_source_kind(%SubAgentSource{variant: :compact}), do: :sub_agent_compact
  defp sub_agent_source_kind(%SubAgentSource{variant: :thread_spawn}), do: :sub_agent_thread_spawn
  defp sub_agent_source_kind(%SubAgentSource{variant: :other}), do: :sub_agent_other
  defp sub_agent_source_kind(%SubAgentSource{}), do: :sub_agent
  defp sub_agent_source_kind(_), do: :sub_agent
end
