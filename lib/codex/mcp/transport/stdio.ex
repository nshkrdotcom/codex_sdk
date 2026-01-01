defmodule Codex.MCP.Transport.Stdio do
  @moduledoc """
  Runs MCP servers over stdio using a managed subprocess.
  """

  use GenServer

  require Logger

  alias Codex.AppServer.Subprocess.Erlexec
  alias Codex.MCP.Protocol

  defmodule State do
    @moduledoc false

    defstruct [
      :subprocess_mod,
      :subprocess_opts,
      :subprocess_pid,
      :os_pid,
      :stdout_buffer,
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
    subprocess_mod = Keyword.get(opts, :subprocess_mod, Erlexec)
    subprocess_opts = Keyword.get(opts, :subprocess_opts, [])

    with :ok <- ensure_erlexec_started(subprocess_mod),
         {:ok, command} <- build_command(opts),
         {:ok, subprocess_pid, os_pid} <-
           subprocess_mod.start(command, start_opts(opts), subprocess_opts) do
      {:ok,
       %State{
         subprocess_mod: subprocess_mod,
         subprocess_opts: subprocess_opts,
         subprocess_pid: subprocess_pid,
         os_pid: os_pid,
         stdout_buffer: "",
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

    case state.subprocess_mod.send(state.subprocess_pid, encoded, state.subprocess_opts) do
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
  def handle_info({:stdout, os_pid, chunk}, %State{os_pid: os_pid} = state) do
    {messages, buffer, non_json} = Protocol.decode_lines(state.stdout_buffer, chunk)

    Enum.each(non_json, fn raw ->
      Logger.debug("Ignoring non-JSON MCP output: #{inspect(raw)}")
    end)

    state
    |> enqueue_messages(messages)
    |> flush_waiters()
    |> then(fn updated -> {:noreply, %{updated | stdout_buffer: buffer}} end)
  end

  def handle_info({:stderr, os_pid, chunk}, %State{os_pid: os_pid} = state) do
    text = IO.iodata_to_binary(chunk)
    Logger.debug("MCP stderr: #{String.trim(text)}")
    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, pid, reason}, %State{os_pid: pid} = state) do
    Logger.debug("MCP subprocess exited: #{inspect(reason)}")
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
    state.subprocess_mod.stop(state.subprocess_pid, state.subprocess_opts)
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

  defp ensure_erlexec_started(Erlexec) do
    case Application.ensure_all_started(:erlexec) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
      {:error, {:erlexec, {:already_started, _}}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_erlexec_started(_other), do: :ok

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

  defp start_opts(opts) do
    env = build_env(opts)

    []
    |> maybe_add_env(env)
    |> maybe_add_cwd(Keyword.get(opts, :cwd))
    |> Kernel.++([:stdin, {:stdout, self()}, {:stderr, self()}, :monitor])
  end

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

  defp maybe_add_env(opts, []), do: opts
  defp maybe_add_env(opts, env), do: [{:env, env} | opts]

  defp maybe_add_cwd(opts, nil), do: opts
  defp maybe_add_cwd(opts, cwd), do: [{:cd, to_charlist(cwd)} | opts]
end
