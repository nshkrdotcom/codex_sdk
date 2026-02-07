defmodule Codex.Runtime.Env do
  @moduledoc """
  Subprocess environment construction (originator override, API key forwarding).
  """

  alias Codex.Config.BaseURL

  @originator_env "CODEX_INTERNAL_ORIGINATOR_OVERRIDE"
  @sdk_originator "codex_sdk_elixir"

  @spec base_overrides(String.t() | nil, String.t() | nil) :: map()
  def base_overrides(api_key, base_url) do
    %{}
    |> maybe_put("CODEX_API_KEY", api_key)
    |> maybe_put("OPENAI_API_KEY", api_key)
    |> maybe_put_openai_base_url(base_url)
    |> Map.put_new(@originator_env, @sdk_originator)
  end

  @spec to_charlist_env(map()) :: [{String.t(), String.t()}]
  def to_charlist_env(env) when is_map(env) do
    Enum.map(env, fn {key, value} -> {to_string(key), to_string(value)} end)
  end

  @spec maybe_put(map(), String.t(), String.t() | nil) :: map()
  def maybe_put(env, _key, nil), do: env
  def maybe_put(env, _key, ""), do: env
  def maybe_put(env, key, value), do: Map.put(env, key, to_string(value))

  @spec maybe_put_openai_base_url(map(), String.t() | nil) :: map()
  def maybe_put_openai_base_url(env, base_url) do
    default_base_url = BaseURL.default()

    case normalize(base_url) do
      nil -> env
      url when url == default_base_url -> env
      url -> Map.put(env, "OPENAI_BASE_URL", url)
    end
  end

  defp normalize(nil), do: nil

  defp normalize(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp normalize(value), do: to_string(value)
end
