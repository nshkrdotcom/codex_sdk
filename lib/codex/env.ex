defmodule Codex.Env do
  @moduledoc false

  @app :codex_sdk

  @spec all(map() | keyword()) :: %{optional(String.t()) => String.t()}
  def all(overrides \\ %{}) do
    configured_env()
    |> Map.merge(normalize(overrides))
  end

  @spec get(String.t(), map() | keyword() | nil) :: String.t() | nil
  def get(key, env \\ nil)
  def get(key, nil) when is_binary(key), do: Map.get(all(), key)
  def get(key, env) when is_binary(key), do: env |> normalize() |> Map.get(key)

  @spec present?(String.t(), map() | keyword() | nil) :: boolean()
  def present?(key, env \\ nil) when is_binary(key) do
    case get(key, env) do
      value when is_binary(value) and value != "" -> true
      _other -> false
    end
  end

  @spec configured_env() :: %{optional(String.t()) => String.t()}
  def configured_env do
    @app
    |> Application.get_env(:env, %{})
    |> normalize()
  end

  @spec normalize(map() | keyword() | nil) :: %{optional(String.t()) => String.t()}
  def normalize(env) when is_map(env) do
    env
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new(fn {key, value} -> {to_string(key), to_string(value)} end)
  end

  def normalize(env) when is_list(env) do
    env
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new(fn {key, value} -> {to_string(key), to_string(value)} end)
  end

  def normalize(_env), do: %{}
end
