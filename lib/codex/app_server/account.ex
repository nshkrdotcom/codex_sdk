defmodule Codex.AppServer.Account do
  @moduledoc false

  alias Codex.AppServer.Connection
  alias Codex.AppServer.Params
  alias Codex.Auth
  alias Codex.Config.LayerStack

  @type connection :: pid()

  @spec login_start(connection(), :chatgpt | {:api_key, String.t()} | map()) ::
          {:ok, map()} | {:error, term()}
  def login_start(conn, :chatgpt) when is_pid(conn) do
    with :ok <- enforce_login_constraints(:chatgpt, %{"type" => "chatgpt"}) do
      Connection.request(conn, "account/login/start", %{"type" => "chatgpt"}, timeout_ms: 30_000)
    end
  end

  def login_start(conn, "chatgpt") when is_pid(conn) do
    login_start(conn, :chatgpt)
  end

  def login_start(conn, {:api_key, api_key}) when is_pid(conn) and is_binary(api_key) do
    params = %{"type" => "apiKey", "apiKey" => api_key}

    with :ok <- enforce_login_constraints(:api_key, params) do
      Connection.request(conn, "account/login/start", params, timeout_ms: 30_000)
    end
  end

  def login_start(conn, %{} = params) when is_pid(conn) do
    normalized = Params.normalize_map(params)

    with {:ok, login_type} <- infer_login_type(normalized),
         :ok <- enforce_login_constraints(login_type, normalized) do
      Connection.request(conn, "account/login/start", normalized, timeout_ms: 30_000)
    end
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

  defp enforce_login_constraints(login_type, params) do
    %{forced_login_method: forced_method, forced_chatgpt_workspace_id: workspace_id} =
      load_forced_login_config()

    with :ok <- enforce_forced_login_method(forced_method, login_type) do
      enforce_forced_workspace_id(workspace_id, login_type, params)
    end
  end

  defp enforce_forced_login_method(nil, _login_type), do: :ok
  defp enforce_forced_login_method("chatgpt", :chatgpt), do: :ok
  defp enforce_forced_login_method("api", :api_key), do: :ok

  defp enforce_forced_login_method(forced, login_type) do
    {:error, {:forced_login_method, forced, login_type}}
  end

  defp enforce_forced_workspace_id(nil, _login_type, _params), do: :ok

  defp enforce_forced_workspace_id(_workspace_id, :api_key, _params), do: :ok

  defp enforce_forced_workspace_id(workspace_id, :chatgpt, params) do
    case fetch_workspace_id(params) do
      nil ->
        :ok

      ^workspace_id ->
        :ok

      other ->
        {:error, {:forced_chatgpt_workspace_id, workspace_id, other}}
    end
  end

  defp infer_login_type(%{} = params) do
    case Map.get(params, "type") || Map.get(params, :type) do
      "chatgpt" -> {:ok, :chatgpt}
      "apiKey" -> {:ok, :api_key}
      "api_key" -> {:ok, :api_key}
      "api" -> {:ok, :api_key}
      other -> {:error, {:invalid_login_type, other}}
    end
  end

  defp load_forced_login_config do
    cwd =
      case File.cwd() do
        {:ok, value} -> value
        _ -> nil
      end

    case LayerStack.load(Auth.codex_home(), cwd) do
      {:ok, layers} ->
        config = LayerStack.effective_config(layers)

        %{
          forced_login_method:
            Map.get(config, "forced_login_method") || Map.get(config, :forced_login_method),
          forced_chatgpt_workspace_id:
            Map.get(config, "forced_chatgpt_workspace_id") ||
              Map.get(config, :forced_chatgpt_workspace_id)
        }

      {:error, _} ->
        %{forced_login_method: nil, forced_chatgpt_workspace_id: nil}
    end
  end

  defp fetch_workspace_id(params) do
    Map.get(params, "workspaceId") ||
      Map.get(params, "workspace_id") ||
      Map.get(params, :workspaceId) ||
      Map.get(params, :workspace_id)
  end
end
