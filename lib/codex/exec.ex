defmodule Codex.Exec do
  @moduledoc """
  Process manager wrapping the `codex` binary via erlexec.

  Provides blocking and streaming helpers that decode JSONL event output into
  typed `%Codex.Events{}` structs.
  """

  require Logger

  alias Codex.Auth
  alias Codex.Config.Defaults
  alias Codex.Config.LayerStack
  alias Codex.Config.Overrides
  alias Codex.Events
  alias Codex.Exec.CancellationRegistry
  alias Codex.Exec.Options, as: ExecOptions
  alias Codex.Files.Attachment
  alias Codex.IO.Transport.Erlexec, as: IOTransport
  alias Codex.Models
  alias Codex.Options
  alias Codex.Runtime.Env, as: RuntimeEnv
  alias Codex.TransportError

  @type exec_opts :: %{
          optional(:codex_opts) => Options.t(),
          optional(:thread) => Codex.Thread.t(),
          optional(:turn_opts) => map(),
          optional(:continuation_token) => String.t(),
          optional(:attachments) => [Attachment.t()],
          optional(:output_schema_path) => String.t(),
          optional(:tool_outputs) => [map()],
          optional(:tool_failures) => [map()],
          optional(:env) => map(),
          optional(:clear_env?) => boolean(),
          optional(:cancellation_token) => String.t(),
          optional(:timeout_ms) => pos_integer()
        }

  @doc """
  Runs codex in blocking mode and accumulates all emitted events.
  """
  @spec run(String.t(), exec_opts()) :: {:ok, map()} | {:error, term()}
  def run(input, opts) when is_binary(input) do
    with {:ok, exec_opts} <- ExecOptions.new(opts),
         {:ok, command} <- build_command(exec_opts),
         {:ok, state} <- start_process(command, exec_opts),
         :ok <- send_prompt(state, input) do
      collect_events(state)
    end
  end

  @doc """
  Runs `codex exec review` and accumulates all emitted events.
  """
  @spec review(term(), exec_opts()) :: {:ok, map()} | {:error, term()}
  def review(target, opts) do
    with {:ok, exec_opts} <- ExecOptions.new(opts),
         {:ok, command_args} <- review_args(target),
         {:ok, command} <- build_command(exec_opts, command_args),
         {:ok, state} <- start_process(command, exec_opts),
         :ok <- send_prompt(state, "") do
      collect_events(state)
    end
  end

  @doc """
  Returns a lazy stream of events. The underlying process starts on first
  enumeration and stops automatically when the stream halts.
  """
  @spec run_stream(String.t(), exec_opts()) :: {:ok, Enumerable.t()} | {:error, term()}
  def run_stream(input, opts) when is_binary(input) do
    with {:ok, exec_opts} <- ExecOptions.new(opts),
         {:ok, command} <- build_command(exec_opts) do
      starter = fn -> start_process(command, exec_opts) end
      {:ok, build_stream(starter, input)}
    end
  end

  @doc """
  Returns a lazy stream of events for `codex exec review`.
  """
  @spec review_stream(term(), exec_opts()) :: {:ok, Enumerable.t()} | {:error, term()}
  def review_stream(target, opts) do
    with {:ok, exec_opts} <- ExecOptions.new(opts),
         {:ok, command_args} <- review_args(target),
         {:ok, command} <- build_command(exec_opts, command_args) do
      starter = fn -> start_process(command, exec_opts) end
      {:ok, build_stream(starter, "")}
    end
  end

  @doc """
  Cancels any in-flight exec processes associated with the provided cancellation token.
  """
  @spec cancel(String.t()) :: :ok
  def cancel(token) when is_binary(token) and token != "" do
    token
    |> transports_for_token()
    |> Enum.each(fn transport ->
      _ = IOTransport.interrupt(transport)
      _ = IOTransport.force_close(transport)
    end)

    :ok
  end

  def cancel(_token), do: :ok

  defp start_process([binary_path | args], exec_opts) do
    env = build_env(exec_opts)
    timeout_ms = resolve_timeout_ms(exec_opts)
    idle_timeout_ms = resolve_idle_timeout_ms(exec_opts)
    transport_ref = make_ref()

    transport_opts =
      [
        command: binary_path,
        args: args,
        env: env,
        subscriber: {self(), transport_ref},
        headless_timeout_ms: :infinity
      ]

    case IOTransport.start_link(transport_opts) do
      {:ok, transport} ->
        state = %{
          transport: transport,
          transport_ref: transport_ref,
          exec_opts: exec_opts,
          non_json_stdout: [],
          stderr: "",
          done?: false,
          timeout_ms: timeout_ms,
          idle_timeout_ms: idle_timeout_ms,
          cancellation_token: exec_opts.cancellation_token
        }

        :ok = maybe_register_cancellation(state.cancellation_token, transport)
        {:ok, state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp send_prompt(%{transport: transport}, input) do
    case IOTransport.send(transport, input) do
      :ok -> IOTransport.end_input(transport)
      {:error, _} = error -> error
    end
  end

  defp collect_events(state) do
    do_collect(state, [])
  end

  defp do_collect(%{timeout_ms: timeout_ms, transport_ref: ref} = state, events) do
    receive do
      {:codex_io_transport, ^ref, {:message, line}} ->
        {decoded, non_json} = decode_event_line_pair(line, state.exec_opts)

        do_collect(
          %{state | non_json_stdout: state.non_json_stdout ++ non_json},
          events ++ decoded
        )

      {:codex_io_transport, ^ref, {:stderr, data}} ->
        do_collect(%{state | stderr: state.stderr <> data}, events)

      {:codex_io_transport, ^ref, {:error, reason}} ->
        Logger.warning("Transport error during collect: #{inspect(reason)}")
        do_collect(state, events)

      {:codex_io_transport, ^ref, {:exit, reason}} ->
        maybe_unregister_cancellation(state)

        case exit_status_from_reason(reason) do
          {:ok, 0} ->
            {:ok, %{events: events}}

          {:ok, status} ->
            {:error, TransportError.new(status, stderr: state.stderr)}

          {:error, down_reason} ->
            {:error,
             TransportError.new(-1,
               message: "codex executable exited: #{inspect(down_reason)}",
               stderr: state.stderr,
               retryable?: false
             )}
        end
    after
      timeout_ms ->
        Logger.warning("codex exec timed out after #{timeout_ms}ms without output")
        safe_stop(state)
        {:error, {:codex_timeout, timeout_ms}}
    end
  end

  defp build_stream(starter, input) when is_function(starter, 0) and is_binary(input) do
    Stream.resource(
      fn ->
        case starter.() do
          {:ok, state} ->
            :ok = send_prompt(state, input)
            state

          {:error, reason} ->
            {:error, reason}
        end
      end,
      &next_stream_chunk_safe/1,
      &safe_stop/1
    )
  end

  defp next_stream_chunk_safe({:error, reason}) do
    raise TransportError.new(-1,
            message: "failed to start codex exec stream",
            stderr: inspect(reason)
          )
  end

  defp next_stream_chunk_safe(state), do: next_stream_chunk(state)

  defp next_stream_chunk(%{done?: true} = state), do: {:halt, state}

  defp next_stream_chunk(%{idle_timeout_ms: idle_timeout_ms, transport_ref: ref} = state) do
    timeout = idle_timeout_ms || :infinity

    receive do
      {:codex_io_transport, ^ref, {:message, line}} ->
        {decoded, non_json} = decode_event_line_pair(line, state.exec_opts)
        {decoded, %{state | non_json_stdout: state.non_json_stdout ++ non_json}}

      {:codex_io_transport, ^ref, {:stderr, data}} ->
        {[], %{state | stderr: state.stderr <> data}}

      {:codex_io_transport, ^ref, {:error, reason}} ->
        Logger.warning("Transport error during stream: #{inspect(reason)}")
        {[], state}

      {:codex_io_transport, ^ref, {:exit, reason}} ->
        maybe_unregister_cancellation(state)

        case exit_status_from_reason(reason) do
          {:ok, 0} ->
            {[], %{state | done?: true}}

          {:ok, status} ->
            raise TransportError.new(status, stderr: state.stderr)

          {:error, down_reason} ->
            raise TransportError.new(-1,
                    message: "codex executable exited: #{inspect(down_reason)}",
                    stderr: state.stderr,
                    retryable?: false
                  )
        end
    after
      timeout ->
        raise handle_stream_idle_timeout(state, idle_timeout_ms)
    end
  end

  defp handle_stream_idle_timeout(state, timeout_ms) do
    Logger.warning("codex exec stream idle timeout after #{timeout_ms}ms without output")
    safe_stop(state)

    TransportError.new(-1,
      message: "codex exec stream idle timeout after #{timeout_ms}ms",
      retryable?: true
    )
  end

  defp safe_stop({:error, _reason}), do: :ok

  defp safe_stop(%{transport: nil} = state) do
    maybe_unregister_cancellation(state)
    :ok
  end

  defp safe_stop(%{transport: transport, transport_ref: transport_ref} = state)
       when is_pid(transport) do
    maybe_unregister_cancellation(state)
    monitor_ref = Process.monitor(transport)
    _ = safe_force_close(transport)
    await_transport_down_or_shutdown(monitor_ref, transport, Defaults.transport_close_grace_ms())
    flush_transport_messages(transport_ref)
    :ok
  rescue
    _ -> :ok
  end

  defp safe_stop(%{transport: transport} = state) when is_pid(transport) do
    maybe_unregister_cancellation(state)
    _ = safe_force_close(transport)
    :ok
  rescue
    _ -> :ok
  end

  defp resolve_timeout_ms(%ExecOptions{timeout_ms: nil}), do: Defaults.exec_timeout_ms()
  defp resolve_timeout_ms(%ExecOptions{timeout_ms: timeout_ms}), do: timeout_ms

  defp resolve_idle_timeout_ms(%ExecOptions{stream_idle_timeout_ms: nil}), do: nil

  defp resolve_idle_timeout_ms(%ExecOptions{stream_idle_timeout_ms: timeout_ms})
       when is_integer(timeout_ms) and timeout_ms > 0 do
    timeout_ms
  end

  defp resolve_idle_timeout_ms(_), do: nil

  defp build_command(%ExecOptions{codex_opts: %Options{} = opts} = exec_opts, command_args \\ nil) do
    with {:ok, binary_path} <- Options.codex_path(opts),
         {:ok, args} <- build_args(exec_opts, command_args) do
      command = Enum.map([binary_path | args], &to_charlist/1)
      {:ok, command}
    end
  end

  defp build_args(%ExecOptions{codex_opts: %Options{} = codex_opts} = exec_opts, command_args) do
    command_args = command_args || command_args_for_run(exec_opts)

    with {:ok, config_args} <- config_override_args(exec_opts) do
      {:ok,
       ["exec", "--json"] ++
         profile_args(exec_opts) ++
         oss_args(exec_opts) ++
         local_provider_args(exec_opts) ++
         full_auto_args(exec_opts) ++
         dangerously_bypass_args(exec_opts) ++
         model_args(codex_opts) ++
         color_args(exec_opts) ++
         output_last_message_args(exec_opts) ++
         reasoning_effort_args(exec_opts) ++
         sandbox_args(exec_opts.thread) ++
         working_directory_args(exec_opts.thread) ++
         additional_directories_args(exec_opts.thread) ++
         skip_git_repo_check_args(exec_opts.thread) ++
         network_access_args(exec_opts.thread) ++
         ask_for_approval_args(exec_opts.thread) ++
         command_args ++
         continuation_args(exec_opts.continuation_token) ++
         cancellation_args(exec_opts.cancellation_token) ++
         attachment_args(exec_opts.attachments) ++
         schema_args(exec_opts.output_schema_path) ++
         config_args}
    end
  end

  defp command_args_for_run(%ExecOptions{} = exec_opts) do
    resume_args(exec_opts.thread)
  end

  defp profile_args(exec_opts) do
    case exec_opt(exec_opts, :profile) do
      value when is_binary(value) and value != "" -> ["--profile", value]
      _ -> []
    end
  end

  defp oss_args(exec_opts) do
    case exec_opt(exec_opts, :oss) do
      true -> ["--oss"]
      _ -> []
    end
  end

  defp local_provider_args(exec_opts) do
    case exec_opt(exec_opts, :local_provider) do
      value when is_binary(value) and value != "" -> ["--local-provider", value]
      _ -> []
    end
  end

  defp full_auto_args(exec_opts) do
    case exec_opt(exec_opts, :full_auto) do
      true -> ["--full-auto"]
      _ -> []
    end
  end

  defp dangerously_bypass_args(exec_opts) do
    case exec_opt(exec_opts, :dangerously_bypass_approvals_and_sandbox) do
      true -> ["--dangerously-bypass-approvals-and-sandbox"]
      _ -> []
    end
  end

  defp model_args(%Options{model: model}) when is_binary(model) and model != "" do
    ["--model", model]
  end

  defp model_args(_), do: []

  defp color_args(exec_opts) do
    case exec_opt(exec_opts, :color) do
      :auto -> ["--color", "auto"]
      :always -> ["--color", "always"]
      :never -> ["--color", "never"]
      value when is_binary(value) and value != "" -> ["--color", value]
      _ -> []
    end
  end

  defp output_last_message_args(exec_opts) do
    case exec_opt(exec_opts, :output_last_message) do
      value when is_binary(value) and value != "" -> ["--output-last-message", value]
      _ -> []
    end
  end

  defp reasoning_effort_args(%ExecOptions{codex_opts: %Options{} = opts} = exec_opts) do
    case resolve_reasoning_effort(opts, config_cwd(exec_opts)) do
      nil ->
        []

      effort ->
        stringified = Models.reasoning_effort_to_string(effort)
        ["--config", ~s(model_reasoning_effort="#{stringified}")]
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

  defp sandbox_args(%{thread_opts: %Codex.Thread.Options{} = opts}) do
    case sandbox_mode(opts.sandbox) do
      nil -> []
      mode -> ["--sandbox", mode]
    end
  end

  defp sandbox_args(_), do: []

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

  defp working_directory_args(%{thread_opts: %Codex.Thread.Options{working_directory: dir}})
       when is_binary(dir) and dir != "" do
    ["--cd", dir]
  end

  defp working_directory_args(_), do: []

  defp additional_directories_args(%{
         thread_opts: %Codex.Thread.Options{additional_directories: dirs}
       })
       when is_list(dirs) and dirs != [] do
    Enum.flat_map(dirs, fn
      dir when is_binary(dir) and dir != "" -> ["--add-dir", dir]
      _ -> []
    end)
  end

  defp additional_directories_args(_), do: []

  defp skip_git_repo_check_args(%{thread_opts: %Codex.Thread.Options{skip_git_repo_check: true}}),
    do: ["--skip-git-repo-check"]

  defp skip_git_repo_check_args(_), do: []

  defp network_access_args(%{
         thread_opts: %Codex.Thread.Options{sandbox: {:external_sandbox, network_access}}
       }) do
    # For external_sandbox, network_access is part of the sandbox policy
    # and is passed via config
    case network_access do
      :enabled -> ["--config", "sandbox_external.network_access=true"]
      :restricted -> ["--config", "sandbox_external.network_access=false"]
      _ -> []
    end
  end

  defp network_access_args(%{thread_opts: %Codex.Thread.Options{network_access_enabled: value}})
       when value in [true, false] do
    ["--config", "sandbox_workspace_write.network_access=#{value}"]
  end

  defp network_access_args(_), do: []

  defp ask_for_approval_args(%{thread_opts: %Codex.Thread.Options{ask_for_approval: nil}}), do: []

  defp ask_for_approval_args(%{thread_opts: %Codex.Thread.Options{ask_for_approval: policy}}) do
    case approval_policy(policy) do
      nil -> []
      value -> ["--config", ~s(approval_policy="#{value}")]
    end
  end

  defp ask_for_approval_args(_), do: []

  defp approval_policy(:untrusted), do: "untrusted"
  defp approval_policy(:on_failure), do: "on-failure"
  defp approval_policy(:on_request), do: "on-request"
  defp approval_policy(:never), do: "never"
  defp approval_policy("untrusted"), do: "untrusted"
  defp approval_policy("on-failure"), do: "on-failure"
  defp approval_policy("on-request"), do: "on-request"
  defp approval_policy("never"), do: "never"
  defp approval_policy(nil), do: nil
  defp approval_policy(value) when is_binary(value), do: value
  defp approval_policy(_), do: nil

  defp resume_args(%{thread_id: thread_id}) when is_binary(thread_id), do: ["resume", thread_id]
  defp resume_args(%{resume: :last}), do: ["resume", "--last"]
  defp resume_args(_), do: []

  defp continuation_args(token) when is_binary(token) and token != "",
    do: ["--continuation-token", token]

  defp continuation_args(_), do: []

  defp cancellation_args(token) when is_binary(token) and token != "",
    do: ["--cancellation-token", token]

  defp cancellation_args(_), do: []

  defp attachment_args(attachments) do
    attachments
    |> List.wrap()
    |> Enum.flat_map(&attachment_cli_args/1)
  end

  defp schema_args(path) when is_binary(path) and path != "", do: ["--output-schema", path]
  defp schema_args(_), do: []

  defp attachment_cli_args(%Attachment{} = attachment) do
    ["--image", attachment.path]
  end

  defp attachment_cli_args(_), do: []

  defp config_override_args(exec_opts) do
    with {:ok, global_overrides} <- global_config_overrides(exec_opts),
         {:ok, thread_overrides} <- thread_config_overrides(exec_opts),
         {:ok, turn_overrides} <- turn_config_overrides(exec_opts) do
      derived_overrides = derived_config_overrides(exec_opts)

      {:ok,
       (global_overrides ++ derived_overrides ++ thread_overrides ++ turn_overrides)
       |> Overrides.cli_args()}
    end
  end

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

  defp build_env(%ExecOptions{codex_opts: %Options{} = opts, env: env} = exec_opts) do
    base_env =
      RuntimeEnv.base_overrides(opts.api_key, opts.base_url)

    merged =
      base_env
      |> Map.merge(env, fn _key, _base, custom -> custom end)

    merged_list = RuntimeEnv.to_charlist_env(merged)

    if clear_env?(exec_opts) do
      preserve = preserved_env()
      [:clear | preserve ++ merged_list]
    else
      if merged_list == [] do
        []
      else
        preserve = preserved_env()
        preserve ++ merged_list
      end
    end
  end

  defp clear_env?(%ExecOptions{clear_env?: value}) when is_boolean(value), do: value
  defp clear_env?(%ExecOptions{}), do: false

  defp preserved_env do
    Defaults.preserved_env_keys()
    |> Enum.reduce([], fn key, acc ->
      case System.get_env(key) do
        nil -> acc
        value -> [{key, value} | acc]
      end
    end)
    |> Enum.reverse()
  end

  defp decode_event_line_pair(line, exec_opts) when is_binary(line) do
    case Jason.decode(line) do
      {:ok, decoded} ->
        case decode_event_map(decoded, exec_opts) do
          {:ok, event} -> {[event], []}
          {:error, _reason} -> {[], [line]}
        end

      {:error, reason} ->
        Logger.warning("Failed to decode codex event: #{inspect(reason)} (#{line})")
        {[], [line]}
    end
  end

  defp decode_event_map(decoded, exec_opts) do
    event = Events.parse!(decoded)
    {:ok, enrich_event(event, exec_opts)}
  rescue
    error in ArgumentError ->
      Logger.warning("Unsupported codex event: #{Exception.message(error)}")
      {:error, :unsupported_event}
  end

  defp enrich_event(%Events.ThreadStarted{} = event, %ExecOptions{codex_opts: %Options{} = opts}) do
    %Events.ThreadStarted{
      event
      | metadata: enrich_thread_started_metadata(event.metadata, opts)
    }
  end

  defp enrich_event(event, _exec_opts), do: event

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

  defp normalize_string(value) when is_binary(value) and value != "", do: value
  defp normalize_string(_), do: nil

  defp normalize_reasoning(value) when is_atom(value) do
    case Models.normalize_reasoning_effort(value) do
      {:ok, effort} when is_atom(effort) and not is_nil(effort) ->
        Models.reasoning_effort_to_string(effort)

      _ ->
        nil
    end
  end

  defp normalize_reasoning(value) when is_binary(value) and value != "", do: value
  defp normalize_reasoning(_), do: nil

  defp put_if_missing(map, _key, nil), do: map

  defp put_if_missing(map, key, value) do
    if Map.has_key?(map, key), do: map, else: Map.put(map, key, value)
  end

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

  defp exit_status_from_reason(:normal), do: {:ok, 0}

  defp exit_status_from_reason({:exit_status, status}) do
    {:ok, normalize_exit_status(status)}
  end

  defp exit_status_from_reason(status) when is_integer(status) do
    {:ok, normalize_exit_status(status)}
  end

  defp exit_status_from_reason(reason), do: {:error, reason}

  defp normalize_exit_status(raw_status) when is_integer(raw_status) do
    case :exec.status(raw_status) do
      {:status, code} -> code
      {:signal, signal, _core?} -> 128 + :exec.signal_to_int(signal)
    end
  rescue
    _ -> raw_status
  end

  defp normalize_exit_status(raw_status), do: raw_status

  defp flush_transport_messages(ref) when is_reference(ref) do
    receive do
      {:codex_io_transport, ^ref, _event} ->
        flush_transport_messages(ref)
    after
      0 ->
        :ok
    end
  end

  defp flush_transport_messages(_other), do: :ok

  defp await_transport_down_or_shutdown(ref, transport, timeout_ms) do
    case await_transport_down(ref, transport, timeout_ms) do
      :down ->
        :ok

      :timeout ->
        safe_shutdown(transport)
        await_transport_down_or_kill(ref, transport, Defaults.transport_shutdown_grace_ms())
    end
  end

  defp await_transport_down_or_kill(ref, transport, timeout_ms) do
    case await_transport_down(ref, transport, timeout_ms) do
      :down ->
        :ok

      :timeout ->
        safe_kill(transport)
        await_transport_down_or_demonitor(ref, transport, Defaults.transport_kill_grace_ms())
    end
  end

  defp await_transport_down_or_demonitor(ref, transport, timeout_ms) do
    case await_transport_down(ref, transport, timeout_ms) do
      :down ->
        :ok

      :timeout ->
        Process.demonitor(ref, [:flush])
        :ok
    end
  end

  defp await_transport_down(ref, transport, timeout_ms)
       when is_reference(ref) and is_pid(transport) and is_integer(timeout_ms) and timeout_ms >= 0 do
    receive do
      {:DOWN, ^ref, :process, ^transport, _reason} ->
        :down
    after
      timeout_ms ->
        :timeout
    end
  end

  defp safe_force_close(transport) when is_pid(transport) do
    IOTransport.force_close(transport)
  catch
    :exit, _ ->
      {:error, {:transport, :not_connected}}
  end

  defp safe_shutdown(transport) when is_pid(transport) do
    Process.exit(transport, :shutdown)
    :ok
  catch
    :exit, _ -> :ok
  end

  defp safe_kill(transport) when is_pid(transport) do
    Process.exit(transport, :kill)
    :ok
  catch
    :exit, _ -> :ok
  end

  defp maybe_register_cancellation(token, transport)
       when is_binary(token) and token != "" and is_pid(transport) do
    CancellationRegistry.register(token, transport)
  end

  defp maybe_register_cancellation(_token, _transport), do: :ok

  defp maybe_unregister_cancellation(%{cancellation_token: token, transport: transport}) do
    maybe_unregister_cancellation(token, transport)
  end

  defp maybe_unregister_cancellation(%{cancellation_token: token}) do
    maybe_unregister_cancellation(token, nil)
  end

  defp maybe_unregister_cancellation(_state), do: :ok

  defp maybe_unregister_cancellation(token, transport)
       when is_binary(token) and token != "" do
    CancellationRegistry.unregister(token, transport)
  end

  defp maybe_unregister_cancellation(_token, _transport), do: :ok

  defp transports_for_token(token) do
    CancellationRegistry.transports_for_token(token)
  end

  defp review_args(:uncommitted_changes), do: {:ok, ["review", "--uncommitted"]}
  defp review_args({:uncommitted_changes}), do: {:ok, ["review", "--uncommitted"]}

  defp review_args({:base_branch, branch}) when is_binary(branch) and branch != "" do
    {:ok, ["review", "--base", branch]}
  end

  defp review_args({:commit, sha}) when is_binary(sha) and sha != "" do
    {:ok, ["review", "--commit", sha]}
  end

  defp review_args({:commit, sha, title}) when is_binary(sha) and sha != "" do
    args =
      ["review", "--commit", sha]
      |> maybe_append_title(title)

    {:ok, args}
  end

  defp review_args({:custom, instructions}) when is_binary(instructions) do
    instructions = String.trim(instructions)

    if instructions == "" do
      {:error, {:invalid_review_target, instructions}}
    else
      {:ok, ["review", instructions]}
    end
  end

  defp review_args(instructions) when is_binary(instructions) do
    review_args({:custom, instructions})
  end

  defp review_args(other), do: {:error, {:invalid_review_target, other}}

  defp maybe_append_title(args, title) when is_binary(title) and title != "" do
    args ++ ["--title", title]
  end

  defp maybe_append_title(args, _title), do: args

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
end
