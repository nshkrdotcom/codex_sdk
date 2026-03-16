defmodule Codex.Protocol.CollaborationMode do
  @moduledoc """
  Collaboration mode configuration with presets.

  Collaboration modes define different interaction styles with the model:
  - `:plan` - planning mode with high reasoning
  - `:pair_programming` - interactive coding with medium reasoning
  - `:code` - coding-focused preset
  - `:default` - runtime default collaboration preset
  - `:execute` - execution mode with high reasoning
  - `:custom` - custom configuration
  """

  use TypedStruct

  @type mode_kind :: :plan | :pair_programming | :code | :default | :execute | :custom

  typedstruct do
    @typedoc "Collaboration mode with settings"
    field(:mode, mode_kind(), enforce: true)
    field(:model, String.t(), enforce: true)
    field(:reasoning_effort, Codex.Models.reasoning_effort() | nil)
    field(:developer_instructions, String.t() | nil)
  end

  @spec from_map(map()) :: t()
  def from_map(data) when is_list(data), do: data |> Map.new() |> from_map()

  def from_map(%{} = data) do
    normalized = normalize_keys(data)
    settings = normalized |> Map.get("settings", %{}) |> normalize_settings()

    %__MODULE__{
      mode: normalized |> Map.get("mode") |> decode_mode(),
      model: Map.get(settings, "model") || Map.get(normalized, "model", ""),
      reasoning_effort:
        settings
        |> Map.get("reasoning_effort", Map.get(normalized, "reasoning_effort"))
        |> decode_effort(),
      developer_instructions:
        Map.get(settings, "developer_instructions") ||
          Map.get(normalized, "developer_instructions")
    }
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = cm) do
    %{
      "mode" => encode_mode(cm.mode),
      "settings" => %{
        "model" => cm.model,
        "reasoning_effort" => encode_effort(cm.reasoning_effort),
        "developer_instructions" => cm.developer_instructions
      }
    }
  end

  defp decode_mode(mode) when is_atom(mode), do: decode_mode(Atom.to_string(mode))

  defp decode_mode("plan"), do: :plan
  defp decode_mode("pair_programming"), do: :pair_programming
  defp decode_mode("pairprogramming"), do: :pair_programming
  defp decode_mode("pair-programming"), do: :pair_programming
  defp decode_mode("code"), do: :code
  defp decode_mode("default"), do: :default
  defp decode_mode("execute"), do: :execute
  defp decode_mode("custom"), do: :custom
  defp decode_mode(_), do: :custom

  defp encode_mode(:plan), do: "plan"
  # Canonical app-server wire value expected by current Codex builds.
  defp encode_mode(:pair_programming), do: "pair_programming"
  defp encode_mode(:code), do: "code"
  defp encode_mode(:default), do: "default"
  defp encode_mode(:execute), do: "execute"
  defp encode_mode(:custom), do: "custom"

  defp decode_effort(nil), do: nil
  defp decode_effort(s) when is_atom(s), do: decode_effort(Atom.to_string(s))

  defp decode_effort(s) when is_binary(s) do
    case Codex.Models.normalize_reasoning_effort(s) do
      {:ok, effort} -> effort
      _ -> nil
    end
  end

  defp encode_effort(nil), do: nil
  defp encode_effort(value) when is_atom(value), do: Atom.to_string(value)
  defp encode_effort(value), do: value

  defp normalize_settings(%{} = settings), do: normalize_keys(settings)
  defp normalize_settings(_), do: %{}

  defp normalize_keys(%{} = data) do
    data
    |> Enum.map(fn {key, value} ->
      {normalize_key(key), normalize_nested_value(value)}
    end)
    |> Map.new()
  end

  defp normalize_nested_value(%{} = value), do: normalize_keys(value)

  defp normalize_nested_value(value) when is_list(value),
    do: Enum.map(value, &normalize_nested_value/1)

  defp normalize_nested_value(value), do: value

  defp normalize_key(key) when is_atom(key), do: key |> Atom.to_string() |> normalize_key()
  defp normalize_key("reasoningEffort"), do: "reasoning_effort"
  defp normalize_key("developerInstructions"), do: "developer_instructions"
  defp normalize_key(key) when is_binary(key), do: key
end
