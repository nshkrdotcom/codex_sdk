defmodule Codex.TestSupport.Env do
  @moduledoc false

  @app :codex_sdk
  @key :env

  def snapshot(keys) when is_list(keys) do
    %{
      system: Map.new(keys, fn key -> {key, System.get_env(key)} end),
      app: Application.get_env(@app, @key, %{})
    }
  end

  def restore(%{system: system, app: app}) do
    Enum.each(system, fn
      {key, nil} -> System.delete_env(key)
      {key, value} -> System.put_env(key, value)
    end)

    Application.put_env(@app, @key, app)
    :ok
  end

  def put(key, value) when is_binary(key) do
    value = to_string(value)
    System.put_env(key, value)
    Application.put_env(@app, @key, Map.put(app_env(), key, value))
  end

  def delete(key) when is_binary(key) do
    System.delete_env(key)
    Application.put_env(@app, @key, Map.delete(app_env(), key))
  end

  def clear(keys) when is_list(keys) do
    Enum.each(keys, &delete/1)
  end

  def merge(values) when is_map(values) do
    Enum.each(values, fn {key, value} -> put(to_string(key), value) end)
  end

  def app_env do
    @app
    |> Application.get_env(@key, %{})
    |> Codex.Env.normalize()
  end
end
