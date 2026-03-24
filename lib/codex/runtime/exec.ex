defmodule Codex.Runtime.Exec do
  @moduledoc """
  Session-oriented runtime kit for the common Codex exec CLI family.
  """

  @behaviour Codex.RuntimeKit

  require Logger

  alias CliSubprocessCore.Event, as: CoreEvent
  alias CliSubprocessCore.Payload
  alias CliSubprocessCore.ProcessExit, as: CoreProcessExit
  alias CliSubprocessCore.ProviderProfiles.Codex, as: CoreCodex
  alias CliSubprocessCore.Session
  alias Codex.ApprovalPolicy
  alias Codex.Auth
  alias Codex.Config.LayerStack
  alias Codex.Config.Overrides
  alias Codex.Events
  alias Codex.Exec.Options, as: ExecOptions
  alias Codex.Files.Attachment
  alias Codex.IO.Buffer
  alias Codex.Models
  alias Codex.Options
  alias Codex.ProcessExit
  alias Codex.Runtime.Env, as: RuntimeEnv

  @default_session_event_tag :codex_sdk_exec_session

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
  def capabilities, do: CoreCodex.capabilities()

  @doc false
  @spec session_event_tag() :: atom()
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
        %CoreEvent{kind: :error, raw: %{exit: %CoreProcessExit{} = exit}},
        stderr,
        stderr_truncated?
      ) do
    {:error,
     Codex.TransportError.new(exit_code(exit),
       message: exit_message(exit),
       stderr: stderr,
       stderr_truncated?: stderr_truncated?,
       retryable?: retryable_exit?(exit)
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
         {:ok, binary_path} <- Options.codex_path(exec_opts.codex_opts),
         {:ok, config_values} <- config_values(exec_opts) do
      subcommand_args = command_args || command_args_for_run(exec_opts)

      session_opts =
        [
          provider: :codex,
          profile: Codex.Runtime.Exec.Profile,
          subscriber: subscriber,
          metadata: %{lane: :codex_sdk},
          command: binary_path,
          prompt: normalize_prompt(input),
          cli_profile: exec_opt(exec_opts, :profile),
          oss: exec_opt(exec_opts, :oss),
          local_provider: exec_opt(exec_opts, :local_provider),
          full_auto: exec_opt(exec_opts, :full_auto),
          dangerously_bypass_approvals_and_sandbox:
            exec_opt(exec_opts, :dangerously_bypass_approvals_and_sandbox),
          model: normalize_string(exec_opts.codex_opts.model),
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
        ]

      {:ok, session_opts}
    else
      {:error, _} = error ->
        error

      _other ->
        {:error, :invalid_exec_options}
    end
  end

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

    model = normalize_string(opts.model)
    reasoning_effort = normalize_reasoning(opts.reasoning_effort)

    metadata
    |> put_if_missing("model", model)
    |> put_reasoning_if_missing(reasoning_effort)
    |> put_reasoning_config_if_missing(reasoning_effort)
  end

  defp normalize_reasoning(value) when is_atom(value) do
    case Models.normalize_reasoning_effort(value) do
      {:ok, effort} when is_atom(effort) and not is_nil(effort) ->
        Models.reasoning_effort_to_string(effort)

      _ ->
        nil
    end
  end

  defp normalize_reasoning(value) when is_binary(value) and value != "", do: value
  defp normalize_reasoning(_value), do: nil

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

  defp reasoning_config_values(%ExecOptions{codex_opts: %Options{} = opts} = exec_opts) do
    case resolve_reasoning_effort(opts, config_cwd(exec_opts)) do
      nil ->
        []

      effort ->
        stringified = Models.reasoning_effort_to_string(effort)
        [~s(model_reasoning_effort="#{stringified}")]
    end
  end

  defp resolve_reasoning_effort(%Options{} = opts, cwd) do
    effort =
      opts.reasoning_effort ||
        config_reasoning_effort(cwd) ||
        Models.default_reasoning_effort(opts.model)

    effort
    |> normalize_reasoning_effort_value()
    |> then(&Models.coerce_reasoning_effort(opts.model, &1))
  end

  defp normalize_reasoning_effort_value(nil), do: nil

  defp normalize_reasoning_effort_value(value) do
    case Models.normalize_reasoning_effort(value) do
      {:ok, effort} -> effort
      _ -> nil
    end
  end

  defp config_reasoning_effort(cwd) do
    codex_home = Auth.codex_home()

    case LayerStack.load(codex_home, cwd) do
      {:ok, layers} ->
        config = LayerStack.effective_config(layers)
        Map.get(config, "model_reasoning_effort") || Map.get(config, :model_reasoning_effort)

      {:error, _} ->
        nil
    end
  end

  defp config_cwd(%ExecOptions{
         thread: %{thread_opts: %Codex.Thread.Options{working_directory: dir}}
       })
       when is_binary(dir) and dir != "" do
    dir
  end

  defp config_cwd(_exec_opts) do
    case File.cwd() do
      {:ok, cwd} -> cwd
      _ -> nil
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

  defp normalize_string(value) when is_binary(value) and value != "", do: value
  defp normalize_string(_value), do: nil

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

  defp retryable_exit?(%CoreProcessExit{} = exit),
    do: Codex.TransportError.retryable_status?(exit_code(exit))
end
