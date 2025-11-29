defmodule Codex.Exec do
  @moduledoc """
  Process manager wrapping the `codex` binary via erlexec.

  Provides blocking and streaming helpers that decode JSONL event output into
  typed `%Codex.Events{}` structs.
  """

  require Logger

  alias Codex.Events
  alias Codex.Files.Attachment
  alias Codex.Exec.Options, as: ExecOptions
  alias Codex.Models
  alias Codex.Options
  alias Codex.TransportError

  @default_timeout_ms 3_600_000

  @type exec_opts ::
          ExecOptions.t()
          | %{
              optional(:codex_opts) => Options.t(),
              optional(:thread) => Codex.Thread.t(),
              optional(:turn_opts) => map(),
              optional(:continuation_token) => String.t(),
              optional(:attachments) => [Attachment.t()],
              optional(:output_schema_path) => String.t(),
              optional(:tool_outputs) => [map()],
              optional(:tool_failures) => [map()],
              optional(:env) => map(),
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
         :ok <- send_prompt(state, input),
         {:ok, data} <- collect_events(state) do
      {:ok, data}
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
        {decoded, new_buffer} = decode_lines(state.buffer <> iodata_to_binary(chunk))
        do_collect(%{state | buffer: new_buffer}, os_pid, events ++ decoded)

      {:stderr, ^os_pid, chunk} ->
        do_collect(%{state | stderr: [chunk | state.stderr]}, os_pid, events)

      {:DOWN, ^os_pid, :process, _pid, :normal} ->
        {decoded, _} = decode_lines(state.buffer)
        {:ok, %{events: events ++ decoded}}

      {:DOWN, ^os_pid, :process, _pid, {:exit_status, status}} ->
        stderr = state.stderr |> Enum.reverse() |> IO.iodata_to_binary()
        {:error, TransportError.new(normalize_exit_status(status), stderr: stderr)}
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
        {decoded, new_buffer} = decode_lines(data)
        {decoded, %{state | buffer: new_buffer}}

      {:stderr, ^os_pid, chunk} ->
        {[], %{state | stderr: [chunk | state.stderr]}}

      {:DOWN, ^os_pid, :process, _pid, :normal} ->
        {decoded, _} = decode_lines(state.buffer)
        {decoded, %{state | buffer: "", done?: true}}

      {:DOWN, ^os_pid, :process, _pid, {:exit_status, status}} ->
        stderr = state.stderr |> Enum.reverse() |> IO.iodata_to_binary()
        raise TransportError.new(normalize_exit_status(status), stderr: stderr)
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

  defp build_command(_), do: {:error, :missing_options}

  defp build_args(%ExecOptions{codex_opts: %Options{} = codex_opts} = exec_opts) do
    base = ["exec", "--experimental-json"]

    model_args =
      case codex_opts do
        %Options{model: model} when is_binary(model) and model != "" -> ["--model", model]
        _ -> []
      end

    config_args =
      case codex_opts do
        %Options{reasoning_effort: effort} when not is_nil(effort) ->
          stringified = effort |> Models.reasoning_effort_to_string()
          ["--config", ~s(model_reasoning_effort="#{stringified}")]

        _ ->
          []
      end

    resume_args =
      case exec_opts.thread do
        %{thread_id: thread_id} when is_binary(thread_id) -> ["resume", thread_id]
        _ -> []
      end

    continuation_args =
      case exec_opts.continuation_token do
        token when is_binary(token) and token != "" -> ["--continuation-token", token]
        _ -> []
      end

    attachment_args =
      exec_opts.attachments
      |> List.wrap()
      |> Enum.flat_map(&attachment_cli_args/1)

    schema_args =
      case exec_opts.output_schema_path do
        path when is_binary(path) and path != "" -> ["--output-schema", path]
        _ -> []
      end

    cancellation_args =
      case exec_opts.cancellation_token do
        token when is_binary(token) and token != "" -> ["--cancellation-token", token]
        _ -> []
      end

    # Forward pending tool responses so codex exec can replay them when resuming
    # a continuation. The CLI accepts repeated --tool-output/--tool-failure flags
    # with JSON bodies (mirrors Python/TypeScript SDK behaviour).
    tool_output_args =
      exec_opts.tool_outputs
      |> Enum.flat_map(&tool_payload_args("--tool-output", &1, [:call_id, :output]))

    tool_failure_args =
      exec_opts.tool_failures
      |> Enum.flat_map(&tool_payload_args("--tool-failure", &1, [:call_id, :reason]))

    base ++
      model_args ++
      config_args ++
      resume_args ++
      continuation_args ++
      cancellation_args ++
      attachment_args ++
      schema_args ++
      tool_output_args ++
      tool_failure_args
  end

  defp attachment_cli_args(%Attachment{} = attachment) do
    [
      "--attachment",
      attachment.path,
      "--attachment-name",
      attachment.name,
      "--attachment-checksum",
      attachment.checksum
    ]
  end

  defp attachment_cli_args(_), do: []

  defp build_env(%ExecOptions{codex_opts: %Options{} = opts, env: env}) do
    base_env =
      []
      |> maybe_put_key("CODEX_API_KEY", opts.api_key)
      |> maybe_put_key("OPENAI_API_KEY", opts.api_key)
      |> maybe_put_key("CODEX_INTERNAL_ORIGINATOR_OVERRIDE", "codex_sdk_elixir")
      |> Map.new()

    base_env
    |> Map.merge(env, fn _key, _base, custom -> custom end)
    |> Enum.map(fn {key, value} -> {key, value} end)
  end

  defp build_env(_), do: []

  defp maybe_put_key(env, _key, nil), do: env
  defp maybe_put_key(env, _key, ""), do: env
  defp maybe_put_key(env, key, value), do: [{key, value} | env]

  defp maybe_put_env(opts, []), do: opts
  defp maybe_put_env(opts, env), do: [{:env, env} | opts]

  defp decode_lines(data) do
    case String.split(data, "\n", trim: false) do
      [] ->
        {[], data}

      [single] ->
        {[], single}

      parts ->
        {maybe_lines, [last]} = Enum.split(parts, -1)

        decoded =
          maybe_lines
          |> Enum.reject(&(&1 == ""))
          |> Enum.map(&decode_line/1)
          |> Enum.reject(&is_nil/1)

        {decoded, last}
    end
  end

  defp decode_line(line) do
    case Jason.decode(line) do
      {:ok, decoded} ->
        try do
          Events.parse!(decoded)
        rescue
          error in ArgumentError ->
            Logger.warning("Unsupported codex event: #{Exception.message(error)}")
            nil
        end

      {:error, reason} ->
        Logger.warning("Failed to decode codex event: #{inspect(reason)} (#{line})")
        nil
    end
  end

  defp iodata_to_binary(data) when is_binary(data), do: data
  defp iodata_to_binary(data), do: IO.iodata_to_binary(data)

  defp normalize_exit_status(raw_status) do
    case :exec.status(raw_status) do
      {:exit_status, code} -> code
      {:status, code} -> code
      {:signal, signal, _core?} -> {:signal, signal}
      other -> other
    end
  rescue
    _ -> raw_status
  end

  defp tool_payload_args(_flag, payload, _keys) when payload in [nil, %{}], do: []

  defp tool_payload_args(flag, payload, required_keys) when is_map(payload) do
    normalized = normalize_tool_payload(payload)
    payload_map = Map.take(normalized, required_keys)

    if Enum.all?(required_keys, &Map.has_key?(payload_map, &1)) do
      encoded =
        normalized
        |> Map.take(required_keys)
        |> stringify_keys()
        |> Jason.encode!()

      [flag, encoded]
    else
      []
    end
  end

  defp tool_payload_args(_flag, _payload, _keys), do: []

  defp normalize_tool_payload(%_struct{} = struct) do
    struct
    |> Map.from_struct()
    |> Map.delete(:__struct__)
    |> normalize_tool_payload()
  end

  defp normalize_tool_payload(map) when is_map(map) do
    Map.new(map, fn {key, value} ->
      {key, normalize_tool_value(value)}
    end)
  end

  defp normalize_tool_payload(other), do: other

  defp normalize_tool_value(%_struct{} = value),
    do: value |> Map.from_struct() |> normalize_tool_payload()

  defp normalize_tool_value(map) when is_map(map), do: normalize_tool_payload(map)

  defp normalize_tool_value(list) when is_list(list), do: Enum.map(list, &normalize_tool_value/1)

  defp normalize_tool_value(value), do: value

  defp stringify_keys(%_struct{} = struct), do: stringify_keys(Map.from_struct(struct))

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} ->
      {stringify_key(key), stringify_keys(value)}
    end)
  end

  defp stringify_keys(list) when is_list(list), do: Enum.map(list, &stringify_keys/1)

  defp stringify_keys(value), do: value

  defp stringify_key(key) when is_atom(key), do: Atom.to_string(key)
  defp stringify_key(key) when is_binary(key), do: key
  defp stringify_key(key), do: to_string(key)
end
