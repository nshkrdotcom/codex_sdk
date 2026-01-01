defmodule Codex.Skills do
  @moduledoc """
  Helpers for discovering and loading Codex skills.

  Skill discovery is gated by the `features.skills` flag in configuration.
  """

  alias Codex.AppServer
  alias Codex.Auth
  alias Codex.Config.LayerStack

  @type connection :: AppServer.connection()

  @doc """
  Lists skills through the app-server when `features.skills` is enabled.

  Returns `{:error, :skills_disabled}` when the feature flag is off.

  ## Options

    * `:cwds` - working directories to scan (forwarded to `skills/list`)
    * `:force_reload` - bypass skill cache (forwarded to `skills/list`)
    * `:skills_enabled` - override feature flag gate
    * `:config` - config map override used for gating
    * `:codex_home` - override CODEX_HOME lookup for gating
    * `:cwd` - override cwd lookup for gating
    * `:app_server` - override module used for app-server calls
  """
  @spec list(connection(), keyword()) :: {:ok, map()} | {:error, term()}
  def list(conn, opts \\ []) when is_pid(conn) and is_list(opts) do
    if skills_enabled?(opts) do
      app_server = Keyword.get(opts, :app_server, AppServer)

      call_opts =
        opts
        |> Keyword.drop([:skills_enabled, :config, :codex_home, :cwd, :app_server])

      app_server.skills_list(conn, call_opts)
    else
      {:error, :skills_disabled}
    end
  end

  @doc """
  Loads the content of a skill file when `features.skills` is enabled.

  Accepts either a skill metadata map (containing `path`) or a direct path.
  """
  @spec load(map() | String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def load(skill_or_path, opts \\ []) when is_list(opts) do
    if skills_enabled?(opts) do
      case extract_path(skill_or_path) do
        nil -> {:error, :missing_path}
        path -> File.read(path)
      end
    else
      {:error, :skills_disabled}
    end
  end

  defp extract_path(%{"path" => path}) when is_binary(path), do: path
  defp extract_path(%{path: path}) when is_binary(path), do: path
  defp extract_path(path) when is_binary(path), do: path
  defp extract_path(_), do: nil

  defp skills_enabled?(opts) do
    case Keyword.fetch(opts, :skills_enabled) do
      {:ok, value} ->
        value == true

      :error ->
        config =
          Keyword.get(opts, :config) ||
            load_config(Keyword.get(opts, :codex_home), Keyword.get(opts, :cwd))

        fetch_feature(config, "skills") == true
    end
  end

  defp load_config(codex_home, cwd) do
    codex_home = codex_home || Auth.codex_home()
    cwd = cwd || current_cwd()

    case LayerStack.load(codex_home, cwd) do
      {:ok, layers} -> LayerStack.effective_config(layers)
      {:error, _} -> %{}
    end
  end

  defp fetch_feature(%{} = config, key) do
    features =
      Map.get(config, "features") ||
        Map.get(config, :features)

    fetch_feature_value(features, key)
  end

  defp fetch_feature(_config, _key), do: nil

  defp fetch_feature_value(nil, _key), do: nil

  defp fetch_feature_value(%{} = features, "skills") do
    Map.get(features, "skills") || Map.get(features, :skills)
  end

  defp fetch_feature_value(%{} = features, key), do: Map.get(features, key)

  defp fetch_feature_value(_features, _key), do: nil

  defp current_cwd do
    case File.cwd() do
      {:ok, cwd} -> cwd
      _ -> nil
    end
  end
end
