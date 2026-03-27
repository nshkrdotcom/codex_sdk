defmodule Codex.Schema do
  @moduledoc false

  alias CliSubprocessCore.Schema, as: CoreSchema

  defdelegate parse(schema, value, tag), to: CoreSchema
  defdelegate parse!(schema, value, tag), to: CoreSchema
  defdelegate split_extra(map, keys), to: CoreSchema
  defdelegate merge_extra(projected, extra), to: CoreSchema
  defdelegate to_map(struct, keys), to: CoreSchema

  @spec normalize_input(term(), map()) :: term()
  def normalize_input(value, key_mapping \\ %{}) when is_map(key_mapping) do
    do_normalize_input(value, key_mapping, true)
  end

  @spec put_present(map(), term(), term()) :: map()
  def put_present(map, _key, nil) when is_map(map), do: map
  def put_present(map, key, value) when is_map(map), do: Map.put(map, key, value)

  defp do_normalize_input(nil, _key_mapping, true), do: %{}
  defp do_normalize_input(nil, _key_mapping, false), do: nil

  defp do_normalize_input(list, key_mapping, _top_level?) when is_list(list) do
    if list != [] and Keyword.keyword?(list) do
      list
      |> Enum.into(%{})
      |> do_normalize_input(key_mapping, false)
    else
      Enum.map(list, &do_normalize_input(&1, key_mapping, false))
    end
  end

  defp do_normalize_input(%{} = value, key_mapping, _top_level?) do
    value
    |> Enum.map(fn {key, nested_value} ->
      {normalize_key(key, key_mapping), do_normalize_input(nested_value, key_mapping, false)}
    end)
    |> Map.new()
  end

  defp do_normalize_input(value, _key_mapping, _top_level?), do: value

  defp normalize_key(key, key_mapping) when is_atom(key),
    do: key |> Atom.to_string() |> normalize_key(key_mapping)

  defp normalize_key(key, key_mapping) when is_binary(key), do: Map.get(key_mapping, key, key)
  defp normalize_key(key, _key_mapping), do: key
end
