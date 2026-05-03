defmodule Codex.AppServer do
  @moduledoc """
  App-server transport for stateful, bidirectional communication with Codex.
  """

  alias Codex.AppServer.Connection
  alias Codex.AppServer.Params
  alias Codex.AppServer.RemoteConnection
  alias Codex.AppServer.Supervisor, as: ConnectionSupervisor
  alias Codex.Config.Defaults
  alias Codex.GovernedAuthority
  alias Codex.Models
  alias Codex.OAuth.AppServerAuth
  alias Codex.Options
  alias Codex.Protocol.Plugin
  alias Codex.Runtime.Env, as: RuntimeEnv

  @type connection :: pid()

  @typedoc """
  Options for launching and initializing a managed `codex app-server` child process.

  `cwd` and `process_env` / `env` apply to the child process itself. Per-thread working
  directories still belong on `thread/start`, `thread/resume`, or `Codex.Thread.Options`.
  """
  @type connect_opts :: [
          init_timeout_ms: pos_integer(),
          client_name: String.t(),
          client_title: String.t(),
          client_version: String.t(),
          experimental_api: boolean(),
          execution_surface: CliSubprocessCore.ExecutionSurface.t() | map() | keyword(),
          cwd: String.t(),
          process_env: map() | keyword(),
          env: map() | keyword(),
          oauth: keyword()
        ]

  @type connect_remote_opts :: [
          init_timeout_ms: pos_integer(),
          client_name: String.t(),
          client_title: String.t(),
          client_version: String.t(),
          experimental_api: boolean(),
          auth_token: String.t(),
          auth_token_env: String.t(),
          governed_authority: map() | keyword(),
          cwd: String.t(),
          process_env: map() | keyword(),
          env: map() | keyword(),
          oauth: keyword()
        ]

  @default_init_timeout_ms Defaults.app_server_init_timeout_ms()

  @doc """
  Starts a supervised `codex app-server` subprocess and completes the `initialize` handshake.

  Use `cwd` and `process_env` (or the `env` alias) when the app-server child must run with an
  isolated working directory or `CODEX_HOME` without mutating the caller's shell environment.
  """
  @spec connect(Options.t(), connect_opts()) :: {:ok, connection()} | {:error, term()}
  def connect(%Options{} = codex_opts, opts \\ []) do
    init_timeout_ms = Keyword.get(opts, :init_timeout_ms, @default_init_timeout_ms)

    with {:ok, _pid} <- ensure_connection_supervisor(),
         :ok <- AppServerAuth.ensure_before_connect(opts),
         {:ok, conn} <- start_connection(codex_opts, opts),
         {:ok, ^conn} <- await_connection_ready(conn, init_timeout_ms) do
      authenticate_connection(conn, opts)
    end
  end

  @doc """
  Connects to a remote websocket-backed app-server endpoint and completes the
  `initialize` handshake.
  """
  @spec connect_remote(String.t(), connect_remote_opts()) ::
          {:ok, connection()} | {:error, term()}
  def connect_remote(websocket_url, opts \\ [])
      when is_binary(websocket_url) and is_list(opts) do
    init_timeout_ms = Keyword.get(opts, :init_timeout_ms, @default_init_timeout_ms)

    with {:ok, _pid} <- ensure_connection_supervisor(),
         {:ok, opts} <- resolve_remote_auth_token(opts),
         :ok <- validate_remote_auth_transport(websocket_url, Keyword.get(opts, :auth_token)),
         :ok <- AppServerAuth.ensure_before_remote_connect(opts),
         {:ok, conn} <- start_remote_connection(websocket_url, opts),
         {:ok, ^conn} <- await_connection_ready(conn, init_timeout_ms) do
      authenticate_remote_connection(conn, opts)
    end
  end

  defp start_connection(codex_opts, opts) do
    child_spec =
      {Connection, {codex_opts, opts}}
      |> Supervisor.child_spec(restart: :temporary)

    DynamicSupervisor.start_child(ConnectionSupervisor, child_spec)
  end

  defp start_remote_connection(websocket_url, opts) do
    child_spec =
      {RemoteConnection, {websocket_url, opts}}
      |> Supervisor.child_spec(restart: :temporary)

    DynamicSupervisor.start_child(ConnectionSupervisor, child_spec)
  end

  defp await_connection_ready(conn, timeout) do
    case Connection.await_ready(conn, timeout) do
      :ok ->
        {:ok, conn}

      {:error, _reason} = error ->
        _ = DynamicSupervisor.terminate_child(ConnectionSupervisor, conn)
        error
    end
  end

  defp ensure_connection_supervisor do
    with :ok <- ensure_application_started(),
         pid when is_pid(pid) <- Process.whereis(ConnectionSupervisor) do
      {:ok, pid}
    else
      nil -> {:error, :supervisor_unavailable}
      {:error, _} = error -> error
    end
  catch
    :exit, reason -> {:error, reason}
  end

  defp ensure_application_started do
    case Application.ensure_all_started(:codex_sdk) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @spec disconnect(connection()) :: :ok
  def disconnect(conn) when is_pid(conn) do
    _ = safe_terminate_child(conn)
    :ok
  end

  defp safe_terminate_child(conn) do
    DynamicSupervisor.terminate_child(ConnectionSupervisor, conn)
  catch
    :exit, :normal -> :ok
    :exit, {:normal, _} -> :ok
    :exit, _ -> :ok
  end

  defp maybe_terminate_connection(conn), do: safe_terminate_child(conn)

  defp authenticate_connection(conn, opts) do
    case AppServerAuth.authenticate_connection(conn, opts) do
      :ok ->
        {:ok, conn}

      {:error, _reason} = error ->
        maybe_terminate_connection(conn)
        error
    end
  end

  defp authenticate_remote_connection(conn, opts) do
    case AppServerAuth.authenticate_remote_connection(conn, opts) do
      :ok ->
        {:ok, conn}

      {:error, _reason} = error ->
        maybe_terminate_connection(conn)
        error
    end
  end

  @spec alive?(connection()) :: boolean()
  def alive?(conn) when is_pid(conn), do: Process.alive?(conn)

  @spec subscribe(connection(), keyword()) :: :ok | {:error, term()}
  def subscribe(conn, opts \\ []) when is_pid(conn) do
    Connection.subscribe(conn, opts)
  end

  @spec unsubscribe(connection()) :: :ok
  def unsubscribe(conn) when is_pid(conn) do
    Connection.unsubscribe(conn)
  end

  @spec respond(connection(), String.t() | integer(), map()) :: :ok | {:error, term()}
  def respond(conn, id, result) when is_pid(conn) and (is_integer(id) or is_binary(id)) do
    Connection.respond(conn, id, result)
  end

  @doc """
  Sends an app-server request and parses the response with a typed response module.

  When `params` is a typed params struct, the struct module's `to_map/1` is used
  for wire encoding. For the typed plugin APIs, plain maps and keywords are
  normalized through the matching `Codex.Protocol.Plugin.*Params` module before
  the request is sent.
  """
  @spec request_typed(
          connection(),
          String.t(),
          map() | keyword() | struct() | nil,
          module(),
          keyword()
        ) :: {:ok, struct()} | {:error, term()}
  def request_typed(conn, method, params, response_module, opts \\ [])
      when is_pid(conn) and is_binary(method) and is_atom(response_module) and is_list(opts) do
    with {:ok, encoded_params} <- encode_typed_request_params(method, params),
         {:ok, result} <- Connection.request(conn, method, encoded_params, opts) do
      parse_typed_response(response_module, result)
    end
  end

  @spec thread_start(connection(), map() | keyword()) :: {:ok, map()} | {:error, term()}
  def thread_start(conn, params \\ %{}) when is_pid(conn) do
    params = Params.normalize_map(params)

    with {:ok, approval_policy} <-
           params
           |> fetch_any([:approval_policy, "approval_policy"])
           |> Params.ask_for_approval() do
      wire_params =
        %{}
        |> Params.put_optional("model", fetch_any(params, [:model, "model"]))
        |> Params.put_optional(
          "modelProvider",
          fetch_any(params, [:model_provider, "model_provider", :modelProvider, "modelProvider"])
        )
        |> Params.put_optional(
          "cwd",
          fetch_any(params, [:cwd, "cwd", :working_directory, "working_directory"])
        )
        |> Params.put_optional("approvalPolicy", approval_policy)
        |> Params.put_optional(
          "approvalsReviewer",
          params
          |> fetch_any([
            :approvals_reviewer,
            "approvals_reviewer",
            :approvalsReviewer,
            "approvalsReviewer"
          ])
          |> Params.approvals_reviewer()
        )
        |> Params.put_optional(
          "sandbox",
          params
          |> fetch_any([:sandbox, "sandbox"])
          |> Params.sandbox_mode()
        )
        |> Params.put_optional(
          "permissionProfile",
          fetch_any(params, [
            :permission_profile,
            "permission_profile",
            :permissionProfile,
            "permissionProfile"
          ])
        )
        |> Params.put_optional("config", fetch_any(params, [:config, "config"]))
        |> Params.put_optional(
          "baseInstructions",
          fetch_any(params, [:base_instructions, "base_instructions"])
        )
        |> Params.put_optional(
          "developerInstructions",
          fetch_any(params, [:developer_instructions, "developer_instructions"])
        )
        |> Params.put_optional(
          "personality",
          params
          |> fetch_any([:personality, "personality"])
          |> Params.personality()
        )
        |> Params.put_optional(
          "dynamicTools",
          fetch_any(params, [:dynamic_tools, "dynamic_tools", :dynamicTools, "dynamicTools"])
        )
        |> Params.put_optional("ephemeral", fetch_any(params, [:ephemeral, "ephemeral"]))
        |> Params.put_optional(
          "sessionStartSource",
          params
          |> fetch_any([
            :session_start_source,
            "session_start_source",
            :sessionStartSource,
            "sessionStartSource"
          ])
          |> Params.thread_start_source()
        )
        |> Params.put_optional(
          "serviceName",
          fetch_any(params, [:service_name, "service_name", :serviceName, "serviceName"])
        )
        |> Params.put_optional(
          "serviceTier",
          params
          |> fetch_any([:service_tier, "service_tier", :serviceTier, "serviceTier"])
          |> Params.service_tier()
        )
        |> Params.put_optional(
          "experimentalRawEvents",
          fetch_any(params, [:experimental_raw_events, "experimental_raw_events"])
        )
        |> Params.put_optional(
          "persistExtendedHistory",
          fetch_any(params, [
            :persist_extended_history,
            "persist_extended_history",
            :persistExtendedHistory,
            "persistExtendedHistory"
          ])
        )

      Connection.request(conn, "thread/start", wire_params, timeout_ms: 30_000)
    end
  end

  @spec thread_resume(connection(), String.t(), map() | keyword()) ::
          {:ok, map()} | {:error, term()}
  def thread_resume(conn, thread_id, params \\ %{}) when is_pid(conn) and is_binary(thread_id) do
    params = Params.normalize_map(params)

    with {:ok, approval_policy} <-
           params
           |> fetch_any([:approval_policy, "approval_policy"])
           |> Params.ask_for_approval() do
      wire_params =
        %{"threadId" => thread_id}
        |> Params.put_optional("history", fetch_any(params, [:history, "history"]))
        |> Params.put_optional("path", fetch_any(params, [:path, "path"]))
        |> Params.put_optional("model", fetch_any(params, [:model, "model"]))
        |> Params.put_optional(
          "modelProvider",
          fetch_any(params, [:model_provider, "model_provider", :modelProvider, "modelProvider"])
        )
        |> Params.put_optional(
          "cwd",
          fetch_any(params, [:cwd, "cwd", :working_directory, "working_directory"])
        )
        |> Params.put_optional("approvalPolicy", approval_policy)
        |> Params.put_optional(
          "approvalsReviewer",
          params
          |> fetch_any([
            :approvals_reviewer,
            "approvals_reviewer",
            :approvalsReviewer,
            "approvalsReviewer"
          ])
          |> Params.approvals_reviewer()
        )
        |> Params.put_optional(
          "sandbox",
          params
          |> fetch_any([:sandbox, "sandbox"])
          |> Params.sandbox_mode()
        )
        |> Params.put_optional(
          "permissionProfile",
          fetch_any(params, [
            :permission_profile,
            "permission_profile",
            :permissionProfile,
            "permissionProfile"
          ])
        )
        |> Params.put_optional("config", fetch_any(params, [:config, "config"]))
        |> Params.put_optional(
          "baseInstructions",
          fetch_any(params, [:base_instructions, "base_instructions"])
        )
        |> Params.put_optional(
          "developerInstructions",
          fetch_any(params, [:developer_instructions, "developer_instructions"])
        )
        |> Params.put_optional(
          "personality",
          params
          |> fetch_any([:personality, "personality"])
          |> Params.personality()
        )
        |> Params.put_optional(
          "dynamicTools",
          fetch_any(params, [:dynamic_tools, "dynamic_tools", :dynamicTools, "dynamicTools"])
        )
        |> Params.put_optional(
          "serviceTier",
          params
          |> fetch_any([:service_tier, "service_tier", :serviceTier, "serviceTier"])
          |> Params.service_tier()
        )
        |> Params.put_optional(
          "experimentalRawEvents",
          fetch_any(params, [:experimental_raw_events, "experimental_raw_events"])
        )
        |> Params.put_optional(
          "excludeTurns",
          fetch_any(params, [:exclude_turns, "exclude_turns", :excludeTurns, "excludeTurns"])
        )
        |> Params.put_optional(
          "persistExtendedHistory",
          fetch_any(params, [
            :persist_extended_history,
            "persist_extended_history",
            :persistExtendedHistory,
            "persistExtendedHistory"
          ])
        )

      Connection.request(conn, "thread/resume", wire_params, timeout_ms: 30_000)
    end
  end

  @spec thread_list(connection(), keyword()) :: {:ok, map()} | {:error, term()}
  def thread_list(conn, opts \\ []) when is_pid(conn) and is_list(opts) do
    timeout_ms = Keyword.get(opts, :timeout_ms, 30_000)

    wire_params =
      %{}
      |> Params.put_optional("cursor", Keyword.get(opts, :cursor))
      |> Params.put_optional("limit", Keyword.get(opts, :limit))
      |> Params.put_optional("sortKey", Params.thread_sort_key(Keyword.get(opts, :sort_key)))
      |> Params.put_optional(
        "sortDirection",
        Params.sort_direction(Keyword.get(opts, :sort_direction))
      )
      |> Params.put_optional("modelProviders", Keyword.get(opts, :model_providers))
      |> Params.put_optional(
        "sourceKinds",
        normalize_thread_source_kinds(Keyword.get(opts, :source_kinds))
      )
      |> Params.put_optional("archived", Keyword.get(opts, :archived))
      |> Params.put_optional("cwd", Keyword.get(opts, :cwd))
      |> Params.put_optional(
        "useStateDbOnly",
        normalize_true(Keyword.get(opts, :use_state_db_only))
      )
      |> Params.put_optional("searchTerm", Keyword.get(opts, :search_term))

    Connection.request(conn, "thread/list", wire_params, timeout_ms: timeout_ms)
  end

  @spec thread_archive(connection(), String.t()) :: :ok | {:error, term()}
  def thread_archive(conn, thread_id) when is_pid(conn) and is_binary(thread_id) do
    case Connection.request(conn, "thread/archive", %{"threadId" => thread_id},
           timeout_ms: 30_000
         ) do
      {:ok, _} -> :ok
      {:error, _} = error -> error
    end
  end

  @spec thread_unsubscribe(connection(), String.t()) :: {:ok, map()} | {:error, term()}
  def thread_unsubscribe(conn, thread_id) when is_pid(conn) and is_binary(thread_id) do
    Connection.request(conn, "thread/unsubscribe", %{"threadId" => thread_id}, timeout_ms: 30_000)
  end

  @spec thread_fork(connection(), String.t(), map() | keyword()) ::
          {:ok, map()} | {:error, term()}
  def thread_fork(conn, thread_id, params \\ %{})
      when is_pid(conn) and is_binary(thread_id) do
    params = Params.normalize_map(params)

    with {:ok, approval_policy} <-
           params
           |> fetch_any([:approval_policy, "approval_policy"])
           |> Params.ask_for_approval() do
      wire_params =
        %{"threadId" => thread_id}
        |> Params.put_optional("path", fetch_any(params, [:path, "path"]))
        |> Params.put_optional("model", fetch_any(params, [:model, "model"]))
        |> Params.put_optional(
          "modelProvider",
          fetch_any(params, [:model_provider, "model_provider", :modelProvider, "modelProvider"])
        )
        |> Params.put_optional(
          "cwd",
          fetch_any(params, [:cwd, "cwd", :working_directory, "working_directory"])
        )
        |> Params.put_optional("approvalPolicy", approval_policy)
        |> Params.put_optional(
          "approvalsReviewer",
          params
          |> fetch_any([
            :approvals_reviewer,
            "approvals_reviewer",
            :approvalsReviewer,
            "approvalsReviewer"
          ])
          |> Params.approvals_reviewer()
        )
        |> Params.put_optional(
          "sandbox",
          params
          |> fetch_any([:sandbox, "sandbox"])
          |> Params.sandbox_mode()
        )
        |> Params.put_optional(
          "permissionProfile",
          fetch_any(params, [
            :permission_profile,
            "permission_profile",
            :permissionProfile,
            "permissionProfile"
          ])
        )
        |> Params.put_optional("config", fetch_any(params, [:config, "config"]))
        |> Params.put_optional(
          "baseInstructions",
          fetch_any(params, [:base_instructions, "base_instructions"])
        )
        |> Params.put_optional(
          "developerInstructions",
          fetch_any(params, [:developer_instructions, "developer_instructions"])
        )
        |> Params.put_optional("ephemeral", fetch_any(params, [:ephemeral, "ephemeral"]))
        |> Params.put_optional(
          "serviceTier",
          params
          |> fetch_any([:service_tier, "service_tier", :serviceTier, "serviceTier"])
          |> Params.service_tier()
        )
        |> Params.put_optional(
          "excludeTurns",
          fetch_any(params, [:exclude_turns, "exclude_turns", :excludeTurns, "excludeTurns"])
        )
        |> Params.put_optional(
          "persistExtendedHistory",
          fetch_any(params, [
            :persist_extended_history,
            "persist_extended_history",
            :persistExtendedHistory,
            "persistExtendedHistory"
          ])
        )

      Connection.request(conn, "thread/fork", wire_params, timeout_ms: 30_000)
    end
  end

  @spec thread_rollback(connection(), String.t(), pos_integer()) ::
          {:ok, map()} | {:error, term()}
  def thread_rollback(conn, thread_id, num_turns)
      when is_pid(conn) and is_binary(thread_id) and is_integer(num_turns) and num_turns >= 1 do
    params = %{"threadId" => thread_id, "numTurns" => num_turns}
    Connection.request(conn, "thread/rollback", params, timeout_ms: 30_000)
  end

  def thread_rollback(_conn, _thread_id, num_turns) do
    {:error, {:invalid_num_turns, num_turns}}
  end

  @spec thread_read(connection(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def thread_read(conn, thread_id, opts \\ [])
      when is_pid(conn) and is_binary(thread_id) and is_list(opts) do
    timeout_ms = Keyword.get(opts, :timeout_ms, 30_000)

    params = %{
      "threadId" => thread_id,
      "includeTurns" => !!Keyword.get(opts, :include_turns, false)
    }

    Connection.request(conn, "thread/read", params, timeout_ms: timeout_ms)
  end

  @spec thread_turns_list(connection(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def thread_turns_list(conn, thread_id, opts \\ [])
      when is_pid(conn) and is_binary(thread_id) and is_list(opts) do
    timeout_ms = Keyword.get(opts, :timeout_ms, 30_000)

    params =
      %{"threadId" => thread_id}
      |> Params.put_optional("cursor", Keyword.get(opts, :cursor))
      |> Params.put_optional("limit", Keyword.get(opts, :limit))
      |> Params.put_optional(
        "sortDirection",
        Params.sort_direction(Keyword.get(opts, :sort_direction))
      )

    Connection.request(conn, "thread/turns/list", params, timeout_ms: timeout_ms)
  end

  @spec thread_inject_items(connection(), String.t(), [map()]) :: {:ok, map()} | {:error, term()}
  def thread_inject_items(conn, thread_id, items)
      when is_pid(conn) and is_binary(thread_id) and is_list(items) do
    Connection.request(
      conn,
      "thread/inject_items",
      %{"threadId" => thread_id, "items" => items},
      timeout_ms: 30_000
    )
  end

  @spec thread_loaded_list(connection(), keyword()) :: {:ok, map()} | {:error, term()}
  def thread_loaded_list(conn, opts \\ []) when is_pid(conn) and is_list(opts) do
    params =
      %{}
      |> Params.put_optional("cursor", Keyword.get(opts, :cursor))
      |> Params.put_optional("limit", Keyword.get(opts, :limit))

    Connection.request(conn, "thread/loaded/list", params, timeout_ms: 30_000)
  end

  @spec thread_name_set(connection(), String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def thread_name_set(conn, thread_id, name)
      when is_pid(conn) and is_binary(thread_id) and is_binary(name) do
    Connection.request(
      conn,
      "thread/name/set",
      %{"threadId" => thread_id, "name" => name},
      timeout_ms: 30_000
    )
  end

  @spec thread_metadata_update(connection(), String.t(), map() | keyword()) ::
          {:ok, map()} | {:error, term()}
  def thread_metadata_update(conn, thread_id, params)
      when is_pid(conn) and is_binary(thread_id) do
    params = Params.normalize_map(params)

    wire_params =
      %{"threadId" => thread_id}
      |> Params.put_optional(
        "gitInfo",
        params
        |> fetch_any([:git_info, "git_info", :gitInfo, "gitInfo"])
        |> Params.git_info_update()
      )

    Connection.request(conn, "thread/metadata/update", wire_params, timeout_ms: 30_000)
  end

  @spec thread_memory_mode_set(connection(), String.t(), atom() | String.t()) ::
          {:ok, map()} | {:error, term()}
  def thread_memory_mode_set(conn, thread_id, mode)
      when is_pid(conn) and is_binary(thread_id) do
    Connection.request(
      conn,
      "thread/memoryMode/set",
      %{"threadId" => thread_id, "mode" => Params.thread_memory_mode(mode)},
      timeout_ms: 30_000
    )
  end

  @spec thread_unarchive(connection(), String.t()) :: {:ok, map()} | {:error, term()}
  def thread_unarchive(conn, thread_id) when is_pid(conn) and is_binary(thread_id) do
    Connection.request(conn, "thread/unarchive", %{"threadId" => thread_id}, timeout_ms: 30_000)
  end

  @spec memory_reset(connection()) :: {:ok, map()} | {:error, term()}
  def memory_reset(conn) when is_pid(conn) do
    Connection.request(conn, "memory/reset", %{}, timeout_ms: 30_000)
  end

  @doc """
  Writes a skills config entry enabling or disabling a skill by path.
  """
  @spec skills_config_write(connection(), String.t(), boolean()) ::
          {:ok, map()} | {:error, term()}
  def skills_config_write(conn, path, enabled)
      when is_pid(conn) and is_binary(path) and is_boolean(enabled) do
    params = %{"path" => path, "enabled" => enabled}
    Connection.request(conn, "skills/config/write", params, timeout_ms: 30_000)
  end

  @doc """
  Reads config requirements enforced by the server (if any).
  """
  @spec config_requirements(connection()) :: {:ok, map()} | {:error, term()}
  def config_requirements(conn) when is_pid(conn) do
    Connection.request(conn, "configRequirements/read", %{}, timeout_ms: 10_000)
  end

  @doc """
  Lists collaboration mode presets (experimental).
  """
  @spec collaboration_mode_list(connection()) :: {:ok, map()} | {:error, term()}
  def collaboration_mode_list(conn) when is_pid(conn) do
    Connection.request(conn, "collaborationMode/list", %{}, timeout_ms: 30_000)
  end

  @doc """
  Lists available apps/connectors.
  """
  @spec apps_list(connection(), keyword()) :: {:ok, map()} | {:error, term()}
  def apps_list(conn, opts \\ []) when is_pid(conn) and is_list(opts) do
    params =
      %{}
      |> Params.put_optional("cursor", Keyword.get(opts, :cursor))
      |> Params.put_optional("limit", Keyword.get(opts, :limit))
      |> Params.put_optional("threadId", Keyword.get(opts, :thread_id))
      |> Params.put_optional("forceRefetch", normalize_true(Keyword.get(opts, :force_refetch)))

    Connection.request(conn, "app/list", params, timeout_ms: 30_000)
  end

  @doc """
  Starts server-side context compaction for a thread.
  """
  @spec thread_compact(connection(), String.t()) :: {:ok, map()} | {:error, term()}
  def thread_compact(conn, thread_id) when is_pid(conn) and is_binary(thread_id) do
    Connection.request(conn, "thread/compact/start", %{"threadId" => thread_id},
      timeout_ms: 30_000
    )
  end

  @doc """
  Explicit alias for `thread_compact/2`.
  """
  @spec thread_compact_start(connection(), String.t()) :: {:ok, map()} | {:error, term()}
  def thread_compact_start(conn, thread_id) when is_pid(conn) and is_binary(thread_id) do
    thread_compact(conn, thread_id)
  end

  @spec turn_start(connection(), String.t(), String.t() | [map()], keyword()) ::
          {:ok, map()} | {:error, term()}
  def turn_start(conn, thread_id, input, opts \\ [])
      when is_pid(conn) and is_binary(thread_id) and is_list(opts) do
    with {:ok, approval_policy} <-
           opts
           |> Keyword.get(:approval_policy)
           |> Params.ask_for_approval() do
      collaboration_mode =
        opts
        |> Keyword.get(:collaboration_mode)
        |> collaboration_mode_for_turn_start(Keyword.get(opts, :model))

      wire_params =
        %{
          "threadId" => thread_id,
          "input" => Params.user_input(input)
        }
        |> Params.put_optional("cwd", Keyword.get(opts, :cwd))
        |> Params.put_optional("approvalPolicy", approval_policy)
        |> Params.put_optional(
          "approvalsReviewer",
          opts
          |> Keyword.get(:approvals_reviewer)
          |> Params.approvals_reviewer()
        )
        |> Params.put_optional(
          "sandboxPolicy",
          opts |> Keyword.get(:sandbox_policy) |> Params.sandbox_policy()
        )
        |> Params.put_optional("permissionProfile", Keyword.get(opts, :permission_profile))
        |> Params.put_optional("model", Keyword.get(opts, :model))
        |> Params.put_optional(
          "effort",
          opts |> Keyword.get(:effort) |> Params.reasoning_effort()
        )
        |> Params.put_optional("summary", Keyword.get(opts, :summary))
        |> Params.put_optional(
          "personality",
          opts |> Keyword.get(:personality) |> Params.personality()
        )
        |> Params.put_optional("outputSchema", Keyword.get(opts, :output_schema))
        |> Params.put_optional(
          "collaborationMode",
          collaboration_mode
        )
        |> Params.put_optional(
          "responsesapiClientMetadata",
          Keyword.get(opts, :responsesapi_client_metadata)
        )
        |> Params.put_optional("environments", Keyword.get(opts, :environments))
        |> Params.put_optional(
          "serviceTier",
          opts |> Keyword.get(:service_tier) |> Params.service_tier()
        )

      Connection.request(conn, "turn/start", wire_params, timeout_ms: 300_000)
    end
  end

  @spec turn_steer(connection(), String.t(), String.t() | [map()], keyword()) ::
          {:ok, map()} | {:error, term()}
  def turn_steer(conn, thread_id, input, opts \\ [])
      when is_pid(conn) and is_binary(thread_id) and is_list(opts) do
    wire_params =
      %{
        "threadId" => thread_id,
        "input" => Params.user_input(input),
        "expectedTurnId" => Keyword.fetch!(opts, :expected_turn_id)
      }
      |> Params.put_optional(
        "responsesapiClientMetadata",
        Keyword.get(opts, :responsesapi_client_metadata)
      )

    Connection.request(conn, "turn/steer", wire_params, timeout_ms: 30_000)
  end

  defp collaboration_mode_for_turn_start(nil, _model), do: nil

  defp collaboration_mode_for_turn_start(mode, model) do
    default_model =
      case model do
        value when is_binary(value) and value != "" -> value
        _ -> Models.default_model()
      end

    mode
    |> Params.collaboration_mode()
    |> maybe_put_collaboration_default_model(default_model)
  end

  defp maybe_put_collaboration_default_model(%{"settings" => settings} = mode, default_model)
       when is_map(settings) and is_binary(default_model) and default_model != "" do
    if Map.has_key?(settings, "model") do
      mode
    else
      put_in(mode, ["settings", "model"], default_model)
    end
  end

  defp maybe_put_collaboration_default_model(mode, _default_model), do: mode

  @spec turn_interrupt(connection(), String.t(), String.t()) :: :ok | {:error, term()}
  def turn_interrupt(conn, thread_id, turn_id)
      when is_pid(conn) and is_binary(thread_id) and is_binary(turn_id) do
    params = %{"threadId" => thread_id, "turnId" => turn_id}

    case Connection.request(conn, "turn/interrupt", params, timeout_ms: 30_000) do
      {:ok, _} -> :ok
      {:error, _} = error -> error
    end
  end

  @spec thread_realtime_start(connection(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def thread_realtime_start(conn, thread_id, prompt, opts \\ [])
      when is_pid(conn) and is_binary(thread_id) and is_binary(prompt) and is_list(opts) do
    params =
      %{"threadId" => thread_id, "prompt" => prompt}
      |> Params.put_optional(
        "outputModality",
        opts
        |> Keyword.get(:output_modality, :audio)
        |> Params.realtime_output_modality()
      )
      |> Params.put_optional("sessionId", Keyword.get(opts, :session_id))

    Connection.request(conn, "thread/realtime/start", params, timeout_ms: 30_000)
  end

  @spec thread_realtime_append_audio(connection(), String.t(), map() | keyword()) ::
          {:ok, map()} | {:error, term()}
  def thread_realtime_append_audio(conn, thread_id, audio)
      when is_pid(conn) and is_binary(thread_id) do
    Connection.request(
      conn,
      "thread/realtime/appendAudio",
      %{"threadId" => thread_id, "audio" => Params.thread_realtime_audio_chunk(audio)},
      timeout_ms: 30_000
    )
  end

  @spec thread_realtime_append_text(connection(), String.t(), String.t()) ::
          {:ok, map()} | {:error, term()}
  def thread_realtime_append_text(conn, thread_id, text)
      when is_pid(conn) and is_binary(thread_id) and is_binary(text) do
    Connection.request(
      conn,
      "thread/realtime/appendText",
      %{"threadId" => thread_id, "text" => text},
      timeout_ms: 30_000
    )
  end

  @spec thread_realtime_stop(connection(), String.t()) :: {:ok, map()} | {:error, term()}
  def thread_realtime_stop(conn, thread_id) when is_pid(conn) and is_binary(thread_id) do
    Connection.request(conn, "thread/realtime/stop", %{"threadId" => thread_id},
      timeout_ms: 30_000
    )
  end

  @spec skills_list(connection(), keyword()) :: {:ok, map()} | {:error, term()}
  def skills_list(conn, opts \\ []) when is_pid(conn) and is_list(opts) do
    cwds = Keyword.get(opts, :cwds, [])

    force_reload =
      case Keyword.get(opts, :force_reload) do
        true -> true
        _ -> nil
      end

    params =
      %{}
      |> Params.put_optional("cwds", List.wrap(cwds))
      |> Params.put_optional("forceReload", force_reload)
      |> Params.put_optional(
        "perCwdExtraUserRoots",
        opts
        |> Keyword.get(:per_cwd_extra_user_roots)
        |> Params.per_cwd_extra_user_roots()
      )

    Connection.request(conn, "skills/list", params, timeout_ms: 30_000)
  end

  @spec skills_remote_list(connection(), keyword()) :: {:ok, map()} | {:error, term()}
  def skills_remote_list(conn, opts \\ []) when is_pid(conn) and is_list(opts) do
    params =
      %{}
      |> Params.put_optional(
        "hazelnutScope",
        opts |> Keyword.get(:hazelnut_scope) |> Params.hazelnut_scope()
      )
      |> Params.put_optional(
        "productSurface",
        opts |> Keyword.get(:product_surface) |> Params.product_surface()
      )
      |> Params.put_optional("enabled", Keyword.get(opts, :enabled))

    Connection.request(conn, "skills/remote/list", params, timeout_ms: 30_000)
  end

  @spec skills_remote_export(connection(), String.t()) :: {:ok, map()} | {:error, term()}
  def skills_remote_export(conn, hazelnut_id)
      when is_pid(conn) and is_binary(hazelnut_id) do
    Connection.request(
      conn,
      "skills/remote/export",
      %{"hazelnutId" => hazelnut_id},
      timeout_ms: 30_000
    )
  end

  @spec fuzzy_file_search(connection(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def fuzzy_file_search(conn, query, opts \\ [])
      when is_pid(conn) and is_binary(query) and is_list(opts) do
    roots = Keyword.get(opts, :roots, [])

    params =
      %{"query" => query, "roots" => List.wrap(roots)}
      |> Params.put_optional("cancellationToken", Keyword.get(opts, :cancellation_token))

    Connection.request(conn, "fuzzyFileSearch", params, timeout_ms: 30_000)
  end

  @spec fuzzy_file_search_session_start(connection(), String.t(), [String.t()]) ::
          {:ok, map()} | {:error, term()}
  def fuzzy_file_search_session_start(conn, session_id, roots)
      when is_pid(conn) and is_binary(session_id) and is_list(roots) do
    Connection.request(
      conn,
      "fuzzyFileSearch/sessionStart",
      %{"sessionId" => session_id, "roots" => roots},
      timeout_ms: 30_000
    )
  end

  @spec fuzzy_file_search_session_update(connection(), String.t(), String.t()) ::
          {:ok, map()} | {:error, term()}
  def fuzzy_file_search_session_update(conn, session_id, query)
      when is_pid(conn) and is_binary(session_id) and is_binary(query) do
    Connection.request(
      conn,
      "fuzzyFileSearch/sessionUpdate",
      %{"sessionId" => session_id, "query" => query},
      timeout_ms: 30_000
    )
  end

  @spec fuzzy_file_search_session_stop(connection(), String.t()) ::
          {:ok, map()} | {:error, term()}
  def fuzzy_file_search_session_stop(conn, session_id)
      when is_pid(conn) and is_binary(session_id) do
    Connection.request(
      conn,
      "fuzzyFileSearch/sessionStop",
      %{"sessionId" => session_id},
      timeout_ms: 30_000
    )
  end

  @spec model_list(connection(), keyword()) :: {:ok, map()} | {:error, term()}
  def model_list(conn, opts \\ []) when is_pid(conn) and is_list(opts) do
    params =
      %{}
      |> Params.put_optional("cursor", Keyword.get(opts, :cursor))
      |> Params.put_optional("limit", Keyword.get(opts, :limit))
      |> Params.put_optional("includeHidden", normalize_true(Keyword.get(opts, :include_hidden)))

    Connection.request(conn, "model/list", params, timeout_ms: 30_000)
  end

  @doc """
  Reads a file via the app-server filesystem API, returning a base64 payload.
  """
  @spec fs_read_file(connection(), String.t()) :: {:ok, map()} | {:error, term()}
  def fs_read_file(conn, path) when is_pid(conn) and is_binary(path) do
    Connection.request(conn, "fs/readFile", %{"path" => path}, timeout_ms: 30_000)
  end

  @doc """
  Writes base64-encoded file contents via the app-server filesystem API.
  """
  @spec fs_write_file(connection(), String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def fs_write_file(conn, path, data_base64)
      when is_pid(conn) and is_binary(path) and is_binary(data_base64) do
    Connection.request(
      conn,
      "fs/writeFile",
      %{"path" => path, "dataBase64" => data_base64},
      timeout_ms: 30_000
    )
  end

  @doc """
  Creates a directory via the app-server filesystem API.
  """
  @spec fs_create_directory(connection(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def fs_create_directory(conn, path, opts \\ [])
      when is_pid(conn) and is_binary(path) and is_list(opts) do
    params =
      %{"path" => path}
      |> Params.put_optional("recursive", Keyword.get(opts, :recursive))

    Connection.request(conn, "fs/createDirectory", params, timeout_ms: 30_000)
  end

  @doc """
  Fetches file or directory metadata via the app-server filesystem API.
  """
  @spec fs_get_metadata(connection(), String.t()) :: {:ok, map()} | {:error, term()}
  def fs_get_metadata(conn, path) when is_pid(conn) and is_binary(path) do
    Connection.request(conn, "fs/getMetadata", %{"path" => path}, timeout_ms: 30_000)
  end

  @doc """
  Lists directory entries via the app-server filesystem API.
  """
  @spec fs_read_directory(connection(), String.t()) :: {:ok, map()} | {:error, term()}
  def fs_read_directory(conn, path) when is_pid(conn) and is_binary(path) do
    Connection.request(conn, "fs/readDirectory", %{"path" => path}, timeout_ms: 30_000)
  end

  @doc """
  Removes a file or directory via the app-server filesystem API.
  """
  @spec fs_remove(connection(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def fs_remove(conn, path, opts \\ []) when is_pid(conn) and is_binary(path) and is_list(opts) do
    params =
      %{"path" => path}
      |> Params.put_optional("recursive", Keyword.get(opts, :recursive))
      |> Params.put_optional("force", Keyword.get(opts, :force))

    Connection.request(conn, "fs/remove", params, timeout_ms: 30_000)
  end

  @doc """
  Copies a file or directory via the app-server filesystem API.
  """
  @spec fs_copy(connection(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def fs_copy(conn, source_path, destination_path, opts \\ [])
      when is_pid(conn) and is_binary(source_path) and is_binary(destination_path) and
             is_list(opts) do
    params =
      %{"sourcePath" => source_path, "destinationPath" => destination_path}
      |> Params.put_optional("recursive", Keyword.get(opts, :recursive))

    Connection.request(conn, "fs/copy", params, timeout_ms: 30_000)
  end

  @doc """
  Starts filesystem change notifications for an absolute file or directory path.
  """
  @spec fs_watch(connection(), String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def fs_watch(conn, watch_id, path)
      when is_pid(conn) and is_binary(watch_id) and is_binary(path) do
    Connection.request(
      conn,
      "fs/watch",
      %{"watchId" => watch_id, "path" => path},
      timeout_ms: 30_000
    )
  end

  @doc """
  Stops a prior filesystem watch.
  """
  @spec fs_unwatch(connection(), String.t()) :: {:ok, map()} | {:error, term()}
  def fs_unwatch(conn, watch_id) when is_pid(conn) and is_binary(watch_id) do
    Connection.request(conn, "fs/unwatch", %{"watchId" => watch_id}, timeout_ms: 30_000)
  end

  @doc """
  Adds a marketplace source through the app-server marketplace API.
  """
  @spec marketplace_add(connection(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def marketplace_add(conn, source, opts \\ [])
      when is_pid(conn) and is_binary(source) and is_list(opts) do
    params =
      %{"source" => source}
      |> Params.put_optional("refName", Keyword.get(opts, :ref_name))
      |> Params.put_optional(
        "sparsePaths",
        normalize_non_empty_list(Keyword.get(opts, :sparse_paths))
      )

    Connection.request(conn, "marketplace/add", params, timeout_ms: 30_000)
  end

  @doc """
  Removes an installed marketplace by name.
  """
  @spec marketplace_remove(connection(), String.t()) :: {:ok, map()} | {:error, term()}
  def marketplace_remove(conn, marketplace_name)
      when is_pid(conn) and is_binary(marketplace_name) do
    Connection.request(
      conn,
      "marketplace/remove",
      %{"marketplaceName" => marketplace_name},
      timeout_ms: 30_000
    )
  end

  @doc """
  Upgrades one installed marketplace or all marketplaces when no name is provided.
  """
  @spec marketplace_upgrade(connection(), keyword()) :: {:ok, map()} | {:error, term()}
  def marketplace_upgrade(conn, opts \\ []) when is_pid(conn) and is_list(opts) do
    params =
      %{}
      |> Params.put_optional("marketplaceName", Keyword.get(opts, :marketplace_name))

    Connection.request(conn, "marketplace/upgrade", params, timeout_ms: 30_000)
  end

  @doc """
  Creates a controller-local device key.
  """
  @spec device_key_create(connection(), map() | keyword()) :: {:ok, map()} | {:error, term()}
  def device_key_create(conn, params) when is_pid(conn) do
    params = Params.normalize_map(params)

    wire_params =
      %{
        "accountUserId" =>
          fetch_any(params, [:account_user_id, "account_user_id", :accountUserId, "accountUserId"]),
        "clientId" => fetch_any(params, [:client_id, "client_id", :clientId, "clientId"])
      }
      |> Params.put_optional(
        "protectionPolicy",
        params
        |> fetch_any([
          :protection_policy,
          "protection_policy",
          :protectionPolicy,
          "protectionPolicy"
        ])
        |> normalize_device_key_protection_policy()
      )

    Connection.request(conn, "device/key/create", wire_params, timeout_ms: 30_000)
  end

  @doc """
  Reads device-key public metadata by key id.
  """
  @spec device_key_public(connection(), String.t()) :: {:ok, map()} | {:error, term()}
  def device_key_public(conn, key_id) when is_pid(conn) and is_binary(key_id) do
    Connection.request(conn, "device/key/public", %{"keyId" => key_id}, timeout_ms: 30_000)
  end

  @doc """
  Signs a structured device-key payload with a controller-local key.
  """
  @spec device_key_sign(connection(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  def device_key_sign(conn, key_id, payload)
      when is_pid(conn) and is_binary(key_id) and is_map(payload) do
    Connection.request(
      conn,
      "device/key/sign",
      %{"keyId" => key_id, "payload" => payload},
      timeout_ms: 30_000
    )
  end

  @doc """
  Lists plugin marketplaces via the app-server plugin API and returns the raw response map.

  For typed structs, use `plugin_list_typed/2`.
  """
  @spec plugin_list(connection(), keyword()) :: {:ok, map()} | {:error, term()}
  def plugin_list(conn, opts \\ []) when is_pid(conn) and is_list(opts) do
    with {:ok, params} <-
           encode_plugin_request_params(
             "plugin/list",
             cwds: Keyword.get(opts, :cwds),
             force_remote_sync: Keyword.get(opts, :force_remote_sync)
           ) do
      Connection.request(conn, "plugin/list", params, timeout_ms: 30_000)
    end
  end

  @doc """
  Lists plugin marketplaces via the app-server plugin API and parses the response
  into `Codex.Protocol.Plugin.ListResponse`.

  The raw `plugin_list/2` wrapper remains available and still returns the
  original map payload.
  """
  @spec plugin_list_typed(connection(), keyword()) ::
          {:ok, Plugin.ListResponse.t()} | {:error, term()}
  def plugin_list_typed(conn, opts \\ []) when is_pid(conn) and is_list(opts) do
    request_typed(conn, "plugin/list", opts, Plugin.ListResponse, timeout_ms: 30_000)
  end

  @doc """
  Installs a plugin via the app-server plugin API and returns the raw response map.

  For typed structs, use `plugin_install_typed/4`.
  """
  @spec plugin_install(connection(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def plugin_install(conn, marketplace_path, plugin_name, opts \\ [])
      when is_pid(conn) and is_binary(marketplace_path) and is_binary(plugin_name) and
             is_list(opts) do
    with {:ok, params} <-
           encode_plugin_request_params(
             "plugin/install",
             marketplace_path: marketplace_path,
             plugin_name: plugin_name,
             force_remote_sync: Keyword.get(opts, :force_remote_sync)
           ) do
      Connection.request(conn, "plugin/install", params, timeout_ms: 30_000)
    end
  end

  @doc """
  Installs a plugin via the app-server plugin API and parses the response into
  `Codex.Protocol.Plugin.InstallResponse`.

  The raw `plugin_install/4` wrapper remains available and still returns the
  original map payload.
  """
  @spec plugin_install_typed(connection(), String.t(), String.t(), keyword()) ::
          {:ok, Plugin.InstallResponse.t()} | {:error, term()}
  def plugin_install_typed(conn, marketplace_path, plugin_name, opts \\ [])
      when is_pid(conn) and is_binary(marketplace_path) and is_binary(plugin_name) and
             is_list(opts) do
    params =
      opts
      |> Keyword.put(:marketplace_path, marketplace_path)
      |> Keyword.put(:plugin_name, plugin_name)

    request_typed(conn, "plugin/install", params, Plugin.InstallResponse, timeout_ms: 30_000)
  end

  @doc """
  Reads plugin details from a marketplace entry via the app-server plugin API
  and returns the raw response map.

  For typed structs, use `plugin_read_typed/3`.
  """
  @spec plugin_read(connection(), String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def plugin_read(conn, marketplace_path, plugin_name)
      when is_pid(conn) and is_binary(marketplace_path) and is_binary(plugin_name) do
    with {:ok, params} <-
           encode_plugin_request_params(
             "plugin/read",
             marketplace_path: marketplace_path,
             plugin_name: plugin_name
           ) do
      Connection.request(conn, "plugin/read", params, timeout_ms: 30_000)
    end
  end

  @doc """
  Reads plugin details from a marketplace entry via the app-server plugin API
  and parses the response into `Codex.Protocol.Plugin.ReadResponse`.

  The raw `plugin_read/3` wrapper remains available and still returns the
  original map payload.
  """
  @spec plugin_read_typed(connection(), String.t(), String.t()) ::
          {:ok, Plugin.ReadResponse.t()} | {:error, term()}
  def plugin_read_typed(conn, marketplace_path, plugin_name)
      when is_pid(conn) and is_binary(marketplace_path) and is_binary(plugin_name) do
    request_typed(
      conn,
      "plugin/read",
      %Plugin.ReadParams{marketplace_path: marketplace_path, plugin_name: plugin_name},
      Plugin.ReadResponse,
      timeout_ms: 30_000
    )
  end

  @doc """
  Uninstalls a plugin via the app-server plugin API and returns the raw response map.

  For typed structs, use `plugin_uninstall_typed/3`.
  """
  @spec plugin_uninstall(connection(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def plugin_uninstall(conn, plugin_id, opts \\ [])
      when is_pid(conn) and is_binary(plugin_id) and is_list(opts) do
    with {:ok, params} <-
           encode_plugin_request_params(
             "plugin/uninstall",
             plugin_id: plugin_id,
             force_remote_sync: Keyword.get(opts, :force_remote_sync)
           ) do
      Connection.request(conn, "plugin/uninstall", params, timeout_ms: 30_000)
    end
  end

  @doc """
  Uninstalls a plugin via the app-server plugin API and parses the response into
  `Codex.Protocol.Plugin.UninstallResponse`.

  The raw `plugin_uninstall/3` wrapper remains available and still returns the
  original map payload.
  """
  @spec plugin_uninstall_typed(connection(), String.t(), keyword()) ::
          {:ok, Plugin.UninstallResponse.t()} | {:error, term()}
  def plugin_uninstall_typed(conn, plugin_id, opts \\ [])
      when is_pid(conn) and is_binary(plugin_id) and is_list(opts) do
    params =
      opts
      |> Keyword.put(:plugin_id, plugin_id)

    request_typed(conn, "plugin/uninstall", params, Plugin.UninstallResponse, timeout_ms: 30_000)
  end

  @doc """
  Runs a thread-bound shell command via the app-server `!` workflow.
  """
  @spec thread_shell_command(connection(), String.t(), String.t()) ::
          {:ok, map()} | {:error, term()}
  def thread_shell_command(conn, thread_id, command)
      when is_pid(conn) and is_binary(thread_id) and is_binary(command) do
    Connection.request(
      conn,
      "thread/shellCommand",
      %{"threadId" => thread_id, "command" => command},
      timeout_ms: 30_000
    )
  end

  @spec experimental_feature_list(connection(), keyword()) :: {:ok, map()} | {:error, term()}
  def experimental_feature_list(conn, opts \\ []) when is_pid(conn) and is_list(opts) do
    params =
      %{}
      |> Params.put_optional("cursor", Keyword.get(opts, :cursor))
      |> Params.put_optional("limit", Keyword.get(opts, :limit))

    Connection.request(conn, "experimentalFeature/list", params, timeout_ms: 30_000)
  end

  @spec experimental_feature_enablement_set(connection(), map() | keyword()) ::
          {:ok, map()} | {:error, term()}
  def experimental_feature_enablement_set(conn, enablement \\ %{}) when is_pid(conn) do
    params = %{"enablement" => Params.normalize_map(enablement)}

    Connection.request(conn, "experimentalFeature/enablement/set", params, timeout_ms: 30_000)
  end

  @spec config_read(connection(), keyword()) :: {:ok, map()} | {:error, term()}
  def config_read(conn, opts \\ []) when is_pid(conn) and is_list(opts) do
    params =
      %{"includeLayers" => !!Keyword.get(opts, :include_layers, false)}
      |> Params.put_optional("cwd", Keyword.get(opts, :cwd))

    Connection.request(conn, "config/read", params, timeout_ms: 10_000)
  end

  @spec external_agent_config_detect(connection(), keyword()) :: {:ok, map()} | {:error, term()}
  def external_agent_config_detect(conn, opts \\ [])
      when is_pid(conn) and is_list(opts) do
    params =
      %{}
      |> Params.put_optional("includeHome", normalize_true(Keyword.get(opts, :include_home)))
      |> Params.put_optional("cwds", Keyword.get(opts, :cwds))

    Connection.request(conn, "externalAgentConfig/detect", params, timeout_ms: 30_000)
  end

  @spec external_agent_config_import(connection(), [map()]) :: {:ok, map()} | {:error, term()}
  def external_agent_config_import(conn, migration_items)
      when is_pid(conn) and is_list(migration_items) do
    Connection.request(
      conn,
      "externalAgentConfig/import",
      %{"migrationItems" => migration_items},
      timeout_ms: 30_000
    )
  end

  @spec config_write(connection(), String.t(), term(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def config_write(conn, key_path, value, opts \\ [])
      when is_pid(conn) and is_binary(key_path) and is_list(opts) do
    merge_strategy = Params.merge_strategy(Keyword.get(opts, :merge_strategy, :replace))

    params =
      %{
        "keyPath" => key_path,
        "value" => value,
        "mergeStrategy" => merge_strategy
      }
      |> Params.put_optional("filePath", Keyword.get(opts, :file_path))
      |> Params.put_optional("expectedVersion", Keyword.get(opts, :expected_version))

    Connection.request(conn, "config/value/write", params, timeout_ms: 10_000)
  end

  @spec config_batch_write(connection(), [map()], keyword()) :: {:ok, map()} | {:error, term()}
  def config_batch_write(conn, edits, opts \\ [])
      when is_pid(conn) and is_list(edits) and is_list(opts) do
    wire_edits =
      Enum.map(edits, fn edit ->
        edit = Params.normalize_map(edit)

        %{
          "keyPath" =>
            Map.get(edit, :key_path) || Map.get(edit, "key_path") || Map.get(edit, :keyPath) ||
              Map.get(edit, "keyPath"),
          "value" => Map.get(edit, :value) || Map.get(edit, "value"),
          "mergeStrategy" =>
            Params.merge_strategy(
              Map.get(edit, :merge_strategy) || Map.get(edit, "merge_strategy") || :replace
            )
        }
      end)

    params =
      %{"edits" => wire_edits}
      |> Params.put_optional("filePath", Keyword.get(opts, :file_path))
      |> Params.put_optional("expectedVersion", Keyword.get(opts, :expected_version))
      |> Params.put_optional(
        "reloadUserConfig",
        normalize_true(Keyword.get(opts, :reload_user_config))
      )

    Connection.request(conn, "config/batchWrite", params, timeout_ms: 10_000)
  end

  @spec review_start(connection(), String.t(), term(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def review_start(conn, thread_id, target, opts \\ [])
      when is_pid(conn) and is_binary(thread_id) and is_list(opts) do
    params =
      %{
        "threadId" => thread_id,
        "target" => review_target(target)
      }
      |> Params.put_optional("delivery", normalize_review_delivery(Keyword.get(opts, :delivery)))

    Connection.request(conn, "review/start", params, timeout_ms: 300_000)
  end

  @spec command_exec(connection(), [String.t()], keyword()) :: {:ok, map()} | {:error, term()}
  def command_exec(conn, command, opts \\ [])
      when is_pid(conn) and is_list(command) and is_list(opts) do
    timeout_ms = Keyword.get(opts, :timeout_ms)
    disable_timeout = normalize_true(Keyword.get(opts, :disable_timeout))

    params =
      %{"command" => command}
      |> Params.put_optional("processId", Keyword.get(opts, :process_id))
      |> Params.put_optional("tty", normalize_true(Keyword.get(opts, :tty)))
      |> Params.put_optional("streamStdin", normalize_true(Keyword.get(opts, :stream_stdin)))
      |> Params.put_optional(
        "streamStdoutStderr",
        normalize_true(Keyword.get(opts, :stream_stdout_stderr))
      )
      |> Params.put_optional("outputBytesCap", Keyword.get(opts, :output_bytes_cap))
      |> Params.put_optional(
        "disableOutputCap",
        normalize_true(Keyword.get(opts, :disable_output_cap))
      )
      |> Params.put_optional("disableTimeout", disable_timeout)
      |> Params.put_optional("timeoutMs", timeout_ms)
      |> Params.put_optional("cwd", Keyword.get(opts, :cwd))
      |> Params.put_optional("env", Keyword.get(opts, :env))
      |> Params.put_optional("size", opts |> Keyword.get(:size) |> Params.terminal_size())
      |> Params.put_optional(
        "sandboxPolicy",
        opts |> Keyword.get(:sandbox_policy) |> Params.sandbox_policy()
      )
      |> Params.put_optional("permissionProfile", Keyword.get(opts, :permission_profile))

    request_timeout_ms =
      cond do
        disable_timeout ->
          Defaults.exec_timeout_ms() + 5_000

        is_integer(timeout_ms) and timeout_ms > 0 ->
          timeout_ms + 5_000

        true ->
          30_000
      end

    Connection.request(conn, "command/exec", params, timeout_ms: request_timeout_ms)
  end

  @doc """
  Writes bytes to a running `command/exec` session.
  """
  @spec command_exec_write(connection(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def command_exec_write(conn, process_id, opts \\ [])
      when is_pid(conn) and is_binary(process_id) and is_list(opts) do
    params =
      %{"processId" => process_id}
      |> Params.put_optional(
        "deltaBase64",
        opts
        |> Keyword.get(:delta)
        |> encode_command_exec_delta()
      )
      |> Params.put_optional("closeStdin", normalize_true(Keyword.get(opts, :close_stdin)))

    Connection.request(conn, "command/exec/write", params, timeout_ms: 30_000)
  end

  @spec command_exec_terminate(connection(), String.t()) :: {:ok, map()} | {:error, term()}
  def command_exec_terminate(conn, process_id)
      when is_pid(conn) and is_binary(process_id) do
    Connection.request(
      conn,
      "command/exec/terminate",
      %{"processId" => process_id},
      timeout_ms: 30_000
    )
  end

  @spec command_exec_resize(connection(), String.t(), map() | keyword()) ::
          {:ok, map()} | {:error, term()}
  def command_exec_resize(conn, process_id, size)
      when is_pid(conn) and is_binary(process_id) do
    params =
      %{"processId" => process_id}
      |> Params.put_optional("size", Params.terminal_size(size))

    Connection.request(conn, "command/exec/resize", params, timeout_ms: 30_000)
  end

  @doc """
  Backwards-compatible alias for `command_exec_write/3` using raw stdin text.
  """
  @spec command_write_stdin(connection(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def command_write_stdin(conn, process_id, stdin, opts \\ [])
      when is_pid(conn) and is_binary(process_id) and is_binary(stdin) and is_list(opts) do
    command_exec_write(conn, process_id,
      delta: stdin,
      close_stdin: Keyword.get(opts, :close_stdin, false)
    )
  end

  @spec windows_sandbox_setup_start(connection(), atom() | String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def windows_sandbox_setup_start(conn, mode, opts \\ [])
      when is_pid(conn) and is_list(opts) do
    params =
      %{"mode" => Params.windows_sandbox_setup_mode(mode)}
      |> Params.put_optional("cwd", Keyword.get(opts, :cwd))

    Connection.request(conn, "windowsSandbox/setupStart", params, timeout_ms: 30_000)
  end

  @spec feedback_upload(connection(), keyword()) :: {:ok, map()} | {:error, term()}
  def feedback_upload(conn, opts) when is_pid(conn) and is_list(opts) do
    params =
      %{
        "classification" => Keyword.fetch!(opts, :classification),
        "includeLogs" => !!Keyword.get(opts, :include_logs, false)
      }
      |> Params.put_optional("reason", Keyword.get(opts, :reason))
      |> Params.put_optional("threadId", Keyword.get(opts, :thread_id))

    Connection.request(conn, "feedback/upload", params, timeout_ms: 30_000)
  end

  defp review_target({:uncommitted_changes}), do: %{"type" => "uncommittedChanges"}

  defp review_target({:base_branch, branch}) when is_binary(branch),
    do: %{"type" => "baseBranch", "branch" => branch}

  defp review_target({:commit, sha, title}) when is_binary(sha) do
    %{"type" => "commit", "sha" => sha}
    |> Params.put_optional("title", title)
  end

  defp review_target({:custom, instructions}) when is_binary(instructions) do
    %{"type" => "custom", "instructions" => instructions}
  end

  defp review_target(%{} = target), do: target
  defp review_target(other), do: %{"type" => "custom", "instructions" => to_string(other)}

  defp normalize_review_delivery(nil), do: nil
  defp normalize_review_delivery(:inline), do: "inline"
  defp normalize_review_delivery(:detached), do: "detached"
  defp normalize_review_delivery("inline"), do: "inline"
  defp normalize_review_delivery("detached"), do: "detached"
  defp normalize_review_delivery(other) when is_binary(other), do: other
  defp normalize_review_delivery(_other), do: nil

  defp normalize_thread_source_kinds(nil), do: nil

  defp normalize_thread_source_kinds(source_kinds) when is_list(source_kinds) do
    source_kinds
    |> Enum.map(&Params.thread_source_kind/1)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      list -> list
    end
  end

  defp normalize_thread_source_kinds(_), do: nil

  defp normalize_non_empty_list(nil), do: nil
  defp normalize_non_empty_list([]), do: nil
  defp normalize_non_empty_list(values) when is_list(values), do: values
  defp normalize_non_empty_list(value), do: [value]

  defp normalize_device_key_protection_policy(nil), do: nil

  defp normalize_device_key_protection_policy(:hardware_only), do: "hardware_only"

  defp normalize_device_key_protection_policy(:allow_os_protected_nonextractable),
    do: "allow_os_protected_nonextractable"

  defp normalize_device_key_protection_policy("hardware_only"), do: "hardware_only"

  defp normalize_device_key_protection_policy("allow_os_protected_nonextractable"),
    do: "allow_os_protected_nonextractable"

  defp normalize_device_key_protection_policy(value) when is_binary(value), do: value
  defp normalize_device_key_protection_policy(_), do: nil

  defp encode_command_exec_delta(nil), do: nil
  defp encode_command_exec_delta(delta) when is_binary(delta), do: Base.encode64(delta)
  defp encode_command_exec_delta(delta), do: delta

  defp encode_plugin_request_params(method, params) when is_binary(method) and is_list(params) do
    params
    |> normalize_plugin_request_params(method)
    |> then(&encode_typed_request_params(method, &1))
  end

  defp encode_typed_request_params(method, nil) do
    case typed_params_module(method) do
      nil ->
        {:ok, %{}}

      module when is_atom(module) and not is_nil(module) ->
        parser = :erlang.make_fun(module, :parse, 1)
        encoder = :erlang.make_fun(module, :to_map, 1)

        with {:ok, typed_params} <- parser.(%{}) do
          {:ok, encoder.(typed_params)}
        end
    end
  end

  defp encode_typed_request_params(_method, %module{} = params) do
    if function_exported?(module, :to_map, 1) do
      {:ok, module.to_map(params)}
    else
      {:ok, Map.from_struct(params)}
    end
  end

  defp encode_typed_request_params(method, params) when is_map(params) or is_list(params) do
    case typed_params_module(method) do
      nil ->
        {:ok, Params.normalize_map(params)}

      module when is_atom(module) and not is_nil(module) ->
        parser = :erlang.make_fun(module, :parse, 1)
        encoder = :erlang.make_fun(module, :to_map, 1)

        with {:ok, typed_params} <- parser.(params) do
          {:ok, encoder.(typed_params)}
        end
    end
  end

  defp parse_typed_response(response_module, result) do
    cond do
      function_exported?(response_module, :parse, 1) ->
        case response_module.parse(result) do
          {:ok, typed_response} -> {:ok, typed_response}
          {:error, _reason} = error -> error
          typed_response -> {:ok, typed_response}
        end

      function_exported?(response_module, :from_map, 1) ->
        {:ok, response_module.from_map(result)}

      true ->
        {:error, {:invalid_typed_response_module, response_module}}
    end
  rescue
    error in [CliSubprocessCore.Schema.Error] ->
      {:error, {error.tag, error.details}}

    error in [ArgumentError, RuntimeError] ->
      {:error, {:invalid_typed_response, response_module, error}}
  end

  defp typed_params_module("plugin/list"), do: Plugin.ListParams
  defp typed_params_module("plugin/read"), do: Plugin.ReadParams
  defp typed_params_module("plugin/install"), do: Plugin.InstallParams
  defp typed_params_module("plugin/uninstall"), do: Plugin.UninstallParams
  defp typed_params_module(_method), do: nil

  defp normalize_plugin_request_params(params, method)
       when method in ["plugin/list", "plugin/install", "plugin/uninstall"] and is_list(params) do
    if Keyword.has_key?(params, :force_remote_sync) do
      Keyword.update!(params, :force_remote_sync, &Plugin.Helpers.raw_true?/1)
    else
      params
    end
  end

  defp normalize_plugin_request_params(params, _method) when is_list(params), do: params

  defp normalize_true(true), do: true
  defp normalize_true("true"), do: true
  defp normalize_true(_), do: nil

  defp resolve_remote_auth_token(opts) when is_list(opts) do
    with {:ok, governed_authority} <- GovernedAuthority.fetch(opts),
         {:ok, process_env} <-
           RuntimeEnv.normalize_overrides(
             Keyword.get(opts, :process_env, Keyword.get(opts, :env, %{}))
           ) do
      auth_token =
        opts
        |> Keyword.get(:auth_token)
        |> normalize_remote_auth_token()

      case {auth_token, Keyword.get(opts, :auth_token_env)} do
        {token, _auth_token_env} when is_binary(token) ->
          {:ok, Keyword.put(opts, :auth_token, token)}

        {nil, nil} ->
          {:ok, Keyword.delete(opts, :auth_token)}

        {nil, auth_token_env} ->
          resolve_remote_auth_token_env(opts, process_env, auth_token_env, governed_authority)
      end
    end
  end

  defp resolve_remote_auth_token_env(opts, process_env, auth_token_env, governed_authority) do
    auth_token_env =
      auth_token_env
      |> to_string()
      |> String.trim()

    auth_token =
      remote_auth_token_env_value(process_env, auth_token_env, governed_authority)
      |> normalize_remote_auth_token()

    cond do
      auth_token_env == "" ->
        {:error, {:missing_auth_token_env, auth_token_env}}

      is_binary(auth_token) ->
        {:ok, Keyword.put(opts, :auth_token, auth_token)}

      Map.has_key?(process_env, auth_token_env) or
          standalone_remote_auth_env_present?(auth_token_env, governed_authority) ->
        {:error, {:empty_auth_token_env, auth_token_env}}

      true ->
        {:error, {:missing_auth_token_env, auth_token_env}}
    end
  end

  defp remote_auth_token_env_value(process_env, auth_token_env, %{}) do
    Map.get(process_env, auth_token_env)
  end

  defp remote_auth_token_env_value(process_env, auth_token_env, nil) do
    case Map.get(process_env, auth_token_env) do
      nil -> System.get_env(auth_token_env)
      value -> value
    end
  end

  defp standalone_remote_auth_env_present?(_auth_token_env, %{}), do: false

  defp standalone_remote_auth_env_present?(auth_token_env, nil),
    do: System.get_env(auth_token_env) != nil

  defp normalize_remote_auth_token(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp normalize_remote_auth_token(_value), do: nil

  defp validate_remote_auth_transport(_websocket_url, nil), do: :ok

  defp validate_remote_auth_transport(websocket_url, auth_token) when is_binary(auth_token) do
    case URI.parse(websocket_url) do
      %URI{scheme: "wss", host: host} when is_binary(host) ->
        :ok

      %URI{scheme: "ws", host: host} when is_binary(host) ->
        if loopback_host?(host) do
          :ok
        else
          {:error, {:invalid_remote_auth_transport, websocket_url}}
        end

      _ ->
        {:error, {:invalid_remote_auth_transport, websocket_url}}
    end
  end

  defp loopback_host?(host) when is_binary(host) do
    String.downcase(host) == "localhost" or
      case :inet.parse_address(String.to_charlist(host)) do
        {:ok, {127, _, _, _}} -> true
        {:ok, {0, 0, 0, 0, 0, 0, 0, 1}} -> true
        _ -> false
      end
  end

  defp fetch_any(%{} = map, keys) when is_list(keys) do
    Enum.find_value(keys, &Map.get(map, &1))
  end
end
