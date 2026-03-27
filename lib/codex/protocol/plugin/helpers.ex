defmodule Codex.Protocol.Plugin.Helpers do
  @moduledoc false

  alias CliSubprocessCore.Schema.Conventions
  alias CliSubprocessCore.Schema.Error, as: SchemaError
  alias Codex.Schema

  @spec required_string() :: Zoi.schema()
  def required_string do
    Conventions.trimmed_string()
    |> Zoi.min(1)
  end

  @spec optional_string() :: Zoi.schema()
  def optional_string, do: Conventions.optional_trimmed_string()

  @spec any_map() :: Zoi.schema()
  def any_map, do: Conventions.any_map()

  @spec optional_map() :: Zoi.schema()
  def optional_map, do: Zoi.optional(Zoi.nullish(any_map()))

  @spec default_array(Zoi.schema(), list()) :: Zoi.schema()
  def default_array(schema, default \\ []) when is_list(default) do
    Zoi.default(Zoi.optional(Zoi.nullish(Zoi.array(schema))), default)
  end

  @spec default_string_list([String.t()]) :: Zoi.schema()
  def default_string_list(default \\ []) when is_list(default) do
    Zoi.default(Zoi.optional(Zoi.nullish(Zoi.array(required_string()))), default)
  end

  @spec boolean_flag() :: Zoi.schema()
  def boolean_flag do
    Zoi.default(
      Zoi.optional(
        Zoi.nullish(Zoi.any() |> Zoi.transform({__MODULE__, :normalize_boolean_flag, []}))
      ),
      false
    )
  end

  @spec normalize_boolean_flag(term(), keyword()) :: {:ok, boolean()} | {:error, String.t()}
  def normalize_boolean_flag(true, _opts), do: {:ok, true}
  def normalize_boolean_flag(false, _opts), do: {:ok, false}
  def normalize_boolean_flag("true", _opts), do: {:ok, true}
  def normalize_boolean_flag("false", _opts), do: {:ok, false}

  def normalize_boolean_flag(value, _opts) when is_atom(value),
    do: normalize_boolean_flag(Atom.to_string(value), [])

  def normalize_boolean_flag(_value, _opts), do: {:error, "expected a boolean"}

  @spec raw_true?(term()) :: boolean()
  def raw_true?(true), do: true
  def raw_true?("true"), do: true
  def raw_true?(_), do: false

  @spec parse(Zoi.schema(), term(), atom(), map(), (map() -> struct())) ::
          {:ok, struct()} | {:error, {atom(), CliSubprocessCore.Schema.error_detail()}}
  def parse(schema, value, tag, key_mapping, projector) when is_function(projector, 1) do
    case Schema.parse(schema, normalize_input(value, key_mapping), tag) do
      {:ok, parsed} ->
        try do
          {:ok, projector.(parsed)}
        rescue
          error in [SchemaError] ->
            {:error, {tag, error.details}}
        end

      {:error, {^tag, details}} ->
        {:error, {tag, details}}
    end
  end

  @spec parse!(Zoi.schema(), term(), atom(), map(), (map() -> struct())) :: struct()
  def parse!(schema, value, tag, key_mapping, projector) when is_function(projector, 1) do
    schema
    |> Schema.parse!(normalize_input(value, key_mapping), tag)
    |> projector.()
  rescue
    error in [SchemaError] ->
      reraise SchemaError, [tag: tag, details: error.details], __STACKTRACE__
  end

  @spec split_extra(map(), [String.t()]) :: {map(), map()}
  def split_extra(parsed, known_fields), do: Schema.split_extra(parsed, known_fields)

  @spec parse_nested(term(), module()) :: struct() | nil
  def parse_nested(nil, _module), do: nil

  def parse_nested(%module{} = value, module), do: value

  def parse_nested(value, module) do
    module.parse!(value)
  end

  @spec parse_list([term()] | nil, module()) :: [struct()]
  def parse_list(nil, _module), do: []

  def parse_list(values, module) when is_list(values),
    do: Enum.map(values, &parse_nested(&1, module))

  @spec encode_nested(term(), module()) :: map() | nil
  def encode_nested(nil, _module), do: nil

  def encode_nested(%module{} = value, module), do: module.to_map(value)

  def encode_nested(value, _module) when is_map(value), do: value

  @spec encode_list([term()], module()) :: [map()]
  def encode_list(values, module) when is_list(values) do
    Enum.map(values, &encode_nested(&1, module))
  end

  @spec maybe_put(map(), String.t(), term()) :: map()
  def maybe_put(map, _key, nil), do: map
  def maybe_put(map, key, value), do: Map.put(map, key, value)

  @spec normalize_input(term(), map()) :: term()
  def normalize_input(nil, _key_mapping), do: %{}

  def normalize_input(list, key_mapping) when is_list(list),
    do: list |> Enum.into(%{}) |> normalize_input(key_mapping)

  def normalize_input(%{} = value, key_mapping) when is_map(key_mapping) do
    value
    |> Enum.map(fn {key, nested_value} ->
      {normalize_key(key, key_mapping), normalize_value(nested_value, key_mapping)}
    end)
    |> Map.new()
  end

  def normalize_input(value, _key_mapping), do: value

  defp normalize_value(%{} = value, key_mapping), do: normalize_input(value, key_mapping)

  defp normalize_value(values, key_mapping) when is_list(values) do
    Enum.map(values, &normalize_value(&1, key_mapping))
  end

  defp normalize_value(value, _key_mapping), do: value

  defp normalize_key(key, key_mapping) when is_atom(key) do
    key
    |> Atom.to_string()
    |> normalize_key(key_mapping)
  end

  defp normalize_key(key, key_mapping) when is_binary(key), do: Map.get(key_mapping, key, key)
end
