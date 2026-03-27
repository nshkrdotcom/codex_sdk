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

  alias CliSubprocessCore.Schema.Conventions
  alias Codex.Schema

  @type mode_kind :: :plan | :pair_programming | :code | :default | :execute | :custom

  @known_fields ["mode", "settings", "model", "reasoning_effort", "developer_instructions"]
  @settings_known_fields ["model", "reasoning_effort", "developer_instructions"]
  @settings_schema Zoi.map(
                     %{
                       "model" => Conventions.optional_trimmed_string(),
                       "reasoning_effort" => Conventions.optional_any(),
                       "developer_instructions" => Conventions.optional_trimmed_string()
                     },
                     unrecognized_keys: :preserve
                   )
  @schema Zoi.map(
            %{
              "mode" => Conventions.optional_any(),
              "settings" => Zoi.default(Zoi.optional(Zoi.nullish(@settings_schema)), %{}),
              "model" => Conventions.optional_trimmed_string(),
              "reasoning_effort" => Conventions.optional_any(),
              "developer_instructions" => Conventions.optional_trimmed_string()
            },
            unrecognized_keys: :preserve
          )

  typedstruct do
    @typedoc "Collaboration mode with settings"
    field(:mode, mode_kind(), enforce: true)
    field(:model, String.t(), enforce: true)
    field(:reasoning_effort, Codex.Models.reasoning_effort() | nil)
    field(:developer_instructions, String.t() | nil)
    field(:extra, map(), default: %{})
  end

  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @spec parse(map() | keyword() | t()) ::
          {:ok, t()}
          | {:error, {:invalid_collaboration_mode, CliSubprocessCore.Schema.error_detail()}}
  def parse(%__MODULE__{} = mode), do: {:ok, mode}
  def parse(data) when is_list(data), do: parse(Enum.into(data, %{}))

  def parse(data) do
    case Schema.parse(@schema, normalize_keys(data), :invalid_collaboration_mode) do
      {:ok, parsed} ->
        {:ok, build_mode(parsed)}

      {:error, {:invalid_collaboration_mode, details}} ->
        {:error, {:invalid_collaboration_mode, details}}
    end
  end

  @spec parse!(map() | keyword() | t()) :: t()
  def parse!(%__MODULE__{} = mode), do: mode
  def parse!(data) when is_list(data), do: parse!(Enum.into(data, %{}))

  def parse!(data) do
    @schema
    |> Schema.parse!(normalize_keys(data), :invalid_collaboration_mode)
    |> build_mode()
  end

  @spec from_map(map()) :: t()
  def from_map(data), do: parse!(data)

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = cm) do
    settings =
      %{
        "model" => cm.model,
        "reasoning_effort" => encode_effort(cm.reasoning_effort),
        "developer_instructions" => cm.developer_instructions
      }
      |> merge_settings_extra(cm.extra)

    %{
      "mode" => encode_mode(cm.mode),
      "settings" => settings
    }
    |> Map.merge(Map.drop(cm.extra, ["settings"]))
  end

  defp build_mode(parsed) do
    settings = Map.get(parsed, "settings", %{})
    {_, top_extra} = Schema.split_extra(parsed, @known_fields)
    settings_extra = Map.drop(settings, @settings_known_fields)
    extra = maybe_put_settings_extra(top_extra, settings_extra)

    %__MODULE__{
      mode: parsed |> Map.get("mode") |> decode_mode(),
      model: fetch_setting(settings, parsed, "model") || "",
      reasoning_effort:
        settings
        |> fetch_setting(parsed, "reasoning_effort")
        |> decode_effort(),
      developer_instructions: fetch_setting(settings, parsed, "developer_instructions"),
      extra: extra
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

  defp decode_effort(_), do: nil

  defp encode_effort(nil), do: nil
  defp encode_effort(value) when is_atom(value), do: Atom.to_string(value)
  defp encode_effort(value), do: value

  defp merge_settings_extra(settings, %{"settings" => extra}) when is_map(extra),
    do: Map.merge(settings, extra)

  defp merge_settings_extra(settings, _extra), do: settings

  defp maybe_put_settings_extra(extra, settings_extra) when map_size(settings_extra) == 0,
    do: extra

  defp maybe_put_settings_extra(extra, settings_extra),
    do: Map.put(extra, "settings", settings_extra)

  defp fetch_setting(%{} = settings, %{} = normalized, key) when is_binary(key) do
    if Map.has_key?(settings, key) do
      Map.get(settings, key)
    else
      Map.get(normalized, key)
    end
  end

  defp normalize_keys(%{} = data) do
    data
    |> Enum.map(fn {key, value} ->
      {normalize_key(key), normalize_nested_value(value)}
    end)
    |> Map.new()
  end

  defp normalize_keys(other), do: other

  defp normalize_nested_value(%{} = value), do: normalize_keys(value)

  defp normalize_nested_value(value) when is_list(value),
    do: Enum.map(value, &normalize_nested_value/1)

  defp normalize_nested_value(value), do: value

  defp normalize_key(key) when is_atom(key), do: key |> Atom.to_string() |> normalize_key()
  defp normalize_key("reasoningEffort"), do: "reasoning_effort"
  defp normalize_key("developerInstructions"), do: "developer_instructions"
  defp normalize_key(key) when is_binary(key), do: key
end
