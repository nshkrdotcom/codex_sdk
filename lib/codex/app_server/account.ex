defmodule Codex.AppServer.Account do
  @moduledoc false

  alias Codex.AppServer.Connection
  alias Codex.AppServer.Params
  alias Codex.Auth
  alias Codex.Config.LayerStack
  alias Codex.GovernedAuthority
  alias Codex.Runtime.Env, as: RuntimeEnv

  @type connection :: pid()
  @login_type_map %{
    "chatgpt" => :chatgpt,
    "chatgptAuthTokens" => :chatgpt,
    "chatgpt_auth_tokens" => :chatgpt,
    "apiKey" => :api_key,
    "api_key" => :api_key,
    "api" => :api_key,
    "amazonBedrock" => :bedrock_api_key
  }

  @type login_method ::
          :chatgpt
          | {:api_key, String.t()}
          | {:amazon_bedrock, String.t(), String.t()}
          | map()

  @spec login_start(connection(), login_method()) ::
          {:ok, map()} | {:error, term()}
  def login_start(conn, :chatgpt) when is_pid(conn) do
    login_start(conn, :chatgpt, [])
  end

  def login_start(conn, "chatgpt") when is_pid(conn) do
    login_start(conn, :chatgpt, [])
  end

  def login_start(conn, {:api_key, api_key}) when is_pid(conn) and is_binary(api_key) do
    login_start(conn, {:api_key, api_key}, [])
  end

  def login_start(conn, {:amazon_bedrock, api_key, region})
      when is_pid(conn) and is_binary(api_key) and is_binary(region) do
    login_start(conn, {:amazon_bedrock, api_key, region}, [])
  end

  def login_start(conn, %{} = params) when is_pid(conn) do
    login_start(conn, params, [])
  end

  @doc """
  Starts an account login with current app-server presentation options.

  ChatGPT login accepts `:app_brand`, `:codex_streamlined_login`, and
  `:use_hosted_login_success_page`.

  Amazon Bedrock login is an unstable upstream app-server API. Its connection must
  have been initialized with `experimental_api: true`. The current upstream server
  publishes the request schema but returns an unimplemented error when it is used.
  """
  @spec login_start(connection(), login_method(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def login_start(conn, :chatgpt, opts) when is_pid(conn) and is_list(opts) do
    params =
      %{"type" => "chatgpt"}
      |> Params.put_optional("appBrand", normalize_login_app_brand(Keyword.get(opts, :app_brand)))
      |> Params.put_optional(
        "codexStreamlinedLogin",
        enabled_option(Keyword.get(opts, :codex_streamlined_login))
      )
      |> Params.put_optional(
        "useHostedLoginSuccessPage",
        enabled_option(Keyword.get(opts, :use_hosted_login_success_page))
      )

    with :ok <- reject_governed_login(opts),
         :ok <- enforce_login_constraints(:chatgpt, params, opts) do
      Connection.request(conn, "account/login/start", params, timeout_ms: 30_000)
    end
  end

  def login_start(conn, "chatgpt", opts) when is_pid(conn) and is_list(opts) do
    login_start(conn, :chatgpt, opts)
  end

  def login_start(conn, {:api_key, api_key}, opts)
      when is_pid(conn) and is_binary(api_key) and is_list(opts) do
    params = %{"type" => "apiKey", "apiKey" => api_key}

    with :ok <- reject_governed_login(opts),
         :ok <- enforce_login_constraints(:api_key, params, opts) do
      Connection.request(conn, "account/login/start", params, timeout_ms: 30_000)
    end
  end

  def login_start(conn, {:amazon_bedrock, api_key, region}, opts)
      when is_pid(conn) and is_binary(api_key) and is_binary(region) and is_list(opts) do
    params = %{"type" => "amazonBedrock", "apiKey" => api_key, "region" => region}

    with :ok <- reject_governed_login(opts),
         :ok <- validate_amazon_bedrock_login(api_key, region),
         :ok <- enforce_login_constraints(:bedrock_api_key, params, opts) do
      Connection.request(conn, "account/login/start", params, timeout_ms: 30_000)
    end
  end

  def login_start(conn, %{} = params, opts) when is_pid(conn) and is_list(opts) do
    normalized = Params.normalize_map(params)

    with :ok <- reject_governed_login(opts),
         {:ok, login_type} <- infer_login_type(normalized),
         :ok <- enforce_login_constraints(login_type, normalized, opts) do
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

  @spec send_add_credits_nudge_email(connection(), :credits | :usage_limit | String.t()) ::
          {:ok, map()} | {:error, term()}
  def send_add_credits_nudge_email(conn, credit_type) when is_pid(conn) do
    params = %{"creditType" => normalize_add_credits_nudge_credit_type(credit_type)}

    Connection.request(conn, "account/sendAddCreditsNudgeEmail", params, timeout_ms: 30_000)
  end

  @doc """
  Reads account token usage (lifetime/streak summary plus optional daily buckets).
  """
  @spec usage(connection()) :: {:ok, map()} | {:error, term()}
  def usage(conn) when is_pid(conn) do
    Connection.request(conn, "account/usage/read", nil, timeout_ms: 30_000)
  end

  @doc """
  Reads active workspace messages (headlines/announcements) for the account.
  """
  @spec workspace_messages(connection()) :: {:ok, map()} | {:error, term()}
  def workspace_messages(conn) when is_pid(conn) do
    Connection.request(conn, "account/workspaceMessages/read", nil, timeout_ms: 30_000)
  end

  @doc """
  Consumes a rate-limit reset credit.

  Pass `credit_id:` to redeem a specific credit (from `rate_limits/1`'s
  `rateLimitResetCredits.credits` list); omit it to let the backend
  auto-select the next available credit.
  """
  @spec consume_rate_limit_reset_credit(connection(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def consume_rate_limit_reset_credit(conn, opts \\ []) when is_pid(conn) and is_list(opts) do
    credit_id = Keyword.get(opts, :credit_id, Keyword.get(opts, :creditId))
    idempotency_key = Keyword.get(opts, :idempotency_key, Keyword.get(opts, :idempotencyKey))

    params =
      %{}
      |> Params.put_optional("creditId", credit_id)
      |> Params.put_optional("idempotencyKey", idempotency_key)

    Connection.request(
      conn,
      "account/rateLimitResetCredit/consume",
      params,
      timeout_ms: 30_000
    )
  end

  defp enforce_login_constraints(login_type, params, opts) do
    with {:ok, %{forced_login_method: forced_method, forced_chatgpt_workspace_id: workspace_id}} <-
           load_forced_login_config(opts),
         :ok <- enforce_forced_login_method(forced_method, login_type) do
      enforce_forced_workspace_id(workspace_id, login_type, params)
    end
  end

  defp enforce_forced_login_method(nil, _login_type), do: :ok
  defp enforce_forced_login_method("chatgpt", :chatgpt), do: :ok
  defp enforce_forced_login_method("api", :api_key), do: :ok
  defp enforce_forced_login_method("api", :bedrock_api_key), do: :ok

  defp enforce_forced_login_method(forced, login_type) do
    {:error, {:forced_login_method, forced, login_type}}
  end

  defp enforce_forced_workspace_id(nil, _login_type, _params), do: :ok

  defp enforce_forced_workspace_id(_workspace_id, :api_key, _params), do: :ok
  defp enforce_forced_workspace_id(_workspace_id, :bedrock_api_key, _params), do: :ok

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

  defp normalize_add_credits_nudge_credit_type(:credits), do: "credits"
  defp normalize_add_credits_nudge_credit_type(:usage_limit), do: "usage_limit"
  defp normalize_add_credits_nudge_credit_type("credits"), do: "credits"
  defp normalize_add_credits_nudge_credit_type("usage_limit"), do: "usage_limit"
  defp normalize_add_credits_nudge_credit_type(value) when is_binary(value), do: value
  defp normalize_add_credits_nudge_credit_type(value), do: to_string(value)

  defp infer_login_type(%{} = params) do
    type = Map.get(params, "type") || Map.get(params, :type)

    case Map.fetch(@login_type_map, type) do
      {:ok, login_type} -> {:ok, login_type}
      :error -> {:error, {:invalid_login_type, type}}
    end
  end

  defp validate_amazon_bedrock_login(api_key, _region) when byte_size(api_key) == 0 do
    {:error, {:invalid_amazon_bedrock_login, :api_key_required}}
  end

  defp validate_amazon_bedrock_login(api_key, region) do
    cond do
      String.trim(api_key) == "" ->
        {:error, {:invalid_amazon_bedrock_login, :api_key_required}}

      String.trim(region) == "" ->
        {:error, {:invalid_amazon_bedrock_login, :region_required}}

      true ->
        :ok
    end
  end

  defp load_forced_login_config(opts) do
    with {:ok, authority} <- GovernedAuthority.fetch(opts),
         {:ok, child_process_env} <- resolve_child_env(opts, authority),
         :ok <- GovernedAuthority.validate_runtime_env(authority, child_process_env),
         {:ok, cwd} <- resolve_cwd(opts, authority),
         {:ok, codex_home} <- resolve_codex_home(opts, child_process_env, authority),
         {:ok, layers} <- LayerStack.load(codex_home, cwd) do
      {:ok, forced_login_config(LayerStack.effective_config(layers))}
    else
      {:error, reason} ->
        if governed_opts?(opts) do
          {:error, reason}
        else
          {:ok, forced_login_config(%{})}
        end
    end
  end

  defp forced_login_config(config) do
    %{
      forced_login_method:
        Map.get(config, "forced_login_method") || Map.get(config, :forced_login_method),
      forced_chatgpt_workspace_id:
        Map.get(config, "forced_chatgpt_workspace_id") ||
          Map.get(config, :forced_chatgpt_workspace_id)
    }
  end

  defp governed_opts?(opts) do
    case GovernedAuthority.fetch(opts) do
      {:ok, %{} = _authority} -> true
      _ -> false
    end
  end

  defp resolve_child_env(opts, nil) do
    process_env = Keyword.get(opts, :process_env, Keyword.get(opts, :env))

    with {:ok, overrides} <- RuntimeEnv.normalize_overrides(process_env) do
      {:ok, Map.merge(Codex.Env.all(), overrides)}
    end
  end

  defp resolve_child_env(opts, %GovernedAuthority{} = authority) do
    with :ok <-
           GovernedAuthority.reject_option_supplementation(authority, opts, :app_server_account) do
      {:ok, GovernedAuthority.child_env(authority)}
    end
  end

  defp resolve_cwd(_opts, %GovernedAuthority{} = authority),
    do: {:ok, GovernedAuthority.child_cwd(authority)}

  defp resolve_cwd(opts, nil) do
    case Keyword.get(opts, :cwd) do
      nil ->
        case File.cwd() do
          {:ok, value} -> {:ok, value}
          _ -> {:ok, nil}
        end

      cwd when is_binary(cwd) ->
        if String.trim(cwd) == "", do: {:error, {:invalid_cwd, cwd}}, else: {:ok, cwd}

      other ->
        {:error, {:invalid_cwd, other}}
    end
  end

  defp resolve_codex_home(opts, child_process_env, nil) do
    case Keyword.get(opts, :codex_home) || Map.get(child_process_env, "CODEX_HOME") do
      value when is_binary(value) and value != "" ->
        {:ok, value}

      _ ->
        {:ok, Auth.codex_home()}
    end
  end

  defp resolve_codex_home(_opts, _child_process_env, %GovernedAuthority{config_root: root}),
    do: {:ok, root}

  defp reject_governed_login(opts) do
    case GovernedAuthority.fetch(opts) do
      {:ok, nil} ->
        :ok

      {:ok, %GovernedAuthority{}} ->
        {:error, {:governed_account_mutation_forbidden, :login_start}}

      {:error, _reason} = error ->
        error
    end
  end

  defp normalize_login_app_brand(value) when value in [:codex, "codex"], do: "codex"
  defp normalize_login_app_brand(value) when value in [:chatgpt, "chatgpt"], do: "chatgpt"
  defp normalize_login_app_brand(_value), do: nil

  defp enabled_option(true), do: true
  defp enabled_option(_value), do: nil

  defp fetch_workspace_id(params) do
    Map.get(params, "workspaceId") ||
      Map.get(params, "chatgptAccountId") ||
      Map.get(params, "workspace_id") ||
      Map.get(params, "chatgpt_account_id") ||
      Map.get(params, :workspaceId) ||
      Map.get(params, :chatgptAccountId) ||
      Map.get(params, :workspace_id) ||
      Map.get(params, :chatgpt_account_id)
  end
end
