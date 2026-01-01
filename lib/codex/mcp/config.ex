defmodule Codex.MCP.Config do
  @moduledoc """
  Helpers for managing MCP server configuration through app-server config APIs.
  """

  alias Codex.AppServer

  @type connection :: AppServer.connection()
  @type server_config :: map()

  @doc """
  Lists configured MCP servers from the app-server config.

  ## Options

    * `:include_layers` - include layered config metadata (passed to `config/read`)
    * `:app_server` - override the module used for config calls (defaults to `Codex.AppServer`)
  """
  @spec list_servers(connection(), keyword()) :: {:ok, map()} | {:error, term()}
  def list_servers(conn, opts \\ []) when is_pid(conn) and is_list(opts) do
    app_server = Keyword.get(opts, :app_server, AppServer)
    read_opts = Keyword.drop(opts, [:app_server])

    with {:ok, %{"config" => config}} <- app_server.config_read(conn, read_opts) do
      {:ok, fetch_servers(config)}
    end
  end

  @doc """
  Adds or replaces an MCP server entry under `mcp_servers.<name>`.

  The `attrs` map should include either a stdio launcher (`command`) or a
  streamable HTTP URL (`url`).
  """
  @spec add_server(connection(), String.t(), map() | keyword(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def add_server(conn, name, attrs, opts \\ [])
      when is_pid(conn) and is_binary(name) and is_list(opts) do
    with {:ok, value} <- normalize_server_value(attrs) do
      app_server = Keyword.get(opts, :app_server, AppServer)
      write_opts = Keyword.drop(opts, [:app_server])
      app_server.config_write(conn, "mcp_servers." <> name, value, write_opts)
    end
  end

  @doc """
  Removes a configured MCP server entry.
  """
  @spec remove_server(connection(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def remove_server(conn, name, opts \\ [])
      when is_pid(conn) and is_binary(name) and is_list(opts) do
    app_server = Keyword.get(opts, :app_server, AppServer)
    write_opts = Keyword.drop(opts, [:app_server])
    app_server.config_write(conn, "mcp_servers." <> name, nil, write_opts)
  end

  defp fetch_servers(%{} = config) do
    servers =
      Map.get(config, "mcp_servers") ||
        Map.get(config, "mcpServers") ||
        Map.get(config, :mcp_servers) ||
        Map.get(config, :mcpServers) ||
        %{}

    normalize_servers(servers)
  end

  defp fetch_servers(_), do: %{}

  defp normalize_servers(%{} = servers), do: stringify_keys(servers)
  defp normalize_servers(_), do: %{}

  defp normalize_server_value(attrs) do
    attrs = normalize_map(attrs)

    if map_size(attrs) == 0 do
      {:error, :missing_server_config}
    else
      config =
        attrs
        |> stringify_keys()
        |> normalize_aliases()
        |> drop_nil_values()

      if Map.has_key?(config, "command") or Map.has_key?(config, "url") do
        {:ok, config}
      else
        {:error, :missing_transport}
      end
    end
  end

  defp normalize_map(nil), do: %{}
  defp normalize_map(%{} = map), do: map
  defp normalize_map(list) when is_list(list), do: Map.new(list)
  defp normalize_map(_), do: %{}

  defp normalize_aliases(%{} = config) do
    config
    |> canonicalize_key("envVars", "env_vars")
    |> canonicalize_key("bearerTokenEnvVar", "bearer_token_env_var")
    |> canonicalize_key("httpHeaders", "http_headers")
    |> canonicalize_key("envHttpHeaders", "env_http_headers")
    |> canonicalize_key("startupTimeoutSec", "startup_timeout_sec")
    |> canonicalize_key("toolTimeoutSec", "tool_timeout_sec")
    |> canonicalize_key("enabledTools", "enabled_tools")
    |> canonicalize_key("disabledTools", "disabled_tools")
  end

  defp canonicalize_key(config, from, to) do
    cond do
      Map.has_key?(config, to) ->
        Map.delete(config, from)

      Map.has_key?(config, from) ->
        config
        |> Map.put(to, Map.get(config, from))
        |> Map.delete(from)

      true ->
        config
    end
  end

  defp drop_nil_values(%{} = map) do
    map
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, val} -> {to_string(key), stringify_keys(val)} end)
  end

  defp stringify_keys(list) when is_list(list), do: Enum.map(list, &stringify_keys/1)
  defp stringify_keys(other), do: other
end
