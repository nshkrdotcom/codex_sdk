defmodule Codex.Exec do
  @moduledoc """
  Process manager wrapping the `codex` binary via erlexec.

  Provides blocking and streaming helpers that decode JSONL event output into
  typed `%Codex.Events{}` structs.
  """

  require Logger

  alias Codex.Events
  alias Codex.Files.Attachment
  alias Codex.Options
  alias Codex.TransportError

  @type exec_opts :: %{
          optional(:codex_opts) => Options.t(),
          optional(:thread) => Codex.Thread.t(),
          optional(:turn_opts) => map(),
          optional(:continuation_token) => String.t(),
          optional(:attachments) => [Attachment.t()]
        }

  @doc """
  Runs codex in blocking mode and accumulates all emitted events.
  """
  @spec run(String.t(), exec_opts()) :: {:ok, map()} | {:error, term()}
  def run(input, opts) when is_binary(input) and is_map(opts) do
    with :ok <- ensure_erlexec_started(),
         {:ok, command} <- build_command(opts),
         {:ok, state} <- start_process(command, opts),
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
  def run_stream(input, opts) when is_binary(input) and is_map(opts) do
    with :ok <- ensure_erlexec_started(),
         {:ok, command} <- build_command(opts),
         {:ok, state} <- start_process(command, opts),
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

    exec_opts =
      [:stdin, {:stdout, self()}, {:stderr, self()}, :monitor]
      |> maybe_put_env(env)

    case :exec.run(command, exec_opts) do
      {:ok, pid, os_pid} ->
        {:ok, %{pid: pid, os_pid: os_pid, buffer: "", stderr: [], done?: false}}

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

  defp do_collect(state, os_pid, events) do
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
      15_000 ->
        safe_stop(state)
        {:error, :codex_timeout}
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

  defp build_command(%{codex_opts: %Options{} = opts} = exec_opts) do
    with {:ok, binary_path} <- Options.codex_path(opts) do
      args = build_args(exec_opts)
      command = Enum.map([binary_path | args], &to_charlist/1)
      {:ok, command}
    end
  end

  defp build_command(_), do: {:error, :missing_options}

  defp build_args(exec_opts) do
    base = ["exec", "--experimental-json"]

    model_args =
      case exec_opts do
        %{codex_opts: %Options{model: model}} when is_binary(model) and model != "" ->
          ["--model", model]

        _ ->
          []
      end

    thread_args =
      case exec_opts do
        %{thread: %{thread_id: thread_id}} when is_binary(thread_id) ->
          ["--thread-id", thread_id]

        _ ->
          []
      end

    continuation_args =
      case exec_opts do
        %{continuation_token: token} when is_binary(token) and token != "" ->
          ["--continuation-token", token]

        _ ->
          []
      end

    attachment_args =
      exec_opts
      |> Map.get(:attachments, [])
      |> Enum.flat_map(&attachment_cli_args/1)

    base ++ model_args ++ thread_args ++ continuation_args ++ attachment_args
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

  defp build_env(%{codex_opts: %Options{} = opts}) do
    []
    |> maybe_put_key("CODEX_API_KEY", opts.api_key)
    |> maybe_put_key("OPENAI_API_KEY", opts.api_key)
    |> maybe_put_key("CODEX_INTERNAL_ORIGINATOR_OVERRIDE", "codex_sdk_elixir")
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
end
