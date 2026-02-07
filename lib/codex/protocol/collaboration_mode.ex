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
  def from_map(%{"mode" => mode} = data) do
    reasoning_effort = Map.get(data, "reasoning_effort") || Map.get(data, "reasoningEffort")

    developer_instructions =
      Map.get(data, "developer_instructions") || Map.get(data, "developerInstructions")

    %__MODULE__{
      mode: decode_mode(mode),
      model: Map.get(data, "model", ""),
      reasoning_effort: decode_effort(reasoning_effort),
      developer_instructions: developer_instructions
    }
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = cm) do
    %{"mode" => encode_mode(cm.mode), "model" => cm.model}
    |> maybe_put("reasoning_effort", cm.reasoning_effort && Atom.to_string(cm.reasoning_effort))
    |> maybe_put("developer_instructions", cm.developer_instructions)
  end

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

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
