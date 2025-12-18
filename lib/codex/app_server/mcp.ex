defmodule Codex.AppServer.Mcp do
  @moduledoc """
  MCP (Model Context Protocol) server management for app-server connections.

  This module provides functions to interact with MCP servers configured in
  the Codex app-server, including listing server status and handling OAuth
  authentication flows.
  """

  alias Codex.AppServer.Connection
  alias Codex.AppServer.Params

  @type connection :: pid()

  @doc """
  Lists configured MCP servers with their tools, resources, and auth status.

  Supports cursor-based pagination via `:cursor` and `:limit` options.

  ## Compatibility

  This function tries the new `mcpServerStatus/list` method first. If the server
  returns a "method not found" (`-32601`) or "unknown variant" (`-32600`) error
  (older servers), it falls back to the legacy `mcpServers/list` method
  automatically.
  """
  @spec list_servers(connection(), keyword()) :: {:ok, map()} | {:error, term()}
  def list_servers(conn, opts \\ []) when is_pid(conn) and is_list(opts) do
    params =
      %{}
      |> Params.put_optional("cursor", Keyword.get(opts, :cursor))
      |> Params.put_optional("limit", Keyword.get(opts, :limit))

    case Connection.request(conn, "mcpServerStatus/list", params, timeout_ms: 30_000) do
      {:error, %{"code" => -32_601}} ->
        Connection.request(conn, "mcpServers/list", params, timeout_ms: 30_000)

      {:error, %{code: -32_601}} ->
        Connection.request(conn, "mcpServers/list", params, timeout_ms: 30_000)

      {:error, error} ->
        if unknown_variant_mcp_server_status_list?(error) do
          Connection.request(conn, "mcpServers/list", params, timeout_ms: 30_000)
        else
          {:error, error}
        end

      result ->
        result
    end
  end

  @doc """
  Alias for `list_servers/2`. Returns MCP server status information.
  """
  @spec list_server_statuses(connection(), keyword()) :: {:ok, map()} | {:error, term()}
  def list_server_statuses(conn, opts \\ []), do: list_servers(conn, opts)

  @spec oauth_login(connection(), keyword()) :: {:ok, map()} | {:error, term()}
  def oauth_login(conn, opts) when is_pid(conn) and is_list(opts) do
    name = Keyword.fetch!(opts, :name)

    params =
      %{"name" => name}
      |> Params.put_optional("scopes", Keyword.get(opts, :scopes))
      |> Params.put_optional("timeoutSecs", Keyword.get(opts, :timeout_secs))

    Connection.request(conn, "mcpServer/oauth/login", params, timeout_ms: 30_000)
  end

  defp unknown_variant_mcp_server_status_list?(%{"code" => -32_600, "message" => message})
       when is_binary(message) do
    String.contains?(message, "unknown variant") and
      String.contains?(message, "mcpServerStatus/list")
  end

  defp unknown_variant_mcp_server_status_list?(%{code: -32_600, message: message})
       when is_binary(message) do
    String.contains?(message, "unknown variant") and
      String.contains?(message, "mcpServerStatus/list")
  end

  defp unknown_variant_mcp_server_status_list?(_error), do: false
end
