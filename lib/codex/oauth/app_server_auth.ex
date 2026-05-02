defmodule Codex.OAuth.AppServerAuth do
  @moduledoc false

  alias Codex.AppServer.Account
  alias Codex.OAuth
  alias Codex.OAuth.AppServerRefreshResponder
  alias Codex.OAuth.Context
  alias Codex.OAuth.Session
  alias Codex.OAuth.TokenStore.Memory, as: MemoryTokenStore

  @child_option_keys [:cwd, :process_env, :env]
  @app_server_option_keys [:mode, :storage, :auto_refresh]

  @type storage :: :auto | :file | :memory

  @type normalized_options :: %{
          enabled?: boolean(),
          storage: storage(),
          auto_refresh?: boolean(),
          oauth_opts: keyword()
        }
  @type ensure_before_remote_connect_error ::
          :experimental_api_required_for_memory_oauth
          | :remote_persistent_oauth_not_supported
          | {:invalid_oauth_options, term()}
          | {:invalid_oauth_storage, term()}
          | {:unsupported_oauth_mode, term()}

  @spec ensure_before_connect(keyword()) :: :ok | {:error, term()}
  def ensure_before_connect(connect_opts) when is_list(connect_opts) do
    with {:ok, oauth} <- normalize_options(connect_opts) do
      maybe_ensure_persistent_login(oauth, connect_opts)
    end
  end

  @spec ensure_before_remote_connect(keyword()) ::
          :ok | {:error, ensure_before_remote_connect_error()}
  def ensure_before_remote_connect(connect_opts) when is_list(connect_opts) do
    with {:ok, oauth} <- normalize_options(connect_opts) do
      case oauth do
        %{enabled?: false} ->
          :ok

        %{storage: :memory} ->
          :ok

        %{storage: storage} when storage in [:auto, :file] ->
          {:error, :remote_persistent_oauth_not_supported}
      end
    end
  end

  @spec authenticate_connection(pid(), keyword()) :: :ok | {:error, term()}
  def authenticate_connection(conn, connect_opts)
      when is_pid(conn) and is_list(connect_opts) do
    with {:ok, oauth} <- normalize_options(connect_opts) do
      maybe_authenticate_memory_connection(conn, oauth, connect_opts)
    end
  end

  @spec authenticate_remote_connection(pid(), keyword()) :: :ok | {:error, term()}
  def authenticate_remote_connection(conn, connect_opts)
      when is_pid(conn) and is_list(connect_opts) do
    with {:ok, oauth} <- normalize_options(connect_opts) do
      maybe_authenticate_memory_connection(conn, oauth, connect_opts)
    end
  end

  defp maybe_ensure_persistent_login(%{enabled?: false}, _connect_opts), do: :ok
  defp maybe_ensure_persistent_login(%{storage: :memory}, _connect_opts), do: :ok

  defp maybe_ensure_persistent_login(%{oauth_opts: oauth_opts}, connect_opts) do
    case OAuth.login_session(oauth_runtime_opts(oauth_opts, connect_opts, storage: :file)) do
      {:ok, _session, _warnings} -> :ok
      {:error, _} = error -> error
    end
  end

  defp maybe_authenticate_memory_connection(_conn, %{enabled?: false}, _connect_opts), do: :ok

  defp maybe_authenticate_memory_connection(_conn, %{storage: storage}, _connect_opts)
       when storage in [:auto, :file],
       do: :ok

  defp maybe_authenticate_memory_connection(conn, oauth, connect_opts) do
    case external_session(oauth.oauth_opts, connect_opts) do
      {:ok, session} ->
        authenticate_memory_session(conn, session, oauth, connect_opts)

      {:error, _} = error ->
        error
    end
  end

  defp maybe_start_refresh_responder(_conn, _session, %{auto_refresh?: false}), do: :ok

  defp maybe_start_refresh_responder(conn, session, %{auto_refresh?: true}) do
    case AppServerRefreshResponder.start(conn, session) do
      {:ok, _pid} -> :ok
      {:error, _} = error -> error
    end
  end

  defp external_session(oauth_opts, connect_opts) do
    runtime_opts = oauth_runtime_opts(oauth_opts, connect_opts, storage: :memory)

    case Context.resolve(runtime_opts) do
      {:ok, context} ->
        load_external_session(context, runtime_opts)

      {:error, _} = error ->
        error
    end
  end

  defp force_memory_login(runtime_opts) do
    runtime_opts =
      runtime_opts
      |> Keyword.put(:storage, :memory)
      |> Keyword.put(:ignore_stored_session?, true)

    case OAuth.login_session(runtime_opts) do
      {:ok, %Session{} = session, _warnings} -> {:ok, session}
      {:error, _} = error -> error
    end
  end

  defp materialize_existing_session(
         %Session{
           auth_record: %{auth_mode: auth_mode, tokens: %{access_token: access_token} = _tokens},
           token_store: token_store,
           persisted?: false,
           storage: :memory
         } = session
       )
       when auth_mode in [:chatgpt, :chatgpt_auth_tokens] and is_binary(access_token) and
              access_token != "" and is_pid(token_store) do
    case login_params(session) do
      {:ok, _params} -> {:ok, session}
      {:error, _} = error -> error
    end
  end

  defp materialize_existing_session(%Session{auth_record: %{auth_mode: auth_mode}} = session)
       when auth_mode in [:chatgpt, :chatgpt_auth_tokens] do
    with {:ok, _params} <- login_params(session) do
      case MemoryTokenStore.start_link(
             session.auth_record,
             session.context,
             provider: session.provider,
             flow: session.flow
           ) do
        {:ok, token_store} ->
          %Session{} = refreshed_session = MemoryTokenStore.fetch(token_store)
          {:ok, %{refreshed_session | token_store: token_store}}

        {:error, _} = error ->
          error
      end
    end
  end

  defp materialize_existing_session(%Session{}), do: {:error, :unsupported_auth_mode}

  defp login_params(%Session{} = session) do
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
         |> Map.put("type", "chatgptAuthTokens")
         |> Map.put("accessToken", access_token)
         |> Map.put("chatgptAccountId", account_id)
         |> maybe_put("chatgptPlanType", tokens.plan_type)}
    end
  end

  defp normalize_options(connect_opts) do
    case Keyword.fetch(connect_opts, :oauth) do
      :error ->
        {:ok, %{enabled?: false, storage: :auto, auto_refresh?: false, oauth_opts: []}}

      {:ok, oauth_opts} when is_list(oauth_opts) ->
        mode = Keyword.get(oauth_opts, :mode, :auto)
        storage = normalize_storage(Keyword.get(oauth_opts, :storage, :auto))

        cond do
          mode != :auto ->
            {:error, {:unsupported_oauth_mode, mode}}

          storage == :invalid ->
            {:error, {:invalid_oauth_storage, Keyword.get(oauth_opts, :storage, :auto)}}

          storage == :memory and Keyword.get(connect_opts, :experimental_api, false) != true ->
            {:error, :experimental_api_required_for_memory_oauth}

          true ->
            {:ok,
             %{
               enabled?: true,
               storage: storage,
               auto_refresh?: Keyword.get(oauth_opts, :auto_refresh, true),
               oauth_opts: Keyword.drop(oauth_opts, @app_server_option_keys)
             }}
        end

      {:ok, other} ->
        {:error, {:invalid_oauth_options, other}}
    end
  end

  defp oauth_runtime_opts(oauth_opts, connect_opts, overrides) do
    oauth_opts
    |> Keyword.merge(overrides)
    |> merge_child_option(connect_opts, :cwd)
    |> merge_child_option(connect_opts, :process_env)
    |> merge_child_option(connect_opts, :env)
  end

  defp child_context_opts(connect_opts) do
    Enum.reduce(@child_option_keys, [], fn key, acc ->
      case Keyword.fetch(connect_opts, key) do
        {:ok, value} -> Keyword.put(acc, key, value)
        :error -> acc
      end
    end)
  end

  defp merge_child_option(opts, connect_opts, key) do
    case Keyword.fetch(connect_opts, key) do
      {:ok, value} -> Keyword.put(opts, key, value)
      :error -> opts
    end
  end

  defp normalize_storage(storage) when storage in [:auto, :file, :memory], do: storage
  defp normalize_storage(_storage), do: :invalid

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp authenticate_memory_session(conn, session, oauth, connect_opts) do
    with {:ok, params} <- login_params(session),
         {:ok, _response} <- Account.login_start(conn, params, child_context_opts(connect_opts)) do
      maybe_start_refresh_responder(conn, session, oauth)
    end
  end

  defp load_external_session(context, runtime_opts) do
    case OAuth.load_session(context, runtime_opts) do
      {:ok, %Session{} = session} ->
        maybe_materialize_existing_session(session, runtime_opts)

      {:ok, nil} ->
        force_memory_login(runtime_opts)

      {:error, _} = error ->
        error
    end
  end

  defp maybe_materialize_existing_session(session, runtime_opts) do
    case materialize_existing_session(session) do
      {:ok, materialized} -> {:ok, materialized}
      {:error, :unsupported_auth_mode} -> force_memory_login(runtime_opts)
      {:error, :missing_chatgpt_account_id} -> force_memory_login(runtime_opts)
      {:error, :missing_access_token} -> force_memory_login(runtime_opts)
      {:error, _} = error -> error
    end
  end
end
