defmodule Codex.Runtime.Exec do
  @moduledoc """
  Session-oriented runtime kit for the common Codex exec CLI family.
  """

  @behaviour Codex.RuntimeKit

  require Logger

  alias CliSubprocessCore.Event, as: CoreEvent
  alias CliSubprocessCore.Payload
  alias CliSubprocessCore.ProviderProfiles.Codex, as: CoreCodex
  alias CliSubprocessCore.Session
  alias Codex.ApprovalPolicy
  alias Codex.Config.Overrides
  alias Codex.Events
  alias Codex.Exec.Options, as: ExecOptions
  alias Codex.Files.Attachment
  alias Codex.IO.Buffer
  alias Codex.Options
  alias Codex.ProcessExit
  alias Codex.Runtime.Env, as: RuntimeEnv
  alias ExecutionPlane.ProcessExit, as: CoreProcessExit

  @default_session_event_tag :codex_sdk_exec_session
  @session_control_capabilities [
    :session_history,
    :session_resume,
    :session_pause,
    :session_intervene
  ]

  @impl true
  def start_session(opts) when is_list(opts) do
    with {:ok, session_opts} <- build_session_options(opts) do
      Session.start_session(session_opts)
    end
  end

  @impl true
  def subscribe(session, pid, ref) when is_pid(session) and is_pid(pid) and is_reference(ref) do
    Session.subscribe(session, pid, ref)
  end

  @impl true
  def send_input(session, input, opts \\ []) when is_pid(session) do
    Session.send_input(session, input, opts)
  end

  @impl true
  def end_input(session) when is_pid(session), do: Session.end_input(session)

  @impl true
  def interrupt(session) when is_pid(session), do: Session.interrupt(session)

  @impl true
  def close(session) when is_pid(session), do: Session.close(session)

  @impl true
  def info(session) when is_pid(session), do: Session.info(session)

  @impl true
  def capabilities do
    (CoreCodex.capabilities() ++ @session_control_capabilities)
    |> Enum.uniq()
  end

  @spec list_provider_sessions(keyword()) :: {:ok, [map()]} | {:error, term()}
  def list_provider_sessions(opts \\ []) when is_list(opts) do
    with {:ok, sessions} <- Codex.list_sessions(opts) do
      {:ok,
       Enum.map(sessions, fn session ->
         %{
           id: session.id,
           label:
             session.originator ||
               session.metadata["title"] ||
               session.metadata[:title] ||
               session.id,
           cwd: session.cwd,
           updated_at: session.updated_at,
           source_kind: :thread_history,
           metadata: %{
             path: session.path,
             started_at: session.started_at,
             originator: session.originator,
             cli_version: session.cli_version
           },
           raw: session
         }
       end)}
    end
  end

  @doc false
  @spec session_event_tag() :: :codex_sdk_exec_session
  def session_event_tag, do: @default_session_event_tag

  @impl true
  def project_event(%CoreEvent{kind: :run_started}, state), do: {[], state}

  def project_event(%CoreEvent{raw: %{exit: %CoreProcessExit{}}}, state), do: {[], state}

  def project_event(
        %CoreEvent{
          kind: :error,
          payload: %Payload.Error{code: "parse_error", metadata: metadata}
        },
        state
      ) do
    line = Map.get(metadata, :line) || Map.get(metadata, "line") || ""

    Logger.warning("Failed to decode codex event: #{Buffer.format_binary_for_log(line)}")
    {[], state}
  end

  def project_event(%CoreEvent{raw: raw}, state) when is_map(raw) do
    case decode_public_event(raw, state) do
      {:ok, event} -> {[event], state}
      :drop -> {[], state}
    end
  end

  def project_event(_event, state), do: {[], state}

  @spec session_error(CoreEvent.t(), binary(), boolean()) :: {:error, term()} | nil
  def session_error(
        %CoreEvent{
          kind: :error,
          raw: %{exit: %CoreProcessExit{} = exit},
          payload: %Payload.Error{} = payload
        },
        stderr,
        stderr_truncated?
      ) do
    {:error,
     Codex.TransportError.new(exit_code(exit),
       message: payload.message || exit_message(exit),
       stderr: stderr,
       stderr_truncated?: stderr_truncated?,
       retryable?: retryable_exit?(exit),
       reason_code: normalize_reason_code(payload.code)
     )}
  end

  def session_error(_event, _stderr, _stderr_truncated?), do: nil

  @spec stderr_chunk(CoreEvent.t()) :: binary() | nil
  def stderr_chunk(%CoreEvent{kind: :stderr, payload: %Payload.Stderr{content: content}})
      when is_binary(content),
      do: content

  def stderr_chunk(_event), do: nil

  @spec build_session_options(keyword()) :: {:ok, keyword()} | {:error, term()}
  def build_session_options(opts) when is_list(opts) do
    exec_opts = Keyword.fetch!(opts, :exec_opts)
    input = Keyword.get(opts, :input)
    command_args = Keyword.get(opts, :command_args)
    subscriber = Keyword.get(opts, :subscriber)

    with %ExecOptions{} = exec_opts <- exec_opts,
         {:ok, command_spec} <-
           Options.codex_command_spec(exec_opts.codex_opts, exec_opts.execution_surface),
         {:ok, config_values} <- config_values(exec_opts) do
      subcommand_args = command_args || command_args_for_run(exec_opts)

      session_opts =
        [
          provider: :codex,
          profile: Codex.Runtime.Exec.Profile,
          subscriber: subscriber,
          metadata: session_metadata(opts, exec_opts),
          command_spec: command_spec,
          stdin: normalize_prompt(input),
          cli_profile: exec_opt(exec_opts, :profile),
          oss: payload_oss?(exec_opts),
          local_provider: payload_local_provider(exec_opts),
          full_auto: exec_opt(exec_opts, :full_auto),
          dangerously_bypass_approvals_and_sandbox:
            exec_opt(exec_opts, :dangerously_bypass_approvals_and_sandbox),
          model: normalize_option_string(exec_opts.codex_opts.model),
          model_payload: exec_opts.codex_opts.model_payload,
          color: normalize_option_string(exec_opt(exec_opts, :color)),
          output_last_message: exec_opt(exec_opts, :output_last_message),
          sandbox: sandbox_mode(fetch_thread_opt(exec_opts.thread, :sandbox)),
          working_directory: fetch_thread_opt(exec_opts.thread, :working_directory),
          additional_directories:
            normalize_string_list(fetch_thread_opt(exec_opts.thread, :additional_directories)),
          skip_git_repo_check: fetch_thread_opt(exec_opts.thread, :skip_git_repo_check) == true,
          subcommand_args: subcommand_args,
          continuation_token: exec_opts.continuation_token,
          cancellation_token: exec_opts.cancellation_token,
          images: attachment_paths(exec_opts.attachments),
          output_schema: exec_opts.output_schema_path,
          config_values: config_values,
          env: build_env(exec_opts),
          session_event_tag: @default_session_event_tag,
          headless_timeout_ms: :infinity,
          max_stderr_buffer_size: transport_stderr_buffer_size(exec_opts)
        ] ++ Options.execution_surface_options(exec_opts.execution_surface)

      {:ok, session_opts}
    else
      {:error, _} = error ->
        error

      _other ->
        {:error, :invalid_exec_options}
    end
  end

  defp session_metadata(opts, %ExecOptions{codex_opts: %Options{} = codex_opts}) do
    model = normalize_option_string(codex_opts.model)
    reasoning_effort = normalize_reasoning_value(codex_opts.reasoning_effort)

    opts
    |> Keyword.get(:metadata, %{})
    |> normalize_session_metadata()
    |> Map.put_new(:lane, :codex_sdk)
    |> put_if_missing("model", model)
    |> put_reasoning_if_missing(reasoning_effort)
    |> put_reasoning_config_if_missing(reasoning_effort)
  end

  defp normalize_session_metadata(metadata) when is_map(metadata), do: metadata
  defp normalize_session_metadata(_metadata), do: %{}

  defp decode_public_event(raw, state) do
    event = Events.parse!(raw)
    {:ok, enrich_event(event, codex_options(state))}
  rescue
    error in ArgumentError ->
      Logger.warning("Unsupported codex event: #{Exception.message(error)}")
      :drop
  end

  defp codex_options(%{exec_opts: %ExecOptions{codex_opts: %Options{} = opts}}), do: opts
  defp codex_options(%{exec_opts: %Options{} = opts}), do: opts
  defp codex_options(%{codex_opts: %Options{} = opts}), do: opts
  defp codex_options(_state), do: nil

  defp enrich_event(%Events.ThreadStarted{} = event, %Options{} = opts) do
    %Events.ThreadStarted{
      event
      | metadata: enrich_thread_started_metadata(event.metadata, opts)
    }
  end

  defp enrich_event(event, _opts), do: event

  defp enrich_thread_started_metadata(metadata, %Options{} = opts) do
    metadata =
      case metadata do
        value when is_map(value) -> value
        _ -> %{}
      end

    model = normalize_option_string(opts.model)
    reasoning_effort = normalize_reasoning_value(opts.reasoning_effort)

    metadata
    |> put_if_missing("model", model)
    |> put_reasoning_if_missing(reasoning_effort)
    |> put_reasoning_config_if_missing(reasoning_effort)
  end

  defp put_if_missing(map, _key, nil), do: map

  defp put_if_missing(map, key, value),
    do: if(Map.has_key?(map, key), do: map, else: Map.put(map, key, value))

  defp put_reasoning_if_missing(map, nil), do: map

  defp put_reasoning_if_missing(map, value) do
    if Map.has_key?(map, "reasoning_effort") or Map.has_key?(map, "reasoningEffort") do
      map
    else
      Map.put(map, "reasoning_effort", value)
    end
  end

  defp put_reasoning_config_if_missing(map, nil), do: map

  defp put_reasoning_config_if_missing(map, value) do
    case Map.get(map, "config") do
      config when is_map(config) ->
        if Map.has_key?(config, "model_reasoning_effort") do
          map
        else
          Map.put(map, "config", Map.put(config, "model_reasoning_effort", value))
        end

      _ ->
        Map.put(map, "config", %{"model_reasoning_effort" => value})
    end
  end

  defp command_args_for_run(%ExecOptions{} = exec_opts) do
    resume_args(exec_opts.thread)
  end

  defp config_values(%ExecOptions{} = exec_opts) do
    with {:ok, approval_values} <- approval_config_values(exec_opts.thread),
         {:ok, override_values} <- override_config_values(exec_opts) do
      {:ok,
       reasoning_config_values(exec_opts) ++
         network_access_config_values(exec_opts.thread) ++
         payload_config_values(exec_opts) ++
         approval_values ++
         override_values}
    end
  end

  defp override_config_values(exec_opts) do
    with {:ok, global_overrides} <- global_config_overrides(exec_opts),
         {:ok, thread_overrides} <- thread_config_overrides(exec_opts),
         {:ok, turn_overrides} <- turn_config_overrides(exec_opts) do
      derived_overrides = derived_config_overrides(exec_opts)

      {:ok,
       (global_overrides ++ derived_overrides ++ thread_overrides ++ turn_overrides)
       |> Overrides.cli_args()
       |> config_values_from_cli_args()}
    end
  end

  defp reasoning_config_values(%ExecOptions{codex_opts: %Options{} = opts}) do
    case normalize_reasoning_value(opts.reasoning_effort) do
      nil ->
        []

      reasoning ->
        [~s(model_reasoning_effort="#{reasoning}")]
    end
  end

  defp approval_config_values(%{thread_opts: %Codex.Thread.Options{ask_for_approval: nil}}),
    do: {:ok, []}

  defp approval_config_values(%{thread_opts: %Codex.Thread.Options{ask_for_approval: policy}}) do
    case ApprovalPolicy.to_external(policy) do
      {:ok, nil} ->
        {:ok, []}

      {:ok, value} when is_binary(value) ->
        {:ok, [~s(approval_policy="#{value}")]}

      {:ok, %{} = value} ->
        %{"approval_policy" => value}
        |> Overrides.normalize_config_overrides()
        |> case do
          {:ok, overrides} ->
            {:ok, overrides |> Overrides.cli_args() |> config_values_from_cli_args()}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp approval_config_values(_thread), do: {:ok, []}

  defp normalize_reasoning_value(nil), do: nil

  defp normalize_reasoning_value(value) when is_atom(value) do
    Codex.Models.reasoning_effort_to_string(value)
  end

  defp normalize_reasoning_value(value) when is_binary(value), do: value

  defp network_access_config_values(%{
         thread_opts: %Codex.Thread.Options{sandbox: {:external_sandbox, network_access}}
       }) do
    case network_access do
      :enabled -> ["sandbox_external.network_access=true"]
      :restricted -> ["sandbox_external.network_access=false"]
      _ -> []
    end
  end

  defp network_access_config_values(%{
         thread_opts: %Codex.Thread.Options{network_access_enabled: value}
       })
       when value in [true, false] do
    ["sandbox_workspace_write.network_access=#{value}"]
  end

  defp network_access_config_values(_thread), do: []

  defp global_config_overrides(%ExecOptions{codex_opts: %Options{} = opts}) do
    opts
    |> Map.get(:config_overrides, [])
    |> Overrides.normalize_config_overrides()
  end

  defp thread_config_overrides(%ExecOptions{
         thread: %{thread_opts: %Codex.Thread.Options{} = opts}
       }) do
    opts
    |> Map.get(:config_overrides, [])
    |> Overrides.normalize_config_overrides()
  end

  defp thread_config_overrides(_), do: {:ok, []}

  defp turn_config_overrides(%ExecOptions{turn_opts: %{} = opts}) do
    opts
    |> fetch_turn_opt(:config_overrides)
    |> Overrides.normalize_config_overrides()
  end

  defp derived_config_overrides(%ExecOptions{codex_opts: %Options{} = opts} = exec_opts) do
    thread_opts =
      case exec_opts.thread do
        %{thread_opts: %Codex.Thread.Options{} = thread_opts} -> thread_opts
        _ -> nil
      end

    Overrides.derived_overrides(opts, thread_opts)
  end

  defp build_env(%ExecOptions{codex_opts: %Options{} = opts, env: env}) do
    RuntimeEnv.base_overrides(opts.api_key, opts.base_url)
    |> Map.merge(payload_env_overrides(opts), fn _key, _base, payload -> payload end)
    |> Map.merge(env, fn _key, _base, custom -> custom end)
  end

  defp attachment_paths(attachments) do
    attachments
    |> List.wrap()
    |> Enum.flat_map(fn
      %Attachment{path: path} when is_binary(path) and path != "" -> [path]
      _attachment -> []
    end)
  end

  defp resume_args(%{thread_id: thread_id}) when is_binary(thread_id), do: ["resume", thread_id]
  defp resume_args(%{resume: :last}), do: ["resume", "--last"]
  defp resume_args(_), do: []

  defp sandbox_mode(:strict), do: "read-only"
  defp sandbox_mode(:default), do: nil
  defp sandbox_mode(:permissive), do: "danger-full-access"
  defp sandbox_mode(:read_only), do: "read-only"
  defp sandbox_mode(:workspace_write), do: "workspace-write"
  defp sandbox_mode(:danger_full_access), do: "danger-full-access"
  defp sandbox_mode(:external_sandbox), do: "external-sandbox"
  defp sandbox_mode({:external_sandbox, _network_access}), do: "external-sandbox"
  defp sandbox_mode("read-only"), do: "read-only"
  defp sandbox_mode("workspace-write"), do: "workspace-write"
  defp sandbox_mode("danger-full-access"), do: "danger-full-access"
  defp sandbox_mode("external-sandbox"), do: "external-sandbox"
  defp sandbox_mode(nil), do: nil
  defp sandbox_mode(value) when is_binary(value), do: value
  defp sandbox_mode(_), do: nil

  defp exec_opt(%ExecOptions{} = exec_opts, key) when is_atom(key) do
    case fetch_turn_opt(exec_opts.turn_opts, key) do
      nil -> fetch_thread_opt(exec_opts.thread, key)
      value -> value
    end
  end

  defp payload_oss?(%ExecOptions{codex_opts: %Options{} = opts} = exec_opts) do
    case payload_provider_backend(opts.model_payload) do
      backend when backend in [:oss, "oss"] -> true
      _ -> exec_opt(exec_opts, :oss) == true
    end
  end

  defp payload_local_provider(%ExecOptions{codex_opts: %Options{} = opts} = exec_opts) do
    case payload_backend_metadata(opts.model_payload) do
      %{"oss_provider" => provider} when is_binary(provider) and provider != "" ->
        provider

      _ ->
        exec_opt(exec_opts, :local_provider)
    end
  end

  defp payload_config_values(%ExecOptions{codex_opts: %Options{} = opts}) do
    opts.model_payload
    |> payload_backend_metadata()
    |> Map.get("config_values", [])
    |> List.wrap()
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
  end

  defp payload_env_overrides(%Options{model_payload: payload}) do
    payload
    |> case do
      payload when is_map(payload) ->
        Map.get(payload, :env_overrides, Map.get(payload, "env_overrides", %{}))

      _ ->
        %{}
    end
    |> case do
      env when is_map(env) ->
        Map.new(env, fn {key, value} -> {to_string(key), to_string(value)} end)

      _ ->
        %{}
    end
  end

  defp payload_backend_metadata(payload) when is_map(payload) do
    Map.get(payload, :backend_metadata, Map.get(payload, "backend_metadata", %{}))
    |> case do
      metadata when is_map(metadata) -> metadata
      _ -> %{}
    end
  end

  defp payload_backend_metadata(_payload), do: %{}

  defp payload_provider_backend(payload) when is_map(payload) do
    Map.get(payload, :provider_backend, Map.get(payload, "provider_backend"))
  end

  defp payload_provider_backend(_payload), do: nil

  defp fetch_turn_opt(%{} = opts, key) when is_atom(key) do
    case Map.fetch(opts, key) do
      {:ok, value} ->
        value

      :error ->
        case Map.fetch(opts, Atom.to_string(key)) do
          {:ok, value} -> value
          :error -> nil
        end
    end
  end

  defp fetch_thread_opt(%{thread_opts: %Codex.Thread.Options{} = opts}, key) when is_atom(key) do
    case Map.fetch(opts, key) do
      {:ok, value} -> value
      :error -> nil
    end
  end

  defp fetch_thread_opt(_thread, _key), do: nil

  defp normalize_option_string(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_option_string(value) when is_binary(value) and value != "", do: value
  defp normalize_option_string(_value), do: nil

  defp normalize_string_list(values) when is_list(values) do
    Enum.filter(values, &(is_binary(&1) and &1 != ""))
  end

  defp normalize_string_list(_values), do: []

  defp normalize_prompt(value) when is_binary(value) and value != "", do: value
  defp normalize_prompt(_value), do: nil

  defp config_values_from_cli_args(args) when is_list(args) do
    args
    |> Enum.chunk_every(2)
    |> Enum.flat_map(fn
      ["--config", value] -> [value]
      _other -> []
    end)
  end

  defp transport_stderr_buffer_size(%ExecOptions{max_stderr_buffer_bytes: nil}), do: 262_145

  defp transport_stderr_buffer_size(%ExecOptions{max_stderr_buffer_bytes: max_bytes})
       when is_integer(max_bytes) and max_bytes > 0 do
    max_bytes + 1
  end

  defp transport_stderr_buffer_size(_exec_opts), do: 262_145

  defp exit_code(%CoreProcessExit{status: :success}), do: 0
  defp exit_code(%CoreProcessExit{status: :exit, code: code}) when is_integer(code), do: code

  defp exit_code(%CoreProcessExit{status: :signal, signal: signal}) do
    case ProcessExit.exit_status(%CoreProcessExit{status: :signal, signal: signal}) do
      {:ok, status} -> status
      :unknown -> -1
    end
  end

  defp exit_code(%CoreProcessExit{code: code}) when is_integer(code), do: code
  defp exit_code(_exit), do: -1

  defp exit_message(%CoreProcessExit{status: :exit, code: code}) when is_integer(code) do
    "codex executable exited with status #{code}"
  end

  defp exit_message(%CoreProcessExit{status: :signal, signal: signal}) do
    "codex executable exited due to signal #{inspect(signal)}"
  end

  defp exit_message(%CoreProcessExit{reason: reason}) do
    "codex executable exited: #{inspect(reason)}"
  end

  defp normalize_reason_code(nil), do: nil
  defp normalize_reason_code(code) when is_atom(code), do: code

  defp normalize_reason_code(code) when is_binary(code) do
    code
    |> String.downcase()
    |> String.replace("-", "_")
    |> String.to_atom()
  end

  defp retryable_exit?(%CoreProcessExit{} = exit),
    do: Codex.TransportError.retryable_status?(exit_code(exit))
end
