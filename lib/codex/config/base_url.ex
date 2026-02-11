defmodule Codex.Config.BaseURL do
  @moduledoc """
  Base URL resolution with option → env → default precedence.
  """

  alias Codex.Config.Defaults

  @default_base_url Defaults.openai_api_base_url()

  @spec default() :: String.t()
  def default, do: @default_base_url

  @spec resolve(map() | keyword() | nil) :: String.t()
  def resolve(attrs \\ nil) do
    attrs = normalize_attrs(attrs)

    attrs
    |> explicit_base_url()
    |> normalize_url()
    |> case do
      nil ->
        System.get_env("OPENAI_BASE_URL")
        |> normalize_url()
        |> case do
          nil -> @default_base_url
          value -> value
        end

      value ->
        value
    end
  end

  defp explicit_base_url(attrs) do
    fetch_first(attrs, [:base_url, "base_url"])
  end

  defp fetch_first(attrs, [key | rest]) do
    case Map.get(attrs, key) do
      nil -> fetch_first(attrs, rest)
      value -> value
    end
  end

  defp fetch_first(_attrs, []), do: nil

  defp normalize_attrs(nil), do: %{}
  defp normalize_attrs(attrs) when is_list(attrs), do: Map.new(attrs)
  defp normalize_attrs(attrs) when is_map(attrs), do: attrs
  defp normalize_attrs(_attrs), do: %{}

  defp normalize_url(nil), do: nil

  defp normalize_url(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp normalize_url(_), do: nil
end
