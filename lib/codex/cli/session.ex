defmodule Codex.CLI.Session do
  @moduledoc """
  Raw `codex` CLI subprocess session backed by `cli_subprocess_core`.

  One-shot non-PTY command wrappers should use `Codex.CLI.run/2`, which
  executes through the shared `CliSubprocessCore.Command` lane.

  Sessions are useful for interactive or long-running commands such as:

  - `codex`
  - `codex resume`
  - `codex fork`
  - `codex app-server`
  - `codex mcp-server`

  The caller process continues to receive the historical mailbox events:

  - `{:stdout, os_pid, binary}`
  - `{:stderr, os_pid, binary}`
  - `{:DOWN, os_pid, :process, pid, reason}`

  Use `collect/2` to accumulate output until the process exits.
  """

  alias CliSubprocessCore.{Command, RawSession}
  alias CliSubprocessCore.Transport.Info
  alias Codex.Config.Defaults
  alias Codex.ProcessExit

  @event_tag :codex_cli_session

  @enforce_keys [:args, :command, :os_pid, :pid, :raw_session, :receiver]
  defstruct [:args, :command, :os_pid, :pid, :raw_session, :receiver, pty?: false, stdin?: false]

  @type t :: %__MODULE__{
          args: [String.t()],
          command: [String.t()],
          os_pid: non_neg_integer(),
          pid: pid(),
          raw_session: RawSession.t(),
          receiver: pid(),
          pty?: boolean(),
          stdin?: boolean()
        }

  @type result :: %{
          command: [String.t()],
          args: [String.t()],
          stdout: String.t(),
          stderr: String.t(),
          exit_code: integer(),
          success: boolean()
        }

  @doc """
  Starts a raw subprocess session for `binary_path` and `args`.
  """
  @spec start(String.t(), [String.t()], keyword()) :: {:ok, t()} | {:error, term()}
  def start(binary_path, args, opts \\ [])
      when is_binary(binary_path) and is_list(args) and is_list(opts) do
    receiver = Keyword.get(opts, :receiver, self())
    pty? = Keyword.get(opts, :pty, false)
    stdin? = Keyword.get(opts, :stdin, false)
    args = normalize_args(args)
    relay = start_relay(receiver)

    with {:ok, {env, clear_env?}} <- normalize_env_spec(Keyword.get(opts, :env)),
         invocation <-
           Command.new(binary_path, args,
             cwd: Keyword.get(opts, :cwd),
             env: env,
             clear_env?: clear_env?
           ),
         {:ok, raw_session} <-
           RawSession.start(invocation,
             receiver: relay,
             event_tag: @event_tag,
             stdin?: stdin?,
             stdout_mode: :raw,
             stdin_mode: :raw,
             pty?: pty?,
             interrupt_mode: default_interrupt_mode(pty?)
           ),
         %Info{pid: pid, os_pid: os_pid} = transport_info <- transport_info(raw_session) do
      bind_relay(relay, raw_session, transport_info)

      {:ok,
       %__MODULE__{
         args: args,
         command: [binary_path | args],
         os_pid: os_pid,
         pid: pid,
         raw_session: raw_session,
         receiver: receiver,
         pty?: pty?,
         stdin?: stdin?
       }}
    else
      {:error, _reason} = error ->
        stop_relay(relay)
        error
    end
  end

  @doc """
  Sends input bytes to the subprocess stdin.
  """
  @spec send_input(t(), iodata()) :: :ok | {:error, term()}
  def send_input(%__MODULE__{stdin?: false}, _data), do: {:error, :stdin_unavailable}

  def send_input(%__MODULE__{raw_session: raw_session}, data) do
    RawSession.send_input(raw_session, data)
  end

  @doc """
  Closes the subprocess stdin by sending EOF.
  """
  @spec close_input(t()) :: :ok | {:error, term()}
  def close_input(%__MODULE__{stdin?: false}), do: {:error, :stdin_unavailable}

  def close_input(%__MODULE__{raw_session: raw_session}) do
    RawSession.close_input(raw_session)
  end

  @doc """
  Stops the subprocess.
  """
  @spec stop(t()) :: :ok
  def stop(%__MODULE__{raw_session: raw_session}) do
    RawSession.stop(raw_session)
  end

  @doc """
  Interrupts the subprocess.
  """
  @spec interrupt(t()) :: :ok | {:error, term()}
  def interrupt(%__MODULE__{raw_session: raw_session}) do
    RawSession.interrupt(raw_session)
  end

  @doc """
  Collects stdout/stderr until the subprocess exits.
  """
  @spec collect(t(), timeout()) :: {:ok, result()} | {:error, term()}
  def collect(%__MODULE__{} = session, timeout_ms \\ Defaults.exec_timeout_ms()) do
    do_collect(session, timeout_ms, [], [])
  end

  defp do_collect(%__MODULE__{os_pid: os_pid, pid: pid} = session, timeout_ms, stdout, stderr) do
    receive do
      {:stdout, ^os_pid, data} ->
        do_collect(session, timeout_ms, [data | stdout], stderr)

      {:stderr, ^os_pid, data} ->
        do_collect(session, timeout_ms, stdout, [data | stderr])

      {:DOWN, ^os_pid, :process, ^pid, reason} ->
        exit_code = exit_code(reason)

        {:ok,
         %{
           command: session.command,
           args: session.args,
           stdout: stdout |> Enum.reverse() |> IO.iodata_to_binary(),
           stderr: stderr |> Enum.reverse() |> IO.iodata_to_binary(),
           exit_code: exit_code,
           success: exit_code == 0
         }}
    after
      timeout_ms ->
        {:error, {:timeout, session}}
    end
  end

  defp exit_code(reason) do
    case ProcessExit.exit_status(reason) do
      {:ok, status} -> status
      :unknown -> -1
    end
  end

  defp normalize_args(args), do: Enum.map(args, &to_string/1)

  defp normalize_env_spec(nil), do: {:ok, {%{}, false}}

  defp normalize_env_spec(%{} = env) do
    {:ok, {Map.new(env, fn {key, value} -> {to_string(key), to_string(value)} end), false}}
  end

  defp normalize_env_spec(env) when is_list(env) do
    Enum.reduce_while(env, {:ok, {%{}, false}}, fn
      :clear, {:ok, {acc, _clear?}} ->
        {:cont, {:ok, {acc, true}}}

      {key, value}, {:ok, {acc, clear?}} ->
        {:cont, {:ok, {Map.put(acc, to_string(key), to_string(value)), clear?}}}

      other, _acc ->
        {:halt, {:error, {:invalid_env, other}}}
    end)
  end

  defp normalize_env_spec(other), do: {:error, {:invalid_env, other}}

  defp default_interrupt_mode(true), do: {:stdin, <<3>>}
  defp default_interrupt_mode(_pty?), do: :signal

  defp transport_info(%RawSession{} = raw_session) do
    raw_session
    |> RawSession.info()
    |> Map.fetch!(:transport)
  end

  defp start_relay(receiver) when is_pid(receiver) do
    spawn(fn ->
      relay_loop(%{
        os_pid: nil,
        pid: nil,
        pending: [],
        receiver: receiver,
        receiver_ref: Process.monitor(receiver),
        transport_monitor_ref: nil,
        transport_pid: nil,
        transport_ref: nil
      })
    end)
  end

  defp bind_relay(
         relay,
         %RawSession{transport: transport_pid, transport_ref: transport_ref},
         %Info{
           pid: pid,
           os_pid: os_pid
         }
       ) do
    send(relay, {:bind, transport_pid, transport_ref, pid, os_pid})
    :ok
  end

  defp stop_relay(relay) when is_pid(relay) do
    Process.exit(relay, :normal)
    :ok
  end

  defp relay_loop(state) do
    receive do
      {:bind, transport_pid, transport_ref, pid, os_pid} ->
        transport_monitor_ref = Process.monitor(transport_pid)

        state
        |> Map.put(:transport_pid, transport_pid)
        |> Map.put(:transport_monitor_ref, transport_monitor_ref)
        |> Map.put(:transport_ref, transport_ref)
        |> Map.put(:pid, pid)
        |> Map.put(:os_pid, os_pid)
        |> flush_pending()

      {:DOWN, receiver_ref, :process, _pid, _reason} when receiver_ref == state.receiver_ref ->
        :ok

      {:DOWN, transport_monitor_ref, :process, transport_pid, reason}
      when transport_monitor_ref == state.transport_monitor_ref and
             transport_pid == state.transport_pid ->
        send(
          state.receiver,
          {:DOWN, state.os_pid, :process, state.pid, normalize_transport_down(reason)}
        )

        :ok

      {@event_tag, transport_ref, payload} ->
        state
        |> handle_relay_event(transport_ref, payload)

      _other ->
        relay_loop(state)
    end
  end

  defp flush_pending(%{pending: pending} = state) do
    Enum.reverse(pending)
    |> Enum.reduce_while(%{state | pending: []}, fn {transport_ref, payload}, acc ->
      case deliver_relay_event(acc, transport_ref, payload) do
        {:cont, next_state} -> {:cont, next_state}
        :stop -> {:halt, :stop}
      end
    end)
    |> case do
      :stop -> :ok
      next_state -> relay_loop(next_state)
    end
  end

  defp handle_relay_event(%{transport_ref: nil, pending: pending} = state, transport_ref, payload) do
    relay_loop(%{state | pending: [{transport_ref, payload} | pending]})
  end

  defp handle_relay_event(state, transport_ref, payload) do
    case deliver_relay_event(state, transport_ref, payload) do
      {:cont, next_state} -> relay_loop(next_state)
      :stop -> :ok
    end
  end

  defp deliver_relay_event(%{transport_ref: transport_ref} = state, transport_ref, {:data, chunk}) do
    send(state.receiver, {:stdout, state.os_pid, IO.iodata_to_binary(chunk)})
    {:cont, state}
  end

  defp deliver_relay_event(
         %{transport_ref: transport_ref} = state,
         transport_ref,
         {:message, line}
       ) do
    send(state.receiver, {:stdout, state.os_pid, line})
    {:cont, state}
  end

  defp deliver_relay_event(
         %{transport_ref: transport_ref} = state,
         transport_ref,
         {:stderr, chunk}
       ) do
    send(state.receiver, {:stderr, state.os_pid, IO.iodata_to_binary(chunk)})
    {:cont, state}
  end

  defp deliver_relay_event(
         %{transport_ref: transport_ref} = state,
         transport_ref,
         {:exit, reason}
       ) do
    send(state.receiver, {:DOWN, state.os_pid, :process, state.pid, reason})
    :stop
  end

  defp deliver_relay_event(
         %{transport_ref: transport_ref} = state,
         transport_ref,
         {:error, reason}
       ) do
    send(state.receiver, {:DOWN, state.os_pid, :process, state.pid, {:transport, reason}})
    :stop
  end

  defp deliver_relay_event(state, _transport_ref, _payload), do: {:cont, state}

  defp normalize_transport_down(:normal), do: {:transport, :closed}
  defp normalize_transport_down(reason), do: {:transport, reason}
end
