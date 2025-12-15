defmodule Codex.AppServer.Mcp do
  @moduledoc false

  alias Codex.AppServer.Connection
  alias Codex.AppServer.Params

  @type connection :: pid()

  @spec list_servers(connection(), keyword()) :: {:ok, map()} | {:error, term()}
  def list_servers(conn, opts \\ []) when is_pid(conn) and is_list(opts) do
    params =
      %{}
      |> Params.put_optional("cursor", Keyword.get(opts, :cursor))
      |> Params.put_optional("limit", Keyword.get(opts, :limit))

    Connection.request(conn, "mcpServers/list", params, timeout_ms: 30_000)
  end

  @spec oauth_login(connection(), keyword()) :: {:ok, map()} | {:error, term()}
  def oauth_login(conn, opts) when is_pid(conn) and is_list(opts) do
    name = Keyword.fetch!(opts, :name)

    params =
      %{"name" => name}
      |> Params.put_optional("scopes", Keyword.get(opts, :scopes))
      |> Params.put_optional("timeoutSecs", Keyword.get(opts, :timeout_secs))

    Connection.request(conn, "mcpServer/oauth/login", params, timeout_ms: 30_000)
  end
end
