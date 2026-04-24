defmodule Codex.CLI.Session do
  @moduledoc """
  Raw `codex` CLI subprocess session backed by `CliSubprocessCore.Channel`.

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

  alias CliSubprocessCore.{Channel, Command, CommandSpec}
  alias CliSubprocessCore.TransportInfo
  alias Codex.Config.Defaults
  alias Codex.Options
  alias Codex.ProcessExit

  @enforce_keys [:args, :channel, :command, :os_pid, :pid, :receiver]
  defstruct [:args, :channel, :command, :os_pid, :pid, :receiver, pty?: false, stdin?: false]

  @type t :: %__MODULE__{
          args: [String.t()],
          channel: Channel.t(),
          command: [String.t()],
          os_pid: non_neg_integer(),
          pid: pid(),
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
  Starts a raw subprocess session for a resolved Codex program and `args`.
  """
  @spec start(String.t() | CommandSpec.t(), [String.t()], keyword()) ::
          {:ok, t()} | {:error, term()}
  def start(binary_or_spec, args, opts \\ [])
      when (is_binary(binary_or_spec) or is_struct(binary_or_spec, CommandSpec)) and is_list(args) and
             is_list(opts) do
    receiver = Keyword.get(opts, :receiver, self())
    pty? = Keyword.get(opts, :pty, false)
    stdin? = Keyword.get(opts, :stdin, false)
    args = normalize_args(args)
    relay = start_relay(receiver)
    channel_ref = make_ref()

    with {:ok, {env, clear_env?}} <- normalize_env_spec(Keyword.get(opts, :env)),
         {:ok, execution_surface} <-
           Options.normalize_execution_surface(Keyword.get(opts, :execution_surface)),
         invocation <-
           Command.new(binary_or_spec, args,
             cwd: Keyword.get(opts, :cwd),
             env: env,
             clear_env?: clear_env?
           ),
         {:ok, channel, %{transport: transport_info}} <-
           Channel.start_channel(
             Options.execution_surface_options(execution_surface) ++
               [
                 command: invocation,
                 subscriber: {relay, channel_ref},
                 stdout_mode: :raw,
                 stdin_mode: :raw,
                 pty?: pty?,
                 interrupt_mode: default_interrupt_mode(pty?)
               ]
           ),
         true <- TransportInfo.match?(transport_info) do
      bind_relay(relay, channel, channel_ref, transport_info)

      {:ok,
       %__MODULE__{
         args: args,
         channel: channel,
         command: Command.argv(invocation),
         os_pid: TransportInfo.os_pid(transport_info),
         pid: TransportInfo.pid(transport_info),
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

  def send_input(%__MODULE__{channel: channel}, data) do
    Channel.send_input(channel, data)
  end

  @doc """
  Closes the subprocess stdin by sending EOF.
  """
  @spec close_input(t()) :: :ok | {:error, term()}
  def close_input(%__MODULE__{stdin?: false}), do: {:error, :stdin_unavailable}

  def close_input(%__MODULE__{channel: channel}) do
    Channel.close_input(channel)
  end

  @doc """
  Stops the subprocess.
  """
  @spec stop(t()) :: :ok
  def stop(%__MODULE__{channel: channel}) do
    Channel.stop(channel)
  end

  @doc """
  Interrupts the subprocess.
  """
  @spec interrupt(t()) :: :ok | {:error, term()}
  def interrupt(%__MODULE__{channel: channel}) do
    Channel.interrupt(channel)
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

  defp start_relay(receiver) when is_pid(receiver) do
    spawn(fn ->
      relay_loop(%{
        channel_monitor_ref: nil,
        channel_pid: nil,
        channel_ref: nil,
        os_pid: nil,
        pending: [],
        pid: nil,
        receiver: receiver,
        receiver_ref: Process.monitor(receiver)
      })
    end)
  end

  defp bind_relay(relay, channel, channel_ref, transport_info) do
    pid = TransportInfo.pid(transport_info)
    os_pid = TransportInfo.os_pid(transport_info)
    send(relay, {:bind, channel, channel_ref, pid, os_pid})
    :ok
  end

  defp stop_relay(relay) when is_pid(relay) do
    Process.exit(relay, :normal)
    :ok
  end

  defp relay_loop(state) do
    receive do
      {:bind, channel_pid, channel_ref, pid, os_pid} ->
        channel_monitor_ref = Process.monitor(channel_pid)

        state
        |> Map.put(:channel_pid, channel_pid)
        |> Map.put(:channel_monitor_ref, channel_monitor_ref)
        |> Map.put(:channel_ref, channel_ref)
        |> Map.put(:pid, pid)
        |> Map.put(:os_pid, os_pid)
        |> flush_pending()

      {:DOWN, receiver_ref, :process, _pid, _reason} when receiver_ref == state.receiver_ref ->
        :ok

      {:DOWN, channel_monitor_ref, :process, channel_pid, reason}
      when channel_monitor_ref == state.channel_monitor_ref and channel_pid == state.channel_pid ->
        send(
          state.receiver,
          {:DOWN, state.os_pid, :process, state.pid, normalize_channel_down(reason)}
        )

        :ok

      message ->
        state
        |> handle_relay_message(message)
    end
  end

  defp flush_pending(%{pending: pending} = state) do
    Enum.reverse(pending)
    |> Enum.reduce_while(%{state | pending: []}, fn message, acc ->
      case deliver_relay_message(acc, message) do
        {:cont, next_state} -> {:cont, next_state}
        :stop -> {:halt, :stop}
      end
    end)
    |> case do
      :stop -> :ok
      next_state -> relay_loop(next_state)
    end
  end

  defp handle_relay_message(%{channel_ref: nil, pending: pending} = state, message) do
    relay_loop(%{state | pending: [message | pending]})
  end

  defp handle_relay_message(state, message) do
    case deliver_relay_message(state, message) do
      {:cont, next_state} -> relay_loop(next_state)
      :stop -> :ok
    end
  end

  defp deliver_relay_message(%{channel_ref: channel_ref} = state, message) do
    case Channel.extract_event(message, channel_ref) do
      {:ok, {:data, chunk}} ->
        send(state.receiver, {:stdout, state.os_pid, IO.iodata_to_binary(chunk)})
        {:cont, state}

      {:ok, {:message, line}} ->
        send(state.receiver, {:stdout, state.os_pid, line})
        {:cont, state}

      {:ok, {:stderr, chunk}} ->
        send(state.receiver, {:stderr, state.os_pid, IO.iodata_to_binary(chunk)})
        {:cont, state}

      {:ok, {:exit, reason}} ->
        send(state.receiver, {:DOWN, state.os_pid, :process, state.pid, reason})
        :stop

      {:ok, {:error, reason}} ->
        send(state.receiver, {:DOWN, state.os_pid, :process, state.pid, {:transport, reason}})
        :stop

      :error ->
        {:cont, state}
    end
  end

  defp normalize_channel_down(:normal), do: {:transport, :closed}
  defp normalize_channel_down(reason), do: {:transport, reason}
end
