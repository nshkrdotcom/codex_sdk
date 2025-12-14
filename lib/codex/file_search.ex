defmodule Codex.FileSearch do
  @moduledoc """
  Configuration for file search capabilities in threads and runs.

  File search allows agents to search through uploaded files using vector stores.
  """

  @enforce_keys []
  defstruct vector_store_ids: nil,
            filters: nil,
            ranking_options: nil,
            include_search_results: nil

  @type t :: %__MODULE__{
          vector_store_ids: [String.t()] | nil,
          filters: map() | nil,
          ranking_options: map() | nil,
          include_search_results: boolean() | nil
        }

  @spec new(map() | keyword() | t() | nil) :: {:ok, t() | nil} | {:error, term()}
  def new(nil), do: {:ok, nil}
  def new(%__MODULE__{} = config), do: {:ok, config}
  def new(attrs) when is_list(attrs), do: attrs |> Map.new() |> new()

  def new(attrs) when is_map(attrs) do
    vector_store_ids =
      Map.get(attrs, :vector_store_ids, Map.get(attrs, "vector_store_ids"))

    filters = Map.get(attrs, :filters, Map.get(attrs, "filters"))

    ranking_options =
      Map.get(attrs, :ranking_options, Map.get(attrs, "ranking_options"))

    include_search_results =
      Map.get(attrs, :include_search_results, Map.get(attrs, "include_search_results"))

    with {:ok, vector_store_ids} <- normalize_vector_store_ids(vector_store_ids),
         {:ok, filters} <- normalize_map(filters, :filters),
         {:ok, ranking_options} <- normalize_map(ranking_options, :ranking_options),
         :ok <- validate_boolean(include_search_results, :include_search_results) do
      {:ok,
       %__MODULE__{
         vector_store_ids: vector_store_ids,
         filters: filters,
         ranking_options: ranking_options,
         include_search_results: include_search_results
       }}
    else
      {:error, _} = error -> error
    end
  end

  defp normalize_vector_store_ids(nil), do: {:ok, nil}
  defp normalize_vector_store_ids([]), do: {:ok, []}

  defp normalize_vector_store_ids(ids) when is_list(ids) do
    normalized =
      Enum.map(ids, fn
        value when is_binary(value) -> value
        value when is_atom(value) -> Atom.to_string(value)
        value -> to_string(value)
      end)

    {:ok, normalized}
  end

  defp normalize_vector_store_ids(value), do: {:error, {:invalid_vector_store_ids, value}}

  defp normalize_map(nil, _field), do: {:ok, nil}
  defp normalize_map(map, _field) when is_map(map), do: {:ok, map}
  defp normalize_map(value, field), do: {:error, {:"invalid_#{field}", value}}

  defp validate_boolean(nil, _field), do: :ok
  defp validate_boolean(value, _field) when is_boolean(value), do: :ok
  defp validate_boolean(value, field), do: {:error, {:"invalid_#{field}", value}}

  @spec merge(t() | nil, t() | nil) :: t() | nil
  def merge(nil, nil), do: nil
  def merge(%__MODULE__{} = left, nil), do: left
  def merge(nil, %__MODULE__{} = right), do: right

  def merge(%__MODULE__{} = left, %__MODULE__{} = right) do
    %__MODULE__{
      vector_store_ids: coalesce(right.vector_store_ids, left.vector_store_ids),
      filters: merge_maps(left.filters, right.filters),
      ranking_options: merge_maps(left.ranking_options, right.ranking_options),
      include_search_results: coalesce(right.include_search_results, left.include_search_results)
    }
  end

  defp coalesce(nil, fallback), do: fallback
  defp coalesce(value, _fallback), do: value

  defp merge_maps(nil, map), do: map
  defp merge_maps(map, nil), do: map

  defp merge_maps(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn _key, _l, r -> r end)
  end

  defp merge_maps(_left, right), do: right
end
