defmodule Codex.Exec do
  @moduledoc """
  Process manager wrapping the `codex` binary via erlexec.

  Provides blocking and streaming helpers that decode JSONL event output into
  typed `%Codex.Events{}` structs.
  """

  require Logger

  alias Codex.Events
  alias Codex.Exec.Options, as: ExecOptions
  alias Codex.Files.Attachment
  alias Codex.Models
  alias Codex.Options
  alias Codex.TransportError

  @default_timeout_ms 3_600_000
  @default_preserved_env_keys ~w(
    HOME
    USER
    LOGNAME
    PATH
    LANG
    LC_ALL
    TMPDIR
    CODEX_HOME
    XDG_CONFIG_HOME
    XDG_CACHE_HOME
  )

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
         :ok <- ensure_erlexec_started(),
         {:ok, command} <- build_command(exec_opts),
         {:ok, state} <- start_process(command, exec_opts),
         :ok <- send_prompt(state, input) do
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
         :ok <- ensure_erlexec_started(),
         {:ok, command} <- build_command(exec_opts),
         {:ok, state} <- start_process(command, exec_opts),
         :ok <- send_prompt(state, input) do
      {:ok, build_stream(state)}
    end
  end

  defp ensure_erlexec_started do
    case Application.ensure_all_started(:erlexec) do
      {:ok, _apps} -> :ok
      {:error, {:erlexec, {:already_started, _pid}}} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp start_process(command, exec_opts) do
    env = build_env(exec_opts)
    timeout_ms = resolve_timeout_ms(exec_opts)

    run_opts =
      [:stdin, {:stdout, self()}, {:stderr, self()}, :monitor]
      |> maybe_put_env(env)

    case :exec.run(command, run_opts) do
      {:ok, pid, os_pid} ->
        {:ok,
         %{
           pid: pid,
           os_pid: os_pid,
           buffer: "",
           non_json_stdout: [],
           stderr: [],
           done?: false,
           timeout_ms: timeout_ms
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp send_prompt(%{pid: pid}, input) do
    :ok = :exec.send(pid, input <> "\n")
    :ok = :exec.send(pid, :eof)
    :ok
  end

  defp collect_events(%{os_pid: os_pid} = state) do
    do_collect(state, os_pid, [])
  end

  defp do_collect(%{timeout_ms: timeout_ms} = state, os_pid, events) do
    receive do
      {:stdout, ^os_pid, chunk} ->
        {decoded, new_buffer, non_json} = decode_lines(state.buffer <> iodata_to_binary(chunk))

        do_collect(
          %{state | buffer: new_buffer, non_json_stdout: state.non_json_stdout ++ non_json},
          os_pid,
          events ++ decoded
        )

      {:stderr, ^os_pid, chunk} ->
        do_collect(%{state | stderr: [chunk | state.stderr]}, os_pid, events)

      {:DOWN, ^os_pid, :process, _pid, :normal} ->
        {decoded, _, _} = decode_lines(state.buffer)
        {:ok, %{events: events ++ decoded}}

      {:DOWN, ^os_pid, :process, _pid, {:exit_status, status}} ->
        stderr = state.stderr |> Enum.reverse() |> IO.iodata_to_binary()
        non_json = state.non_json_stdout |> Enum.map_join("\n", & &1)

        merged_stderr =
          if String.trim(non_json) == "" do
            stderr
          else
            [stderr, "\n\n(unparsed stdout)\n", non_json, "\n"]
            |> IO.iodata_to_binary()
          end

        {:error, TransportError.new(normalize_exit_status(status), stderr: merged_stderr)}
    after
      timeout_ms ->
        Logger.warning("codex exec timed out after #{timeout_ms}ms without output")
        safe_stop(state)
        {:error, {:codex_timeout, timeout_ms}}
    end
  end

  defp build_stream(state) do
    Stream.resource(
      fn -> state end,
      &next_stream_chunk/1,
      &safe_stop/1
    )
  end

  defp next_stream_chunk(%{done?: true} = state), do: {:halt, state}

  defp next_stream_chunk(%{os_pid: os_pid} = state) do
    receive do
      {:stdout, ^os_pid, chunk} ->
        data = state.buffer <> iodata_to_binary(chunk)
        {decoded, new_buffer, non_json} = decode_lines(data)

        {decoded,
         %{state | buffer: new_buffer, non_json_stdout: state.non_json_stdout ++ non_json}}

      {:stderr, ^os_pid, chunk} ->
        {[], %{state | stderr: [chunk | state.stderr]}}

      {:DOWN, ^os_pid, :process, _pid, :normal} ->
        {decoded, _, _} = decode_lines(state.buffer)
        {decoded, %{state | buffer: "", done?: true}}

      {:DOWN, ^os_pid, :process, _pid, {:exit_status, status}} ->
        stderr = state.stderr |> Enum.reverse() |> IO.iodata_to_binary()
        non_json = state.non_json_stdout |> Enum.map_join("\n", & &1)

        merged_stderr =
          if String.trim(non_json) == "" do
            stderr
          else
            [stderr, "\n\n(unparsed stdout)\n", non_json, "\n"]
            |> IO.iodata_to_binary()
          end

        raise TransportError.new(normalize_exit_status(status), stderr: merged_stderr)
    end
  end

  defp safe_stop(%{pid: nil}), do: :ok

  defp safe_stop(%{pid: pid}) do
    if Process.alive?(pid) do
      :exec.stop(pid)
    else
      :ok
    end
  rescue
    _ -> :ok
  end

  defp resolve_timeout_ms(%ExecOptions{timeout_ms: nil}), do: @default_timeout_ms
  defp resolve_timeout_ms(%ExecOptions{timeout_ms: timeout_ms}), do: timeout_ms

  defp build_command(%ExecOptions{codex_opts: %Options{} = opts} = exec_opts) do
    with {:ok, binary_path} <- Options.codex_path(opts) do
      args = build_args(exec_opts)
      command = Enum.map([binary_path | args], &to_charlist/1)
      {:ok, command}
    end
  end

  defp build_args(%ExecOptions{codex_opts: %Options{} = codex_opts} = exec_opts) do
    ["exec", "--experimental-json"] ++
      model_args(codex_opts) ++
      reasoning_effort_args(codex_opts) ++
      sandbox_args(exec_opts.thread) ++
      working_directory_args(exec_opts.thread) ++
      additional_directories_args(exec_opts.thread) ++
      skip_git_repo_check_args(exec_opts.thread) ++
      network_access_args(exec_opts.thread) ++
      ask_for_approval_args(exec_opts.thread) ++
      web_search_args(exec_opts.thread) ++
      resume_args(exec_opts.thread) ++
      continuation_args(exec_opts.continuation_token) ++
      cancellation_args(exec_opts.cancellation_token) ++
      attachment_args(exec_opts.attachments) ++
      schema_args(exec_opts.output_schema_path)
  end

  defp model_args(%Options{model: model}) when is_binary(model) and model != "" do
    ["--model", model]
  end

  defp model_args(_), do: []

  defp reasoning_effort_args(%Options{reasoning_effort: effort}) when not is_nil(effort) do
    stringified = Models.reasoning_effort_to_string(effort)
    ["--config", ~s(model_reasoning_effort="#{stringified}")]
  end

  defp reasoning_effort_args(_), do: []

  defp sandbox_args(%{thread_opts: %Codex.Thread.Options{} = opts}) do
    case sandbox_mode(opts.sandbox) do
      nil -> []
      mode -> ["--sandbox", mode]
    end
  end

  defp sandbox_args(_), do: []

  defp sandbox_mode(:strict), do: "read-only"
  defp sandbox_mode(:default), do: "workspace-write"
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

  defp web_search_args(%{thread_opts: %Codex.Thread.Options{web_search_enabled: value}})
       when value in [true, false] do
    ["--config", "features.web_search_request=#{value}"]
  end

  defp web_search_args(_), do: []

  defp resume_args(%{thread_id: thread_id}) when is_binary(thread_id), do: ["resume", thread_id]
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

  defp build_env(%ExecOptions{codex_opts: %Options{} = opts, env: env} = exec_opts) do
    base_env =
      []
      |> maybe_put_key("CODEX_API_KEY", opts.api_key)
      |> maybe_put_key("OPENAI_API_KEY", opts.api_key)
      |> maybe_put_key(
        "OPENAI_BASE_URL",
        if(opts.base_url != "https://api.openai.com/v1", do: opts.base_url, else: nil)
      )
      |> Map.new()

    merged =
      base_env
      |> Map.merge(env, fn _key, _base, custom -> custom end)

    merged_list = Enum.map(merged, fn {key, value} -> {key, value} end)

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
    @default_preserved_env_keys
    |> Enum.reduce([], fn key, acc ->
      case System.get_env(key) do
        nil -> acc
        value -> [{key, value} | acc]
      end
    end)
    |> Enum.reverse()
  end

  defp maybe_put_key(env, _key, nil), do: env
  defp maybe_put_key(env, _key, ""), do: env
  defp maybe_put_key(env, key, value), do: [{key, value} | env]

  defp maybe_put_env(opts, []), do: opts
  defp maybe_put_env(opts, env), do: [{:env, env} | opts]

  defp decode_lines(data) do
    {lines, rest} = split_lines(data)
    {events, non_json} = decode_event_lines(lines)
    {events, rest, non_json}
  end

  defp split_lines(data) do
    parts = String.split(data, "\n", trim: false)

    case parts do
      [] -> {[], data}
      [single] -> {[], single}
      _ -> {Enum.drop(parts, -1), List.last(parts)}
    end
  end

  defp decode_event_lines(lines) do
    lines
    |> Enum.reject(&(&1 == ""))
    |> Enum.reduce({[], []}, fn line, {events, raw} ->
      case decode_line(line) do
        {:ok, event} -> {[event | events], raw}
        {:non_json, raw_line} -> {events, [raw_line | raw]}
      end
    end)
    |> then(fn {events, raw} -> {Enum.reverse(events), Enum.reverse(raw)} end)
  end

  defp decode_line(line) do
    case Jason.decode(line) do
      {:ok, decoded} ->
        try do
          {:ok, Events.parse!(decoded)}
        rescue
          error in ArgumentError ->
            Logger.warning("Unsupported codex event: #{Exception.message(error)}")
            {:non_json, line}
        end

      {:error, reason} ->
        Logger.warning("Failed to decode codex event: #{inspect(reason)} (#{line})")
        {:non_json, line}
    end
  end

  defp iodata_to_binary(data) when is_binary(data), do: data
  defp iodata_to_binary(data), do: IO.iodata_to_binary(data)

  defp normalize_exit_status(raw_status) when is_integer(raw_status) do
    case :exec.status(raw_status) do
      {:status, code} -> code
      {:signal, signal, _core?} -> 128 + :exec.signal_to_int(signal)
    end
  rescue
    _ -> raw_status
  end

  defp normalize_exit_status(raw_status), do: raw_status
end
