defmodule Codex.OAuth.Flows.DeviceCode do
  @moduledoc false

  alias Codex.Auth.Store
  alias Codex.Config.Defaults
  alias Codex.Net.CA
  alias Codex.OAuth.Flows.BrowserCode
  alias Codex.OAuth.Session
  alias Codex.OAuth.TokenStore.File, as: FileTokenStore
  alias Codex.OAuth.TokenStore.Memory, as: MemoryTokenStore

  @json_headers [{"content-type", "application/json"}]

  @spec begin(Codex.OAuth.Context.t(), keyword()) ::
          {:ok, Session.PendingDeviceLogin.t()} | {:error, term()}
  def begin(context, opts \\ []) when is_list(opts) do
    request_opts =
      [
        headers: @json_headers,
        json: %{client_id: context.client_id},
        receive_timeout: Defaults.oauth_http_timeout_ms()
      ]
      |> CA.merge_req_options(context.child_process_env)

    with {:ok, %Req.Response{status: status, body: body}} when status in 200..299 <-
           Req.post(context.provider.device_authorization_url, request_opts),
         {:ok, pending} <- normalize_pending_device_login(context, body, opts) do
      {:ok, pending}
    else
      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:device_code_start_failed, status, body}}

      {:error, _} = error ->
        error
    end
  end

  @spec await(Session.PendingDeviceLogin.t(), keyword()) :: {:ok, Session.t()} | {:error, term()}
  def await(%Session.PendingDeviceLogin{} = pending, opts \\ []) when is_list(opts) do
    timeout_ms = Keyword.get(opts, :timeout, Defaults.oauth_device_code_timeout_ms())
    sleep_fun = Keyword.get(opts, :sleep_fun, &Process.sleep/1)
    started_at = System.monotonic_time(:millisecond)

    poll_for_tokens(pending, timeout_ms, started_at, sleep_fun)
  end

  defp poll_for_tokens(pending, timeout_ms, started_at, sleep_fun) do
    if System.monotonic_time(:millisecond) - started_at >= timeout_ms do
      {:error, :device_code_timeout}
    else
      case poll_once(pending) do
        {:ok, %{authorization_code: code, code_verifier: verifier}} ->
          exchange_and_persist(pending, code, verifier)

        {:ok, %{access_token: _token} = tokens} ->
          persist_session_from_tokens(pending, tokens)

        {:retry, interval_ms} ->
          sleep_fun.(interval_ms)

          poll_for_tokens(
            %{pending | interval_ms: interval_ms},
            timeout_ms,
            started_at,
            sleep_fun
          )

        {:error, _} = error ->
          error
      end
    end
  end

  defp poll_once(%Session.PendingDeviceLogin{} = pending) do
    request_opts =
      [
        headers: @json_headers,
        json: %{
          device_auth_id: pending.device_code,
          device_code: pending.device_code,
          user_code: pending.user_code
        },
        receive_timeout: Defaults.oauth_http_timeout_ms()
      ]
      |> CA.merge_req_options(pending.context.child_process_env)

    case Req.post(pending.context.provider.device_token_url, request_opts) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        normalize_poll_success(body)

      {:ok, %Req.Response{status: status, body: _body}} when status in [403, 404] ->
        {:retry, pending.interval_ms}

      {:ok, %Req.Response{status: _status, body: body}} ->
        normalize_poll_error(body, pending.interval_ms)

      {:error, _} = error ->
        error
    end
  end

  defp normalize_pending_device_login(context, %{} = body, opts) do
    case {fetch_device_code(body), fetch_user_code(body)} do
      {{:ok, device_code}, {:ok, user_code}} ->
        {:ok, build_pending_device_login(context, body, opts, device_code, user_code)}

      _ ->
        {:error, :invalid_device_code_response}
    end
  end

  defp normalize_pending_device_login(_context, _body, _opts),
    do: {:error, :invalid_device_code_response}

  defp normalize_poll_success(%{} = body) do
    cond do
      is_binary(body["authorization_code"]) and body["authorization_code"] != "" ->
        {:ok,
         %{
           authorization_code: body["authorization_code"],
           code_verifier: body["code_verifier"]
         }}

      is_binary(body["access_token"]) and body["access_token"] != "" ->
        {:ok,
         %{
           access_token: body["access_token"],
           refresh_token: body["refresh_token"],
           id_token: body["id_token"]
         }}

      true ->
        {:error, :invalid_device_code_poll_response}
    end
  end

  defp normalize_poll_success(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, %{} = decoded} -> normalize_poll_success(decoded)
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_poll_success(_), do: {:error, :invalid_device_code_poll_response}

  defp normalize_poll_error(%{} = body, interval_ms) do
    case body["error"] || body[:error] do
      error when error in ["authorization_pending", "pending"] ->
        {:retry, interval_ms}

      "slow_down" ->
        {:retry, min(interval_ms * 2, Defaults.oauth_device_code_max_poll_interval_ms())}

      error when error in ["expired_token", "expired"] ->
        {:error, :device_code_expired}

      error when error in ["access_denied", "authorization_denied"] ->
        {:error, :device_code_denied}

      _ ->
        {:error, {:device_code_poll_failed, body}}
    end
  end

  defp normalize_poll_error(body, interval_ms) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, %{} = decoded} -> normalize_poll_error(decoded, interval_ms)
      {:error, _} -> {:retry, interval_ms}
    end
  end

  defp normalize_poll_error(_body, interval_ms), do: {:retry, interval_ms}

  defp exchange_and_persist(%Session.PendingDeviceLogin{} = pending, code, verifier) do
    pkce = %Codex.OAuth.PKCE{verifier: verifier, challenge: "", method: "S256"}

    browser_pending = %Session.PendingLogin{
      provider: :openai_chatgpt,
      flow: :device_code,
      storage: pending.storage,
      context: pending.context,
      authorize_url: pending.verification_url,
      state: "",
      pkce: pkce,
      redirect_uri: pending.context.provider.issuer <> "/deviceauth/callback",
      loopback_server: nil,
      warnings: []
    }

    case BrowserCode.await_exchange(browser_pending, code) do
      {:ok, response} -> persist_session_from_tokens(pending, response)
      {:error, _} = error -> error
    end
  end

  defp persist_session_from_tokens(%Session.PendingDeviceLogin{} = pending, response) do
    record =
      Store.build_record(
        auth_mode: :chatgpt,
        openai_api_key: response.access_token,
        access_token: response.access_token,
        refresh_token: response.refresh_token,
        id_token: response.id_token,
        account_id: response[:account_id],
        last_refresh: DateTime.utc_now()
      )

    case pending.storage do
      :memory ->
        case MemoryTokenStore.start_link(
               record,
               pending.context,
               provider: :openai_chatgpt,
               flow: :device_code
             ) do
          {:ok, token_store} ->
            %Codex.OAuth.Session{} = session = MemoryTokenStore.fetch(token_store)
            {:ok, %{session | token_store: token_store}}

          {:error, _} = error ->
            error
        end

      :file ->
        FileTokenStore.persist(record, pending.context,
          provider: :openai_chatgpt,
          flow: :device_code
        )
    end
  end

  defp normalize_storage(:memory), do: :memory
  defp normalize_storage(_), do: :file

  defp normalize_interval(value) when is_integer(value), do: value

  defp normalize_interval(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} -> parsed
      _ -> 5
    end
  end

  defp normalize_interval(_), do: 5

  defp expires_at(value) when is_integer(value),
    do: DateTime.utc_now() |> DateTime.add(value, :second)

  defp expires_at(_), do: nil

  defp fetch_device_code(body) do
    body
    |> fetch_any([:device_auth_id, "device_auth_id", :device_code, "device_code"])
    |> require_string()
  end

  defp fetch_user_code(body) do
    body
    |> fetch_any([:user_code, "user_code", :usercode, "usercode"])
    |> require_string()
  end

  defp build_pending_device_login(context, body, opts, device_code, user_code) do
    %Session.PendingDeviceLogin{
      provider: :openai_chatgpt,
      flow: :device_code,
      storage: normalize_storage(Keyword.get(opts, :storage, context.storage)),
      context: context,
      verification_url: verification_url(body, context),
      user_code: user_code,
      device_code: device_code,
      interval_ms: interval_ms(body),
      expires_at: expires_at(body["expires_in"]),
      warnings: []
    }
  end

  defp verification_url(body, context) do
    fetch_any(body, [
      :verification_uri_complete,
      "verification_uri_complete",
      :verification_uri,
      "verification_uri"
    ]) ||
      context.provider.device_verification_url
  end

  defp interval_ms(body) do
    body["interval"]
    |> normalize_interval()
    |> Kernel.max(1)
    |> Kernel.*(1_000)
  end

  defp fetch_any(map, keys) do
    Enum.find_value(keys, &Map.get(map, &1))
  end

  defp require_string(value) when is_binary(value) and value != "", do: {:ok, value}
  defp require_string(_value), do: :error
end
