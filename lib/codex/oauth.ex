defmodule Codex.OAuth do
  @moduledoc """
  Native OAuth login and session management for Codex.

  `Codex.OAuth` adds an SDK-managed ChatGPT login path alongside the existing
  CLI passthrough and API-key flows:

  - `storage: :file` or `:auto` writes an upstream-compatible `auth.json`
    under the effective `CODEX_HOME`
  - `storage: :memory` keeps tokens in memory for host-managed and app-server
    external auth flows

  Flow selection is environment-aware:

  - local desktop prefers browser auth-code + PKCE + loopback callback
  - WSL starts with browser auth, then falls back to device code if the
    callback does not arrive quickly
  - SSH/headless/container environments prefer device code
  - non-interactive environments never start a login automatically

  All OAuth HTTP traffic reuses `Codex.Net.CA`, so `CODEX_CA_CERTIFICATE` and
  `SSL_CERT_FILE` apply consistently to login and refresh requests.
  """

  alias Codex.Auth.Store
  alias Codex.Config.Defaults
  alias Codex.Net.CA
  alias Codex.OAuth.Browser
  alias Codex.OAuth.Context
  alias Codex.OAuth.Environment
  alias Codex.OAuth.Flows.BrowserCode
  alias Codex.OAuth.Flows.DeviceCode
  alias Codex.OAuth.LoginResult
  alias Codex.OAuth.LoopbackServer
  alias Codex.OAuth.Session
  alias Codex.OAuth.Status
  alias Codex.OAuth.TokenStore.File, as: FileTokenStore
  alias Codex.OAuth.TokenStore.Memory, as: MemoryTokenStore

  @typedoc "OAuth flow selection."
  @type flow :: :auto | :browser | :browser_code | :device | :device_code

  @typedoc "OAuth storage strategy."
  @type storage :: :auto | :file | :memory

  @spec login(keyword()) :: {:ok, LoginResult.t()} | {:error, term()}
  @doc """
  Ensures a usable OAuth session exists and returns its current status.

  With `storage: :file` or `:auto`, this writes upstream-compatible auth state
  under the effective `CODEX_HOME`. With `storage: :memory`, tokens stay in
  memory only.
  """
  def login(opts \\ []) when is_list(opts) do
    with {:ok, session, warnings} <- login_session(opts) do
      {:ok, to_login_result(session, warnings)}
    end
  end

  @spec begin_login(keyword()) ::
          {:ok, Session.PendingLogin.t() | Session.PendingDeviceLogin.t()} | {:error, term()}
  @doc """
  Starts an OAuth login without opening a browser or waiting for completion.

  Host applications can use this together with `open_in_browser/2` and
  `await_login/2` to control the login UX themselves.
  """
  def begin_login(opts \\ []) when is_list(opts) do
    with {:ok, context, storage, _warnings} <- resolve_context_storage(opts),
         {:ok, flow} <- resolve_flow(context, opts),
         :ok <- ensure_interactive(flow, context.environment) do
      begin_flow(context, flow, storage, opts)
    end
  end

  @spec await_login(Session.PendingLogin.t() | Session.PendingDeviceLogin.t(), keyword()) ::
          {:ok, LoginResult.t()} | {:error, term()}
  @doc """
  Waits for a pending login started by `begin_login/1` to complete.
  """
  def await_login(pending, opts \\ [])

  def await_login(%Session.PendingLogin{} = pending, opts) do
    with {:ok, session} <- BrowserCode.await(pending, opts) do
      {:ok, to_login_result(session, pending.warnings || [])}
    end
  end

  def await_login(%Session.PendingDeviceLogin{} = pending, opts) do
    with {:ok, session} <- DeviceCode.await(pending, opts) do
      {:ok, to_login_result(session, pending.warnings || [])}
    end
  end

  @spec open_in_browser(Session.PendingLogin.t(), keyword()) :: :ok | {:error, term()}
  @doc """
  Opens a pending browser-based login in the user's external browser.
  """
  def open_in_browser(pending, opts \\ [])

  def open_in_browser(%Session.PendingLogin{} = pending, opts) do
    Browser.open(
      pending.authorize_url,
      pending.context.environment,
      browser_opener:
        Keyword.get(opts, :browser_opener) || pending.context.browser_opener ||
          Keyword.get(opts, :opener)
    )
  end

  def open_in_browser(_pending, _opts), do: {:error, :browser_flow_required}

  @spec authorize_url(keyword()) :: {:ok, String.t()} | {:error, term()}
  @doc """
  Returns the authorize URL for a browser-based login attempt.
  """
  def authorize_url(opts \\ []) when is_list(opts) do
    with {:ok, %Session.PendingLogin{} = pending} <-
           begin_login(Keyword.put(opts, :flow, :browser_code)) do
      {:ok, pending.authorize_url}
    end
  end

  @spec status(keyword()) :: {:ok, Status.t()} | {:error, term()}
  @doc """
  Reads the current OAuth auth state for the effective `CODEX_HOME`.
  """
  def status(opts \\ []) when is_list(opts) do
    with {:ok, context, _storage, warnings} <- resolve_context_storage(opts) do
      case load_session(context, opts) do
        {:ok, nil} ->
          {:ok, %Status{authenticated?: false, warnings: warnings}}

        {:ok, %Session{} = session} ->
          {:ok, to_status(session, warnings)}

        {:error, _} = error ->
          error
      end
    end
  end

  @spec refresh(keyword()) :: {:ok, Status.t()} | {:error, term()}
  @doc """
  Refreshes the current OAuth session with the provider token endpoint.
  """
  def refresh(opts \\ []) when is_list(opts) do
    with {:ok, context, _storage, warnings} <- resolve_context_storage(opts),
         {:ok, %Session{} = session} <- load_session(context, opts),
         {:ok, refreshed} <- refresh_session(session, opts) do
      {:ok, to_status(refreshed, warnings)}
    else
      {:ok, nil} -> {:error, :not_authenticated}
      {:error, _} = error -> error
    end
  end

  @spec logout(keyword()) :: :ok | {:error, term()}
  @doc """
  Removes persisted OAuth auth state and stops any in-memory token store.
  """
  def logout(opts \\ []) when is_list(opts) do
    with {:ok, context, _storage, _warnings} <- resolve_context_storage(opts) do
      maybe_stop_token_store(Keyword.get(opts, :token_store))

      case FileTokenStore.delete(context) do
        :ok -> :ok
        {:error, _} = error -> error
      end
    end
  end

  @doc false
  @spec login_session(keyword()) :: {:ok, Session.t(), [String.t()]} | {:error, term()}
  def login_session(opts \\ []) when is_list(opts) do
    case resolve_context_storage(opts) do
      {:ok, context, storage, warnings} ->
        maybe_login_with_stored_session(context, storage, warnings, opts)

      {:error, _} = error ->
        error
    end
  end

  @doc false
  @spec load_session(Context.t(), keyword()) :: {:ok, Session.t() | nil} | {:error, term()}
  def load_session(%Context{} = context, opts \\ []) when is_list(opts) do
    case Keyword.get(opts, :token_store) do
      pid when is_pid(pid) ->
        {:ok, MemoryTokenStore.fetch(pid)}

      _ ->
        FileTokenStore.load(context)
    end
  end

  @doc false
  @spec refresh_session(Session.t(), keyword()) :: {:ok, Session.t()} | {:error, term()}
  def refresh_session(%Session{auth_record: %Store.Record{tokens: nil}}, _opts) do
    {:error, :missing_tokens}
  end

  def refresh_session(%Session{} = session, opts) do
    tokens = session.auth_record.tokens
    refresh_token = tokens.refresh_token || session.auth_record.tokens.refresh_token
    persist? = Keyword.get(opts, :persist?, true)

    case refresh_token do
      token when is_binary(token) and token != "" ->
        session
        |> refresh_request_options(token)
        |> request_refresh(session, persist?)

      _ ->
        {:error, :missing_refresh_token}
    end
  end

  defp maybe_login_with_stored_session(context, storage, warnings, opts) do
    if Keyword.get(opts, :ignore_stored_session?, false) do
      run_login_flow(context, storage, warnings, opts)
    else
      load_or_login_session(context, storage, warnings, opts)
    end
  end

  defp load_or_login_session(context, storage, warnings, opts) do
    case load_session(context, opts) do
      {:ok, %Session{} = session} ->
        {:ok, session, warnings}

      {:ok, nil} ->
        run_login_flow(context, storage, warnings, opts)

      {:error, _} = error ->
        error
    end
  end

  defp refresh_request_options(session, refresh_token) do
    [
      headers: [{"content-type", "application/x-www-form-urlencoded"}],
      form: [
        grant_type: "refresh_token",
        client_id: session.context.client_id,
        refresh_token: refresh_token
      ],
      receive_timeout: Defaults.oauth_http_timeout_ms()
    ]
    |> CA.merge_req_options(session.context.child_process_env)
  end

  defp request_refresh(request_opts, session, persist?) do
    case Req.post(session.context.provider.token_url, request_opts) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        refresh_success(session, body, persist?)

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:refresh_failed, status, body}}

      {:error, _} = error ->
        error
    end
  end

  defp refresh_success(session, body, persist?) do
    with {:ok, refreshed_record} <- refresh_record(session.auth_record, body) do
      persist_refreshed_session(session, refreshed_record, persist?)
    end
  end

  defp run_login_flow(context, storage, warnings, opts) do
    with {:ok, flow} <- resolve_flow(context, opts),
         :ok <- ensure_interactive(flow, context.environment) do
      case flow do
        :browser_code ->
          login_with_browser(context, storage, warnings, opts)

        :device_code ->
          login_with_device_code(context, storage, warnings, opts)

        :none ->
          {:error, :interactive_login_unavailable}
      end
    end
  end

  defp login_with_browser(context, storage, warnings, opts) do
    case BrowserCode.begin(context, Keyword.put(opts, :storage, storage)) do
      {:ok, pending} ->
        open_and_await_browser_login(pending, context, storage, warnings, opts)

      {:error, _reason} = error ->
        maybe_fallback_browser_error(error, context, storage, warnings, opts)
    end
  end

  defp login_with_device_code(context, storage, warnings, opts) do
    with {:ok, pending} <- DeviceCode.begin(context, Keyword.put(opts, :storage, storage)),
         :ok <- maybe_present_device_login(pending, context),
         {:ok, session} <- DeviceCode.await(pending, opts) do
      {:ok, session, warnings}
    end
  end

  defp maybe_present_device_login(%Session.PendingDeviceLogin{} = pending, %Context{
         presenter: presenter
       }) do
    message = %{
      verification_url: pending.verification_url,
      user_code: pending.user_code,
      expires_at: pending.expires_at
    }

    case presenter do
      fun when is_function(fun, 1) ->
        _ = fun.(message)
        :ok

      _ ->
        IO.puts("Open #{pending.verification_url} and enter code #{pending.user_code}")
        :ok
    end
  end

  defp cancel_browser_pending(%Session.PendingLogin{} = pending) do
    LoopbackServer.cancel(pending.loopback_server)
  end

  defp resolve_context_storage(opts) do
    with {:ok, context} <- Context.resolve(opts) do
      requested_storage = Keyword.get(opts, :storage, :auto)
      {storage, warnings} = normalize_storage(requested_storage, context)
      {:ok, context, storage, warnings}
    end
  end

  defp normalize_storage(:memory, _context), do: {:memory, []}

  defp normalize_storage(storage, context) when storage in [:auto, :file] do
    if context.credentials_store_mode in [:keyring, :auto] and not Store.keyring_supported?() do
      {:file,
       [
         "codex_sdk does not support keyring-backed OAuth storage yet; falling back to file storage under CODEX_HOME."
       ]}
    else
      {:file, []}
    end
  end

  defp normalize_storage(_other, context), do: normalize_storage(:auto, context)

  defp resolve_flow(%Context{} = context, opts) do
    case Keyword.get(opts, :flow, :auto) do
      :auto -> {:ok, context.environment.preferred_flow}
      :browser -> {:ok, :browser_code}
      :browser_code -> {:ok, :browser_code}
      :device -> {:ok, :device_code}
      :device_code -> {:ok, :device_code}
      other -> {:error, {:unsupported_oauth_flow, other}}
    end
  end

  defp ensure_interactive(:none, _environment), do: {:error, :interactive_login_unavailable}
  defp ensure_interactive(_flow, %Environment{interactive?: true}), do: :ok
  defp ensure_interactive(_flow, _environment), do: {:error, :interactive_login_unavailable}

  defp begin_flow(context, :browser_code, storage, opts) do
    with {:ok, pending} <- BrowserCode.begin(context, Keyword.put(opts, :storage, storage)) do
      {:ok, put_pending_warnings(pending, storage_warning(context, storage))}
    end
  end

  defp begin_flow(context, :device_code, storage, opts) do
    with {:ok, pending} <- DeviceCode.begin(context, Keyword.put(opts, :storage, storage)) do
      {:ok, put_pending_warnings(pending, storage_warning(context, storage))}
    end
  end

  defp begin_flow(_context, :none, _storage, _opts), do: {:error, :interactive_login_unavailable}

  defp storage_warning(context, :file) do
    if context.credentials_store_mode in [:keyring, :auto] and not Store.keyring_supported?() do
      [
        "codex_sdk does not support keyring-backed OAuth storage yet; falling back to file storage under CODEX_HOME."
      ]
    else
      []
    end
  end

  defp storage_warning(_context, _storage), do: []

  defp put_pending_warnings(%module{} = pending, warnings)
       when module in [Session.PendingLogin, Session.PendingDeviceLogin] do
    %{pending | warnings: warnings}
  end

  defp refresh_record(%Store.Record{} = current_record, body) do
    case normalize_refresh_response(body, current_record) do
      {:ok, record} -> {:ok, record}
      {:error, _} = error -> error
    end
  end

  defp normalize_refresh_response(%{} = body, %Store.Record{} = current_record) do
    access_token = Map.get(body, "access_token") || current_record.tokens.access_token
    refresh_token = Map.get(body, "refresh_token") || current_record.tokens.refresh_token
    id_token = Map.get(body, "id_token") || current_record.tokens.id_token

    {:ok,
     Store.build_record(
       auth_mode: current_record.auth_mode,
       openai_api_key: access_token,
       access_token: access_token,
       refresh_token: refresh_token,
       id_token: id_token,
       account_id: Map.get(body, "account_id"),
       last_refresh: DateTime.utc_now()
     )}
  end

  defp normalize_refresh_response(body, %Store.Record{} = current_record) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, %{} = decoded} -> normalize_refresh_response(decoded, current_record)
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_refresh_response(_body, _current_record), do: {:error, :invalid_refresh_response}

  defp persist_refreshed_session(
         %Session{} = session,
         %Store.Record{} = refreshed_record,
         persist?
       ) do
    refreshed_session = %Session{session | auth_record: refreshed_record}

    cond do
      persist? and session.persisted? ->
        with :ok <- Store.write(refreshed_record, codex_home: session.context.codex_home) do
          {:ok, refreshed_session}
        end

      persist? and is_pid(session.token_store) ->
        :ok = MemoryTokenStore.put(session.token_store, refreshed_session)
        {:ok, refreshed_session}

      true ->
        {:ok, refreshed_session}
    end
  end

  defp maybe_stop_token_store(pid) when is_pid(pid) do
    Agent.stop(pid)
    :ok
  catch
    :exit, _ -> :ok
  end

  defp maybe_stop_token_store(_), do: :ok

  defp open_and_await_browser_login(pending, context, storage, warnings, opts) do
    case open_in_browser(pending, opts) do
      :ok ->
        await_browser_login(pending, context, storage, warnings, opts)

      {:error, _reason} = error ->
        maybe_fallback_browser_error(error, context, storage, warnings, opts)
    end
  end

  defp await_browser_login(pending, context, storage, warnings, opts) do
    case browser_login_result(pending, context, opts) do
      {:ok, session} ->
        {:ok, session, warnings}

      {:error, :timeout} ->
        maybe_fallback_browser_timeout(pending, context, storage, warnings, opts)

      {:error, _} = error ->
        error
    end
  end

  defp browser_login_result(pending, context, opts) do
    if browser_wsl_fallback?(context) do
      BrowserCode.await(
        pending,
        timeout: Defaults.oauth_wsl_device_fallback_grace_ms()
      )
    else
      BrowserCode.await(pending, opts)
    end
  end

  defp maybe_fallback_browser_error(error, context, storage, warnings, opts) do
    if browser_wsl_fallback?(context) do
      login_with_device_code(
        context,
        storage,
        warnings ++ ["Browser open failed under WSL; falling back to device code login."],
        opts
      )
    else
      error
    end
  end

  defp maybe_fallback_browser_timeout(pending, context, storage, warnings, opts) do
    if browser_wsl_fallback?(context) do
      cancel_browser_pending(pending)

      login_with_device_code(
        context,
        storage,
        warnings ++
          ["WSL browser callback did not arrive; falling back to device code login."],
        opts
      )
    else
      {:error, :timeout}
    end
  end

  defp browser_wsl_fallback?(context) do
    context.environment.wsl? and context.environment.fallback_flow == :device_code
  end

  defp to_login_result(%Session{} = session, warnings) do
    tokens = session.auth_record.tokens

    %LoginResult{
      provider: session.provider,
      flow_used: session.flow,
      storage_used: session.storage,
      auth_mode: session.auth_record.auth_mode,
      account_id: tokens && tokens.account_id,
      plan_type: tokens && tokens.plan_type,
      expires_at: tokens && tokens.expires_at,
      persisted?: session.persisted?,
      warnings: warnings
    }
  end

  defp to_status(%Session{} = session, warnings) do
    tokens = session.auth_record.tokens

    %Status{
      authenticated?: true,
      provider: session.provider,
      storage_used: session.storage,
      auth_mode: session.auth_record.auth_mode,
      account_id: tokens && tokens.account_id,
      plan_type: tokens && tokens.plan_type,
      expires_at: tokens && tokens.expires_at,
      persisted?: session.persisted?,
      warnings: warnings
    }
  end
end
