defmodule Codex.MCP.Transport.Stdio do
  @moduledoc """
  Runs MCP servers over stdio using a managed subprocess.
  """

  use GenServer

  require Logger

  alias Codex.IO.Buffer
  alias Codex.IO.Transport.Erlexec, as: IOTransportErlexec
  alias Codex.MCP.Protocol
  alias Codex.Runtime.Erlexec, as: RuntimeErlexec

  defmodule State do
    @moduledoc false

    defstruct [
      :transport_mod,
      :transport,
      :transport_ref,
      :messages,
      :waiters
    ]
  end

  @type t :: pid()

  @doc "Starts a stdio transport process."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc "Sends a JSON-RPC message to the MCP server."
  @spec send(t(), map()) :: :ok | {:error, term()}
  def send(pid, message) when is_pid(pid) and is_map(message) do
    GenServer.call(pid, {:send, message})
  end

  @doc "Receives the next JSON-RPC message from the MCP server."
  @spec recv(t(), pos_integer()) :: {:ok, map()} | {:error, term()}
  def recv(pid, timeout_ms) when is_pid(pid) and is_integer(timeout_ms) and timeout_ms > 0 do
    GenServer.call(pid, {:recv, timeout_ms}, timeout_ms + 1_000)
  end

  @impl true
  def init(opts) do
    {transport_mod, transport_opts} = resolve_transport(opts)
    transport_ref = make_ref()

    with :ok <- maybe_ensure_erlexec(transport_mod),
         {:ok, command} <- build_command(opts),
         {:ok, transport} <-
           transport_mod.start_link(
             [
               command: command,
               cwd: Keyword.get(opts, :cwd),
               env: build_env(opts),
               subscriber: {self(), transport_ref}
             ] ++ transport_opts
           ) do
      {:ok,
       %State{
         transport_mod: transport_mod,
         transport: transport,
         transport_ref: transport_ref,
         messages: :queue.new(),
         waiters: []
       }}
    else
      {:error, _} = error -> error
      other -> {:stop, other}
    end
  end

  @impl true
  def handle_call({:send, message}, _from, %State{} = state) do
    encoded = Protocol.encode_message(message)

    case state.transport_mod.send(state.transport, encoded) do
      :ok -> {:reply, :ok, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:recv, timeout_ms}, from, %State{} = state) do
    case pop_message(state) do
      {:ok, message, next_state} ->
        {:reply, {:ok, message}, next_state}

      :empty ->
        timer_ref = Process.send_after(self(), {:recv_timeout, from}, timeout_ms)
        {:noreply, %{state | waiters: state.waiters ++ [{from, timer_ref}]}}
    end
  end

  @impl true
  def handle_info(
        {:codex_io_transport, ref, {:message, line}},
        %State{transport_ref: ref} = state
      ) do
    state =
      case Buffer.decode_line(line) do
        {:ok, msg} ->
          state
          |> enqueue_messages([msg])
          |> flush_waiters()

        {:non_json, raw} ->
          Logger.debug("Ignoring non-JSON MCP output: #{inspect(raw)}")
          state
      end

    {:noreply, state}
  end

  def handle_info(
        {:codex_io_transport, ref, {:stderr, chunk}},
        %State{transport_ref: ref} = state
      ) do
    text = IO.iodata_to_binary(chunk)
    Logger.debug("MCP stderr: #{String.trim(text)}")
    {:noreply, state}
  end

  def handle_info(
        {:codex_io_transport, ref, {:error, reason}},
        %State{transport_ref: ref} = state
      ) do
    Logger.debug("MCP transport error: #{inspect(reason)}")
    {:noreply, state}
  end

  def handle_info({:codex_io_transport, ref, {:exit, reason}}, %State{transport_ref: ref} = state) do
    Logger.debug("MCP subprocess exited: #{inspect(reason)}")

    state =
      state
      |> drain_waiters({:error, :closed})

    {:stop, :normal, state}
  end

  def handle_info({:recv_timeout, from}, %State{} = state) do
    case pop_waiter(state.waiters, from) do
      {nil, _waiters} ->
        {:noreply, state}

      {timer_ref, waiters} ->
        _ = Process.cancel_timer(timer_ref)
        GenServer.reply(from, {:error, :timeout})
        {:noreply, %{state | waiters: waiters}}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %State{} = state) do
    _ = drain_waiters(state, {:error, :closed})
    _ = state.transport_mod.force_close(state.transport)
    :ok
  end

  defp pop_message(%State{} = state) do
    case :queue.out(state.messages) do
      {{:value, message}, messages} -> {:ok, message, %{state | messages: messages}}
      {:empty, _} -> :empty
    end
  end

  defp enqueue_messages(%State{} = state, messages) do
    updated = Enum.reduce(messages, state.messages, &:queue.in/2)
    %{state | messages: updated}
  end

  defp flush_waiters(%State{} = state) do
    case {state.waiters, pop_message(state)} do
      {[], _} ->
        state

      {[_ | _], :empty} ->
        state

      {[{from, timer_ref} | rest], {:ok, message, next_state}} ->
        _ = Process.cancel_timer(timer_ref)
        GenServer.reply(from, {:ok, message})

        %{next_state | waiters: rest}
        |> flush_waiters()
    end
  end

  defp drain_waiters(%State{} = state, reply) do
    Enum.each(state.waiters, fn {from, timer_ref} ->
      _ = Process.cancel_timer(timer_ref)
      GenServer.reply(from, reply)
    end)

    %{state | waiters: []}
  end

  defp pop_waiter(waiters, target) do
    {match, rest} =
      Enum.reduce(waiters, {nil, []}, fn {from, ref}, {found, acc} ->
        if from == target do
          {ref, acc}
        else
          {found, acc ++ [{from, ref}]}
        end
      end)

    {match, rest}
  end

  defp build_command(opts) do
    case Keyword.get(opts, :command) do
      nil ->
        {:error, :missing_command}

      command when is_binary(command) ->
        args = Keyword.get(opts, :args, [])
        argv = [command | List.wrap(args)]
        {:ok, Enum.map(argv, &to_charlist/1)}

      argv when is_list(argv) ->
        {:ok, Enum.map(argv, &to_charlist/1)}
    end
  end

  defp resolve_transport(opts) do
    case Keyword.fetch(opts, :transport) do
      {:ok, {module, transport_opts}} when is_atom(module) and is_list(transport_opts) ->
        {module, transport_opts}

      {:ok, module} when is_atom(module) ->
        {module, []}

      {:ok, other} ->
        raise ArgumentError, "invalid transport option: #{inspect(other)}"

      :error ->
        case Keyword.get(opts, :subprocess_mod) do
          nil ->
            {IOTransportErlexec, []}

          module when is_atom(module) ->
            {module, Keyword.get(opts, :subprocess_opts, [])}

          other ->
            raise ArgumentError, "invalid subprocess_mod option: #{inspect(other)}"
        end
    end
  end

  defp maybe_ensure_erlexec(IOTransportErlexec), do: RuntimeErlexec.ensure_started()
  defp maybe_ensure_erlexec(_other), do: :ok

  defp build_env(opts) do
    env_vars = Keyword.get(opts, :env_vars, [])
    extra_env = Keyword.get(opts, :env, %{})

    default_env =
      default_env_vars()
      |> Enum.reduce(%{}, fn key, acc ->
        case System.get_env(key) do
          nil -> acc
          value -> Map.put(acc, key, value)
        end
      end)

    from_env_vars =
      env_vars
      |> Enum.reduce(%{}, fn key, acc ->
        case System.get_env(key) do
          nil -> acc
          value -> Map.put(acc, key, value)
        end
      end)

    extra_env =
      case extra_env do
        %{} = map -> map
        list when is_list(list) -> Map.new(list)
        _ -> %{}
      end

    default_env
    |> Map.merge(from_env_vars)
    |> Map.merge(extra_env)
    |> Enum.map(fn {key, value} -> {key, value} end)
  end

  defp default_env_vars do
    case :os.type() do
      {:win32, _} ->
        [
          "PATH",
          "PATHEXT",
          "COMSPEC",
          "SYSTEMROOT",
          "SYSTEMDRIVE",
          "USERNAME",
          "USERDOMAIN",
          "USERPROFILE",
          "HOMEDRIVE",
          "HOMEPATH",
          "PROGRAMFILES",
          "PROGRAMFILES(X86)",
          "PROGRAMW6432",
          "PROGRAMDATA",
          "LOCALAPPDATA",
          "APPDATA",
          "TEMP",
          "TMP",
          "POWERSHELL",
          "PWSH"
        ]

      _ ->
        [
          "HOME",
          "LOGNAME",
          "PATH",
          "SHELL",
          "USER",
          "__CF_USER_TEXT_ENCODING",
          "LANG",
          "LC_ALL",
          "TERM",
          "TMPDIR",
          "TZ"
        ]
    end
  end
end
