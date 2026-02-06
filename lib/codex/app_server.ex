defmodule Codex.AppServer do
  @moduledoc """
  App-server transport for stateful, bidirectional communication with Codex.
  """

  alias Codex.AppServer.Connection
  alias Codex.AppServer.Params
  alias Codex.AppServer.Supervisor, as: ConnectionSupervisor
  alias Codex.Options

  @type connection :: pid()

  @type connect_opts :: [
          init_timeout_ms: pos_integer(),
          client_name: String.t(),
          client_title: String.t(),
          client_version: String.t()
        ]

  @default_init_timeout_ms 10_000

  @spec connect(Options.t(), connect_opts()) :: {:ok, connection()} | {:error, term()}
  def connect(%Options{} = codex_opts, opts \\ []) do
    init_timeout_ms = Keyword.get(opts, :init_timeout_ms, @default_init_timeout_ms)

    with {:ok, _pid} <- ensure_connection_supervisor() do
      child_spec =
        {Connection, {codex_opts, opts}}
        |> Supervisor.child_spec(restart: :temporary)

      case DynamicSupervisor.start_child(ConnectionSupervisor, child_spec) do
        {:ok, conn} ->
          case Connection.await_ready(conn, init_timeout_ms) do
            :ok ->
              {:ok, conn}

            {:error, _reason} = error ->
              _ = DynamicSupervisor.terminate_child(ConnectionSupervisor, conn)
              error
          end

        {:error, _} = error ->
          error
      end
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

  @spec thread_start(connection(), map() | keyword()) :: {:ok, map()} | {:error, term()}
  def thread_start(conn, params \\ %{}) when is_pid(conn) do
    params = Params.normalize_map(params)

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
      |> Params.put_optional(
        "approvalPolicy",
        params
        |> fetch_any([:approval_policy, "approval_policy"])
        |> Params.ask_for_approval()
      )
      |> Params.put_optional(
        "sandbox",
        params
        |> fetch_any([:sandbox, "sandbox"])
        |> Params.sandbox_mode()
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
        "experimentalRawEvents",
        fetch_any(params, [:experimental_raw_events, "experimental_raw_events"])
      )

    Connection.request(conn, "thread/start", wire_params, timeout_ms: 30_000)
  end

  @spec thread_resume(connection(), String.t(), map() | keyword()) ::
          {:ok, map()} | {:error, term()}
  def thread_resume(conn, thread_id, params \\ %{}) when is_pid(conn) and is_binary(thread_id) do
    params = Params.normalize_map(params)

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
      |> Params.put_optional(
        "approvalPolicy",
        params
        |> fetch_any([:approval_policy, "approval_policy"])
        |> Params.ask_for_approval()
      )
      |> Params.put_optional(
        "sandbox",
        params
        |> fetch_any([:sandbox, "sandbox"])
        |> Params.sandbox_mode()
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
        "experimentalRawEvents",
        fetch_any(params, [:experimental_raw_events, "experimental_raw_events"])
      )

    Connection.request(conn, "thread/resume", wire_params, timeout_ms: 30_000)
  end

  @spec thread_list(connection(), keyword()) :: {:ok, map()} | {:error, term()}
  def thread_list(conn, opts \\ []) when is_pid(conn) and is_list(opts) do
    wire_params =
      %{}
      |> Params.put_optional("cursor", Keyword.get(opts, :cursor))
      |> Params.put_optional("limit", Keyword.get(opts, :limit))
      |> Params.put_optional("sortKey", Params.thread_sort_key(Keyword.get(opts, :sort_key)))
      |> Params.put_optional("modelProviders", Keyword.get(opts, :model_providers))
      |> Params.put_optional("archived", Keyword.get(opts, :archived))

    Connection.request(conn, "thread/list", wire_params, timeout_ms: 30_000)
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

  @spec thread_fork(connection(), String.t(), map() | keyword()) ::
          {:ok, map()} | {:error, term()}
  def thread_fork(conn, thread_id, params \\ %{})
      when is_pid(conn) and is_binary(thread_id) do
    params = Params.normalize_map(params)

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
      |> Params.put_optional(
        "approvalPolicy",
        params
        |> fetch_any([:approval_policy, "approval_policy"])
        |> Params.ask_for_approval()
      )
      |> Params.put_optional(
        "sandbox",
        params
        |> fetch_any([:sandbox, "sandbox"])
        |> Params.sandbox_mode()
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

    Connection.request(conn, "thread/fork", wire_params, timeout_ms: 30_000)
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
    params = %{
      "threadId" => thread_id,
      "includeTurns" => !!Keyword.get(opts, :include_turns, false)
    }

    Connection.request(conn, "thread/read", params, timeout_ms: 30_000)
  end

  @spec thread_loaded_list(connection(), keyword()) :: {:ok, map()} | {:error, term()}
  def thread_loaded_list(conn, opts \\ []) when is_pid(conn) and is_list(opts) do
    params =
      %{}
      |> Params.put_optional("cursor", Keyword.get(opts, :cursor))
      |> Params.put_optional("limit", Keyword.get(opts, :limit))

    Connection.request(conn, "thread/loaded/list", params, timeout_ms: 30_000)
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

    Connection.request(conn, "app/list", params, timeout_ms: 30_000)
  end

  @doc """
  Returns an unsupported error. The `thread/compact` API was removed in upstream
  `codex app-server`. Context compaction now happens automatically server-side.

  ## Deprecation Notice

  This function is retained for API compatibility but will always return an error.
  Remove calls to this function from your code.
  """
  @spec thread_compact(connection(), String.t()) :: {:error, {:unsupported, String.t()}}
  @deprecated "thread/compact API removed upstream; compaction is now automatic"
  def thread_compact(_conn, _thread_id) do
    {:error,
     {:unsupported,
      "thread/compact API was removed in upstream codex; context compaction is now automatic server-side"}}
  end

  @spec turn_start(connection(), String.t(), String.t() | [map()], keyword()) ::
          {:ok, map()} | {:error, term()}
  def turn_start(conn, thread_id, input, opts \\ [])
      when is_pid(conn) and is_binary(thread_id) and is_list(opts) do
    wire_params =
      %{
        "threadId" => thread_id,
        "input" => Params.user_input(input)
      }
      |> Params.put_optional("cwd", Keyword.get(opts, :cwd))
      |> Params.put_optional(
        "approvalPolicy",
        opts
        |> Keyword.get(:approval_policy)
        |> Params.ask_for_approval()
      )
      |> Params.put_optional(
        "sandboxPolicy",
        opts |> Keyword.get(:sandbox_policy) |> Params.sandbox_policy()
      )
      |> Params.put_optional("model", Keyword.get(opts, :model))
      |> Params.put_optional("effort", opts |> Keyword.get(:effort) |> Params.reasoning_effort())
      |> Params.put_optional("summary", Keyword.get(opts, :summary))
      |> Params.put_optional(
        "personality",
        opts |> Keyword.get(:personality) |> Params.personality()
      )
      |> Params.put_optional("outputSchema", Keyword.get(opts, :output_schema))
      |> Params.put_optional(
        "collaborationMode",
        opts |> Keyword.get(:collaboration_mode) |> Params.collaboration_mode()
      )

    Connection.request(conn, "turn/start", wire_params, timeout_ms: 300_000)
  end

  @spec turn_interrupt(connection(), String.t(), String.t()) :: :ok | {:error, term()}
  def turn_interrupt(conn, thread_id, turn_id)
      when is_pid(conn) and is_binary(thread_id) and is_binary(turn_id) do
    params = %{"threadId" => thread_id, "turnId" => turn_id}

    case Connection.request(conn, "turn/interrupt", params, timeout_ms: 30_000) do
      {:ok, _} -> :ok
      {:error, _} = error -> error
    end
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

    Connection.request(conn, "skills/list", params, timeout_ms: 30_000)
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

  @spec model_list(connection(), keyword()) :: {:ok, map()} | {:error, term()}
  def model_list(conn, opts \\ []) when is_pid(conn) and is_list(opts) do
    params =
      %{}
      |> Params.put_optional("cursor", Keyword.get(opts, :cursor))
      |> Params.put_optional("limit", Keyword.get(opts, :limit))

    Connection.request(conn, "model/list", params, timeout_ms: 30_000)
  end

  @spec config_read(connection(), keyword()) :: {:ok, map()} | {:error, term()}
  def config_read(conn, opts \\ []) when is_pid(conn) and is_list(opts) do
    params =
      %{"includeLayers" => !!Keyword.get(opts, :include_layers, false)}
      |> Params.put_optional("cwd", Keyword.get(opts, :cwd))

    Connection.request(conn, "config/read", params, timeout_ms: 10_000)
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

    params =
      %{"command" => command}
      |> Params.put_optional("timeoutMs", timeout_ms)
      |> Params.put_optional("cwd", Keyword.get(opts, :cwd))
      |> Params.put_optional("sandboxPolicy", Keyword.get(opts, :sandbox_policy))

    request_timeout_ms =
      case timeout_ms do
        value when is_integer(value) and value > 0 -> value + 5_000
        _ -> 30_000
      end

    Connection.request(conn, "command/exec", params, timeout_ms: request_timeout_ms)
  end

  @doc """
  Writes stdin to a running command execution session.
  """
  @spec command_write_stdin(connection(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def command_write_stdin(conn, process_id, stdin, opts \\ [])
      when is_pid(conn) and is_binary(process_id) and is_binary(stdin) and is_list(opts) do
    params =
      %{
        "processId" => process_id,
        "stdin" => stdin
      }
      |> Params.put_optional("threadId", Keyword.get(opts, :thread_id))
      |> Params.put_optional("turnId", Keyword.get(opts, :turn_id))
      |> Params.put_optional("itemId", Keyword.get(opts, :item_id))
      |> Params.put_optional("yieldTimeMs", Keyword.get(opts, :yield_time_ms))
      |> Params.put_optional("maxOutputTokens", Keyword.get(opts, :max_output_tokens))

    Connection.request(conn, "command/writeStdin", params, timeout_ms: 30_000)
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

  defp fetch_any(%{} = map, keys) when is_list(keys) do
    Enum.find_value(keys, &Map.get(map, &1))
  end
end
