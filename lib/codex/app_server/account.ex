defmodule Codex.AppServer.Account do
  @moduledoc false

  alias Codex.AppServer.Connection
  alias Codex.AppServer.Params

  @type connection :: pid()

  @spec login_start(connection(), :chatgpt | {:api_key, String.t()} | map()) ::
          {:ok, map()} | {:error, term()}
  def login_start(conn, :chatgpt) when is_pid(conn) do
    Connection.request(conn, "account/login/start", %{"type" => "chatgpt"}, timeout_ms: 30_000)
  end

  def login_start(conn, "chatgpt") when is_pid(conn) do
    login_start(conn, :chatgpt)
  end

  def login_start(conn, {:api_key, api_key}) when is_pid(conn) and is_binary(api_key) do
    params = %{"type" => "apiKey", "apiKey" => api_key}
    Connection.request(conn, "account/login/start", params, timeout_ms: 30_000)
  end

  def login_start(conn, %{} = params) when is_pid(conn) do
    Connection.request(conn, "account/login/start", Params.normalize_map(params),
      timeout_ms: 30_000
    )
  end

  @spec login_cancel(connection(), String.t()) :: {:ok, map()} | {:error, term()}
  def login_cancel(conn, login_id) when is_pid(conn) and is_binary(login_id) do
    Connection.request(conn, "account/login/cancel", %{"loginId" => login_id}, timeout_ms: 30_000)
  end

  @spec logout(connection()) :: {:ok, map()} | {:error, term()}
  def logout(conn) when is_pid(conn) do
    Connection.request(conn, "account/logout", nil, timeout_ms: 30_000)
  end

  @spec read(connection(), keyword()) :: {:ok, map()} | {:error, term()}
  def read(conn, opts \\ []) when is_pid(conn) and is_list(opts) do
    params = %{"refreshToken" => !!Keyword.get(opts, :refresh_token, false)}
    Connection.request(conn, "account/read", params, timeout_ms: 30_000)
  end

  @spec rate_limits(connection()) :: {:ok, map()} | {:error, term()}
  def rate_limits(conn) when is_pid(conn) do
    Connection.request(conn, "account/rateLimits/read", nil, timeout_ms: 30_000)
  end
end
