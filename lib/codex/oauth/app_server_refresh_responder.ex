defmodule Codex.OAuth.AppServerRefreshResponder do
  @moduledoc false

  use GenServer

  alias Codex.AppServer.Connection
  alias Codex.OAuth
  alias Codex.OAuth.Session
  alias Codex.OAuth.TokenStore.Memory, as: MemoryTokenStore

  @refresh_method "account/chatgptAuthTokens/refresh"
  @json_rpc_internal_error -32_000

  defmodule State do
    @moduledoc false

    defstruct [:conn, :conn_ref, :session]
  end

  @spec start(pid(), Session.t(), keyword()) :: GenServer.on_start()
  def start(conn, %Session{} = session, opts \\ [])
      when is_pid(conn) and is_list(opts) do
    GenServer.start(__MODULE__, {conn, session})
  end

  @impl true
  def init({conn, %Session{} = session}) do
    Process.flag(:trap_exit, true)

    case Connection.subscribe(conn, methods: [@refresh_method]) do
      :ok ->
        {:ok,
         %State{
           conn: conn,
           conn_ref: Process.monitor(conn),
           session: session
         }}

      {:error, _} = error ->
        {:stop, error}
    end
  end

  @impl true
  def handle_info({:codex_request, id, @refresh_method, params}, %State{} = state) do
    case refresh_response(state.session, params || %{}) do
      {:ok, refreshed_session, result} ->
        case Connection.respond(state.conn, id, result) do
          :ok ->
            {:noreply, cache_session(state, refreshed_session)}

          {:error, reason} ->
            {:stop, reason, state}
        end

      {:error, reason} ->
        message = error_message(reason)
        _ = Connection.respond_error(state.conn, id, @json_rpc_internal_error, message)
        {:noreply, state}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %State{conn_ref: ref} = state) do
    {:stop, :normal, state}
  end

  def handle_info(_message, %State{} = state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, %State{conn: conn}) do
    _ = Connection.unsubscribe(conn)
    :ok
  end

  defp refresh_response(%Session{} = session, params) do
    previous_account_id =
      Map.get(params, "previousAccountId") || Map.get(params, "previous_account_id")

    with {:ok, refreshed_session} <- OAuth.refresh_session(session, persist?: false),
         :ok <- validate_previous_account_id(refreshed_session, previous_account_id),
         {:ok, result} <- result_payload(refreshed_session) do
      {:ok, refreshed_session, result}
    end
  end

  defp validate_previous_account_id(_session, nil), do: :ok

  defp validate_previous_account_id(%Session{} = session, previous_account_id)
       when is_binary(previous_account_id) and previous_account_id != "" do
    tokens = session.auth_record.tokens
    refreshed_account_id = tokens && (tokens.chatgpt_account_id || tokens.account_id)

    if refreshed_account_id == previous_account_id do
      :ok
    else
      {:error, :previous_account_id_mismatch}
    end
  end

  defp validate_previous_account_id(_session, _previous_account_id), do: :ok

  defp result_payload(%Session{} = session) do
    tokens = session.auth_record.tokens
    access_token = tokens && tokens.access_token
    account_id = tokens && (tokens.chatgpt_account_id || tokens.account_id)

    cond do
      not (is_binary(access_token) and access_token != "") ->
        {:error, :missing_access_token}

      not (is_binary(account_id) and account_id != "") ->
        {:error, :missing_chatgpt_account_id}

      true ->
        {:ok,
         %{}
         |> Map.put("accessToken", access_token)
         |> Map.put("chatgptAccountId", account_id)
         |> maybe_put("chatgptPlanType", tokens.plan_type)}
    end
  end

  defp cache_session(%State{} = state, %Session{} = refreshed_session) do
    if is_pid(refreshed_session.token_store) do
      :ok = MemoryTokenStore.put(refreshed_session.token_store, refreshed_session)
    end

    %State{state | session: refreshed_session}
  end

  defp error_message(:previous_account_id_mismatch) do
    "refreshed ChatGPT account did not match the previous account"
  end

  defp error_message(:missing_access_token), do: "refreshed ChatGPT access token was missing"
  defp error_message(:missing_chatgpt_account_id), do: "refreshed ChatGPT account id was missing"
  defp error_message(:missing_refresh_token), do: "ChatGPT refresh token is unavailable"
  defp error_message(:missing_tokens), do: "ChatGPT auth tokens are unavailable"

  defp error_message({:refresh_failed, _status, _body}),
    do: "failed to refresh ChatGPT auth tokens"

  defp error_message(_reason), do: "failed to refresh ChatGPT auth tokens"

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
