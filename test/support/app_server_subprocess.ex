defmodule Codex.TestSupport.AppServerSubprocess do
  @moduledoc false

  use GenServer

  alias CliSubprocessCore.Command
  alias Codex.Options

  @poll_interval_ms 10
  @current_harness_key {__MODULE__, :current_harness}

  @control_env "CODEX_TEST_APP_SERVER_CONTROL"
  @events_env "CODEX_TEST_APP_SERVER_EVENTS"
  @startup_stderr_env "CODEX_TEST_APP_SERVER_STARTUP_STDERR"
  @exit_on_start_env "CODEX_TEST_APP_SERVER_EXIT_ON_START"
  @exit_status_env "CODEX_TEST_APP_SERVER_EXIT_STATUS"

  defstruct [
    :root_dir,
    :script_path,
    :control_path,
    :events_path,
    :owner,
    :relay,
    :process_env
  ]

  @type t :: %__MODULE__{
          root_dir: String.t(),
          script_path: String.t(),
          control_path: String.t(),
          events_path: String.t(),
          owner: pid(),
          relay: pid(),
          process_env: %{String.t() => String.t()}
        }

  defmodule State do
    @moduledoc false

    defstruct owner: nil,
              events_path: nil,
              offset: 0,
              attached_conn: nil,
              pending_events: []
  end

  @spec new!(keyword()) :: t()
  def new!(opts \\ []) when is_list(opts) do
    owner = Keyword.get(opts, :owner, self())
    root_dir = temp_dir!("codex_app_server_subprocess")
    control_path = Path.join(root_dir, "control.jsonl")
    events_path = Path.join(root_dir, "events.jsonl")

    File.write!(control_path, "")
    File.write!(events_path, "")

    process_env =
      %{
        @control_env => control_path,
        @events_env => events_path
      }
      |> maybe_put_env(@startup_stderr_env, Keyword.get(opts, :stderr))
      |> maybe_put_env(
        @exit_on_start_env,
        if(Keyword.get(opts, :exit_on_start, false), do: "1", else: nil)
      )
      |> maybe_put_env(
        @exit_status_env,
        case Keyword.get(opts, :exit_status) do
          value when is_integer(value) -> Integer.to_string(value)
          _ -> nil
        end
      )

    script_path = write_script!(root_dir)

    {:ok, relay} =
      GenServer.start_link(__MODULE__, owner: owner, events_path: events_path)

    %__MODULE__{
      root_dir: root_dir,
      script_path: script_path,
      control_path: control_path,
      events_path: events_path,
      owner: owner,
      relay: relay,
      process_env: process_env
    }
  end

  @spec cleanup(t()) :: :ok
  def cleanup(%__MODULE__{} = harness) do
    if is_pid(harness.relay) and Process.alive?(harness.relay) do
      GenServer.stop(harness.relay, :normal)
    end

    File.rm_rf!(harness.root_dir)
    :ok
  end

  @spec put_current!(t()) :: t()
  def put_current!(%__MODULE__{} = harness) do
    Process.put(@current_harness_key, harness)
    harness
  end

  @spec current!() :: t()
  def current! do
    case Process.get(@current_harness_key) do
      %__MODULE__{} = harness -> harness
      other -> raise "expected current app-server subprocess harness, got: #{inspect(other)}"
    end
  end

  @spec command_path(t()) :: String.t()
  def command_path(%__MODULE__{script_path: script_path}), do: script_path

  @spec process_env(t()) :: %{String.t() => String.t()}
  def process_env(%__MODULE__{process_env: process_env}), do: process_env

  @spec attach(t(), pid()) :: :ok
  def attach(%__MODULE__{relay: relay}, conn) when is_pid(relay) and is_pid(conn) do
    GenServer.call(relay, {:attach, conn})
  end

  @spec codex_opts(Options.t(), t()) :: Options.t()
  def codex_opts(%Options{} = codex_opts, %__MODULE__{} = harness) do
    %Options{codex_opts | codex_path_override: harness.script_path}
  end

  @spec connect_opts(t(), keyword()) :: keyword()
  def connect_opts(%__MODULE__{} = harness, opts \\ []) when is_list(opts) do
    Keyword.put(
      opts,
      :process_env,
      merge_env(Keyword.get(opts, :process_env), harness.process_env)
    )
  end

  @spec send_stdout(t(), iodata()) :: :ok
  def send_stdout(%__MODULE__{} = harness, data) do
    append_control(harness.control_path, %{
      "command" => "stdout",
      "data" => Base.encode64(IO.iodata_to_binary(data))
    })
  end

  @spec send_stdout(iodata()) :: :ok
  def send_stdout(data), do: send_stdout(current!(), data)

  @spec send_stderr(t(), iodata()) :: :ok
  def send_stderr(%__MODULE__{} = harness, data) do
    append_control(harness.control_path, %{
      "command" => "stderr",
      "data" => Base.encode64(IO.iodata_to_binary(data))
    })
  end

  @spec send_stderr(iodata()) :: :ok
  def send_stderr(data), do: send_stderr(current!(), data)

  @spec exit(t()) :: :ok
  def exit(%__MODULE__{} = harness), do: exit(harness, 0)

  @spec exit(integer()) :: :ok
  def exit(status) when is_integer(status), do: exit(current!(), status)

  @spec exit(t(), integer()) :: :ok
  def exit(%__MODULE__{} = harness, status) when is_integer(status) do
    append_control(harness.control_path, %{
      "command" => "exit",
      "status" => status
    })
  end

  @impl true
  def init(opts) do
    state = %State{
      owner: Keyword.fetch!(opts, :owner),
      events_path: Keyword.fetch!(opts, :events_path)
    }

    schedule_poll()
    {:ok, state}
  end

  @impl true
  def handle_call({:attach, conn}, _from, %State{} = state) do
    {:reply, :ok, flush_pending(%{state | attached_conn: conn})}
  end

  @impl true
  def handle_info(:poll, %State{} = state) do
    schedule_poll()
    {:noreply, poll_events(state)}
  end

  def handle_info(_message, %State{} = state), do: {:noreply, state}

  defp poll_events(%State{} = state) do
    case File.read(state.events_path) do
      {:ok, contents} ->
        {events, offset} = parse_events(contents, state.offset)

        Enum.reduce(events, %State{state | offset: offset}, fn event, acc ->
          enqueue_or_deliver(acc, event)
        end)

      {:error, _reason} ->
        state
    end
  end

  defp parse_events(contents, offset) when is_binary(contents) and is_integer(offset) do
    if byte_size(contents) <= offset do
      {[], offset}
    else
      chunk = binary_part(contents, offset, byte_size(contents) - offset)
      complete_chunk = complete_event_chunk(chunk)

      if is_nil(complete_chunk) do
        {[], offset}
      else
        {decode_events(complete_chunk), offset + byte_size(complete_chunk)}
      end
    end
  end

  defp complete_event_chunk(chunk) when is_binary(chunk) do
    case :binary.matches(chunk, "\n") do
      [] ->
        nil

      matches ->
        {newline_offset, 1} = List.last(matches)
        complete_size = newline_offset + 1
        binary_part(chunk, 0, complete_size)
    end
  end

  defp decode_events(chunk) when is_binary(chunk) do
    chunk
    |> String.split("\n", trim: true)
    |> Enum.flat_map(&decode_event_line/1)
  end

  defp decode_event_line(line) when is_binary(line) do
    case Jason.decode(line) do
      {:ok, %{} = event} -> [event]
      _ -> []
    end
  end

  defp enqueue_or_deliver(%State{attached_conn: nil, pending_events: pending} = state, event) do
    %State{state | pending_events: pending ++ [event]}
  end

  defp enqueue_or_deliver(%State{} = state, event) do
    deliver_event(state.owner, state.attached_conn, event)
    state
  end

  defp flush_pending(%State{attached_conn: nil} = state), do: state

  defp flush_pending(%State{} = state) do
    Enum.each(state.pending_events, fn event ->
      deliver_event(state.owner, state.attached_conn, event)
    end)

    %State{state | pending_events: []}
  end

  defp deliver_event(owner, conn, %{"event" => "started"} = event)
       when is_pid(owner) and is_pid(conn) do
    os_pid = Map.get(event, "os_pid")
    argv = List.wrap(Map.get(event, "argv"))
    cwd = Map.get(event, "cwd")
    env = normalize_env_map(Map.get(event, "env"))

    command =
      case argv do
        [program | args] -> Command.new(program, args, cwd: cwd, env: env)
        _ -> nil
      end

    start_opts =
      []
      |> maybe_put_start_opt(:command, command)
      |> Keyword.put(:stdout_mode, :line)
      |> Keyword.put(:stdin_mode, :raw)
      |> Keyword.put(:pty?, false)
      |> Keyword.put(:interrupt_mode, :signal)

    send(owner, {:app_server_subprocess_started, conn, os_pid})
    send(owner, {:app_server_subprocess_start_opts, conn, os_pid, start_opts})
  end

  defp deliver_event(owner, conn, %{"event" => "stdin", "line" => line})
       when is_pid(owner) and is_pid(conn) do
    send(owner, {:app_server_subprocess_send, conn, line})
  end

  defp deliver_event(owner, conn, %{"event" => "stopped"} = event)
       when is_pid(owner) and is_pid(conn) do
    send(owner, {:app_server_subprocess_stopped, conn, Map.get(event, "os_pid")})
  end

  defp deliver_event(_owner, _conn, _event), do: :ok

  defp maybe_put_env(env, _key, nil), do: env
  defp maybe_put_env(env, key, value), do: Map.put(env, key, to_string(value))

  defp maybe_put_start_opt(start_opts, _key, nil), do: start_opts
  defp maybe_put_start_opt(start_opts, key, value), do: Keyword.put(start_opts, key, value)

  defp normalize_env_map(%{} = env),
    do: Map.new(env, fn {key, value} -> {to_string(key), to_string(value)} end)

  defp normalize_env_map(_env), do: %{}

  defp merge_env(nil, process_env), do: process_env

  defp merge_env(%{} = env, process_env) do
    Map.merge(
      Map.new(env, fn {key, value} -> {to_string(key), to_string(value)} end),
      process_env
    )
  end

  defp merge_env(env, process_env) when is_list(env) do
    env
    |> Map.new(fn {key, value} -> {to_string(key), to_string(value)} end)
    |> Map.merge(process_env)
  end

  defp append_control(path, payload) do
    File.write!(path, Jason.encode!(payload) <> "\n", [:append])
    :ok
  end

  defp schedule_poll do
    Process.send_after(self(), :poll, @poll_interval_ms)
  end

  defp temp_dir!(prefix) do
    dir = Path.join(System.tmp_dir!(), "#{prefix}_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    dir
  end

  defp write_script!(root_dir) do
    python =
      System.find_executable("python3") || System.find_executable("python") ||
        raise "python is required for app-server subprocess tests"

    path = Path.join(root_dir, "mock_codex.py")
    File.write!(path, script_contents(python))
    File.chmod!(path, 0o755)
    path
  end

  defp script_contents(python) do
    """
    #!#{python}
    import base64
    import json
    import os
    import select
    import sys
    import time

    CONTROL_PATH = os.environ[#{inspect(@control_env)}]
    EVENTS_PATH = os.environ[#{inspect(@events_env)}]
    STARTUP_STDERR = os.environ.get(#{inspect(@startup_stderr_env)}, "")
    EXIT_ON_START = os.environ.get(#{inspect(@exit_on_start_env)}) == "1"
    EXIT_STATUS = int(os.environ.get(#{inspect(@exit_status_env)}, "0"))

    def emit(event):
        with open(EVENTS_PATH, "a", encoding="utf-8") as handle:
            handle.write(json.dumps(event) + "\\n")
            handle.flush()

    def write_stream(stream, payload):
        stream.buffer.write(payload)
        stream.flush()

    def main():
        emit(
            {
                "event": "started",
                "os_pid": os.getpid(),
                "argv": sys.argv,
                "cwd": os.getcwd(),
                "env": dict(os.environ),
            }
        )

        if STARTUP_STDERR:
            sys.stderr.write(STARTUP_STDERR)
            sys.stderr.flush()

        if EXIT_ON_START:
            emit({"event": "stopped", "os_pid": os.getpid(), "exit_status": EXIT_STATUS})
            return EXIT_STATUS

        control_offset = 0
        exit_status = 0
        running = True

        while running:
            try:
                with open(CONTROL_PATH, "r", encoding="utf-8") as handle:
                    handle.seek(control_offset)
                    control_lines = handle.readlines()
                    control_offset = handle.tell()
            except FileNotFoundError:
                control_lines = []

            for raw in control_lines:
                raw = raw.strip()
                if not raw:
                    continue

                command = json.loads(raw)
                name = command.get("command")

                if name == "stdout":
                    write_stream(sys.stdout, base64.b64decode(command["data"]))
                elif name == "stderr":
                    write_stream(sys.stderr, base64.b64decode(command["data"]))
                elif name == "exit":
                    exit_status = int(command.get("status", 0))
                    running = False
                    break

            if not running:
                break

            readable, _, _ = select.select([sys.stdin], [], [], 0.01)

            if readable:
                line = sys.stdin.readline()

                if line == "":
                    break

                emit({"event": "stdin", "line": line})
            else:
                time.sleep(0.01)

        emit({"event": "stopped", "os_pid": os.getpid(), "exit_status": exit_status})
        return exit_status

    if __name__ == "__main__":
        sys.exit(main())
    """
  end
end
