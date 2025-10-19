defmodule Codex.Exec do
  @moduledoc """
  Thin wrapper around the `codex-rs` binary.

  Provides blocking and streaming execution helpers that parse JSONL emitted by
  the subprocess.
  """

  require Logger

  alias Codex.Options

  @type exec_opts :: %{
          optional(:codex_opts) => Options.t(),
          optional(:thread) => Codex.Thread.t(),
          optional(:turn_opts) => map()
        }

  @doc """
  Runs codex in blocking mode and accumulates all emitted events.
  """
  @spec run(String.t(), exec_opts()) :: {:ok, map()} | {:error, term()}
  def run(input, opts) when is_binary(input) and is_map(opts) do
    with {:ok, cmd} <- build_command(opts),
         {:ok, port} <- open_port(cmd),
         :ok <- send_prompt(port, input),
         {:ok, data} <- collect_events(port) do
      {:ok, data}
    end
  end

  @doc """
  Returns a lazy stream of events. The underlying process is started once the
  stream is consumed for the first time.
  """
  @spec run_stream(String.t(), exec_opts()) :: Enumerable.t()
  def run_stream(input, opts) when is_binary(input) and is_map(opts) do
    Stream.resource(
      fn ->
        {:ok, cmd} = build_command(opts)
        {:ok, port} = open_port(cmd)
        :ok = send_prompt(port, input)
        %{port: port, buffer: "", done?: false}
      end,
      fn
        %{done?: true} = state ->
          {:halt, state}

        %{port: port, buffer: buffer} = state ->
          receive do
            {^port, {:data, chunk}} ->
              {lines, new_buffer} = decode_lines(buffer <> chunk)
              {lines, %{state | buffer: new_buffer}}

            {^port, {:exit_status, status}} ->
              if status == 0 do
                {decoded, _} = decode_lines(buffer)
                {decoded, %{state | buffer: "", done?: true}}
              else
                exit({:codex_exit, status})
              end
          end
      end,
      fn %{port: port} ->
        if Port.info(port) do
          Port.close(port)
        end
      end
    )
  end

  defp build_command(%{codex_opts: %Options{} = opts} = exec_opts) do
    with {:ok, binary_path} <- Options.codex_path(opts) do
      args = build_args(exec_opts)
      {:ok, {binary_path, args}}
    end
  end

  defp build_command(_), do: {:error, :missing_options}

  defp build_args(exec_opts) do
    base = [
      "--mode",
      "jsonl"
    ]

    thread_args =
      case exec_opts do
        %{thread: %{thread_id: thread_id}} when is_binary(thread_id) ->
          ["--thread-id", thread_id]

        _ ->
          []
      end

    base ++ thread_args
  end

  defp open_port({command, args}) do
    options = [:binary, :exit_status, args: args]

    case Port.open({:spawn_executable, to_charlist(command)}, options) do
      port when is_port(port) -> {:ok, port}
      _ -> {:error, :port_open_failed}
    end
  end

  defp send_prompt(port, input) do
    Port.command(port, input <> "\n")
    :ok
  end

  defp collect_events(port) do
    do_collect(port, [], "")
  end

  defp do_collect(port, events, buffer) do
    receive do
      {^port, {:data, chunk}} ->
        {decoded, new_buffer} = decode_lines(buffer <> chunk)
        do_collect(port, events ++ decoded, new_buffer)

      {^port, {:exit_status, 0}} ->
        {decoded, _} = decode_lines(buffer)
        {:ok, %{events: events ++ decoded}}

      {^port, {:exit_status, status}} ->
        {:error, {:codex_exit_status, status}}
    after
      15_000 ->
        Port.close(port)
        {:error, :codex_timeout}
    end
  end

  defp decode_lines(buffer) do
    case String.split(buffer, "\n", trim: false) do
      [] ->
        {[], buffer}

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
        decoded

      {:error, reason} ->
        Logger.warning("Failed to decode codex event: #{inspect(reason)} (#{line})")
        nil
    end
  end
end
