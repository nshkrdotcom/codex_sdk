defmodule Codex.OAuth.Flows.BrowserCode do
  @moduledoc false

  alias Codex.Auth.Store
  alias Codex.Config.Defaults
  alias Codex.Net.CA
  alias Codex.OAuth.LoopbackServer
  alias Codex.OAuth.PKCE
  alias Codex.OAuth.Session
  alias Codex.OAuth.State
  alias Codex.OAuth.TokenStore.File, as: FileTokenStore
  alias Codex.OAuth.TokenStore.Memory, as: MemoryTokenStore

  @token_headers [{"content-type", "application/x-www-form-urlencoded"}]
  @type callback_pending_login :: %Session.PendingLogin{loopback_server: LoopbackServer.t()}
  @type exchange_pending_login :: Session.PendingLogin.t()

  @spec begin(Codex.OAuth.Context.t(), keyword()) ::
          {:ok, Session.PendingLogin.t()} | {:error, term()}
  def begin(context, opts \\ []) when is_list(opts) do
    storage = normalize_storage(Keyword.get(opts, :storage, context.storage))
    pkce = PKCE.generate()
    state = State.generate()

    with {:ok, loopback_server} <-
           LoopbackServer.start(
             callback_path: Keyword.get(opts, :callback_path, "/auth/callback"),
             expected_state: state,
             port: Keyword.get(opts, :callback_port, Defaults.oauth_browser_callback_port())
           ) do
      redirect_uri = loopback_server.callback_url
      authorize_url = authorize_url(context.provider, redirect_uri, pkce, state, opts)

      {:ok,
       %Session.PendingLogin{
         provider: :openai_chatgpt,
         flow: :browser_code,
         storage: storage,
         context: context,
         authorize_url: authorize_url,
         state: state,
         pkce: pkce,
         redirect_uri: redirect_uri,
         loopback_server: loopback_server,
         warnings: []
       }}
    end
  end

  @spec await(callback_pending_login(), keyword()) :: {:ok, Session.t()} | {:error, term()}
  def await(%Session.PendingLogin{loopback_server: %LoopbackServer{}} = pending, opts \\ [])
      when is_list(opts) do
    timeout_ms = Keyword.get(opts, :timeout, Defaults.oauth_browser_callback_timeout_ms())

    with {:ok, %{code: code}} <- LoopbackServer.await_result(pending.loopback_server, timeout_ms),
         {:ok, response} <- exchange_code(pending, code, opts) do
      persist_or_store_session(pending, response)
    end
  end

  @doc false
  @spec await_exchange(exchange_pending_login(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def await_exchange(%Session.PendingLogin{} = pending, code, opts \\ []) when is_binary(code) do
    exchange_code(pending, code, opts)
  end

  @spec authorize_url(
          Codex.OAuth.Provider.OpenAI.t(),
          String.t(),
          PKCE.t(),
          String.t(),
          keyword()
        ) ::
          String.t()
  def authorize_url(provider, redirect_uri, %PKCE{} = pkce, state, opts \\ []) do
    params =
      [
        response_type: "code",
        scope: provider.scope,
        code_challenge: pkce.challenge,
        code_challenge_method: pkce.method,
        id_token_add_organizations: "true",
        codex_cli_simplified_flow: "true",
        state: state,
        originator: provider.originator,
        allowed_workspace_id: Keyword.get(opts, :allowed_workspace_id)
      ]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)

    OAuth2.Client.new(
      authorize_url: provider.authorize_url,
      client_id: provider.client_id,
      redirect_uri: redirect_uri,
      site: provider.issuer,
      token_url: provider.token_url
    )
    |> OAuth2.Client.authorize_url!(params)
  end

  defp exchange_code(%Session.PendingLogin{} = pending, code, opts) do
    env = pending.context.child_process_env
    receive_timeout = Keyword.get(opts, :timeout_ms, Defaults.oauth_http_timeout_ms())

    request_opts =
      [
        headers: @token_headers,
        form: [
          grant_type: "authorization_code",
          code: code,
          redirect_uri: pending.redirect_uri,
          client_id: pending.context.client_id,
          code_verifier: pending.pkce.verifier
        ],
        receive_timeout: receive_timeout
      ]
      |> CA.merge_req_options(env)

    case Req.post(pending.context.provider.token_url, request_opts) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        normalize_token_response(body)

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:token_exchange_failed, status, redact_body(body)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp persist_or_store_session(
         %Session.PendingLogin{context: context, flow: flow} = pending,
         response
       ) do
    record =
      Store.build_record(
        auth_mode: :chatgpt,
        openai_api_key: response.access_token,
        access_token: response.access_token,
        refresh_token: response.refresh_token,
        id_token: response.id_token,
        account_id: response.account_id,
        last_refresh: DateTime.utc_now()
      )

    case pending.storage do
      :memory ->
        case MemoryTokenStore.start_link(record, context,
               provider: :openai_chatgpt,
               flow: flow
             ) do
          {:ok, token_store} ->
            session = MemoryTokenStore.fetch(token_store)
            {:ok, %Session{session | token_store: token_store}}

          {:error, _} = error ->
            error
        end

      :file ->
        FileTokenStore.persist(record, context, provider: :openai_chatgpt, flow: flow)
    end
  end

  defp normalize_token_response(%{} = body), do: normalize_token_response_map(body)

  defp normalize_token_response(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, %{} = decoded} -> normalize_token_response_map(decoded)
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_token_response(_), do: {:error, :invalid_token_response}

  defp normalize_token_response_map(map) do
    access_token = fetch_string(map, "access_token")
    refresh_token = fetch_string(map, "refresh_token")
    id_token = fetch_string(map, "id_token")

    with {:ok, access_token} <- access_token,
         {:ok, refresh_token} <- refresh_token,
         {:ok, id_token} <- id_token do
      record =
        Store.build_record(
          auth_mode: :chatgpt,
          openai_api_key: access_token,
          access_token: access_token,
          refresh_token: refresh_token,
          id_token: id_token,
          last_refresh: DateTime.utc_now()
        )

      {:ok,
       %{
         access_token: access_token,
         refresh_token: refresh_token,
         id_token: id_token,
         account_id: record.tokens && record.tokens.account_id
       }}
    end
  end

  defp fetch_string(map, key) do
    case Map.get(map, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, {:missing_oauth_field, key}}
    end
  end

  defp normalize_storage(:memory), do: :memory
  defp normalize_storage(_), do: :file

  defp redact_body(%{} = body), do: Map.take(body, ["error", "error_description"])
  defp redact_body(_), do: nil
end
