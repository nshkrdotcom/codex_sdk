defmodule Codex.MCP.Transport.Stdio do
  @moduledoc """
  Runs MCP servers over stdio using the core JSON-RPC protocol session stack.
  """

  use GenServer
  import Kernel, except: [send: 2]

  require Logger

  alias CliSubprocessCore.{Command, JSONRPC, ProtocolSession}
  alias Codex.Options

  @default_request_timeout_ms :timer.hours(24)

  defmodule State do
    @moduledoc false

    defstruct [
      :session,
      :session_monitor_ref,
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
    with {:ok, invocation} <- build_command(opts),
         {:ok, execution_surface} <-
           Options.normalize_execution_surface(Keyword.get(opts, :execution_surface)),
         {:ok, session} <- start_protocol_session(invocation, execution_surface) do
      {:ok,
       %State{
         session: session,
         session_monitor_ref: Process.monitor(session),
         messages: :queue.new(),
         waiters: []
       }}
    else
      {:error, _} = error -> error
    end
  end

  @impl true
  def handle_call({:send, message}, _from, %State{} = state) do
    case send_message(state, message) do
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
  def handle_info({:jsonrpc_notification, %{} = notification}, %State{} = state) do
    {:noreply, state |> enqueue_messages([notification]) |> flush_waiters()}
  end

  def handle_info({:jsonrpc_peer_request, %{} = request}, %State{} = state) do
    {:noreply, state |> enqueue_messages([request]) |> flush_waiters()}
  end

  def handle_info({:jsonrpc_request_result, id, {:ok, result}}, %State{} = state) do
    message = %{"id" => id, "result" => result}
    {:noreply, state |> enqueue_messages([message]) |> flush_waiters()}
  end

  def handle_info({:jsonrpc_request_result, id, {:error, %{} = error}}, %State{} = state) do
    message = %{"id" => id, "error" => error}
    {:noreply, state |> enqueue_messages([message]) |> flush_waiters()}
  end

  def handle_info({:jsonrpc_stderr, chunk}, %State{} = state) do
    text = IO.iodata_to_binary(chunk)
    Logger.debug("MCP stderr: #{String.trim(text)}")
    {:noreply, state}
  end

  def handle_info({:jsonrpc_protocol_error, reason}, %State{} = state) do
    Logger.debug("MCP protocol error: #{inspect(reason)}")
    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, pid, _reason}, %State{} = state)
      when ref == state.session_monitor_ref and pid == state.session do
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
    _ = close_session(state.session)
    :ok
  end

  defp send_message(%State{session: session}, %{} = message) do
    case message_kind(message) do
      {:request, id} ->
        start_request_task(session, message, id, self())

      :notification ->
        ProtocolSession.notify(session, message)

      :unsupported ->
        {:error, {:unsupported_message, message}}
    end
  end

  defp message_kind(%{} = message) do
    cond do
      request_message?(message) ->
        {:request, Map.get(message, "id", Map.get(message, :id))}

      notification_message?(message) ->
        :notification

      true ->
        :unsupported
    end
  end

  defp start_request_task(session, message, id, owner) do
    {:ok, _pid} =
      Task.start(fn ->
        result =
          ProtocolSession.request(session, message, timeout_ms: @default_request_timeout_ms)

        Kernel.send(owner, {:jsonrpc_request_result, id, result})
      end)

    :ok
  end

  defp request_message?(%{} = message) do
    present?(Map.get(message, "id", Map.get(message, :id))) and
      is_binary(Map.get(message, "method", Map.get(message, :method)))
  end

  defp notification_message?(%{} = message) do
    not present?(Map.get(message, "id", Map.get(message, :id))) and
      is_binary(Map.get(message, "method", Map.get(message, :method)))
  end

  defp present?(value), do: not is_nil(value)

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

  defp start_protocol_session(invocation, execution_surface) do
    owner = self()

    JSONRPC.start(
      Options.execution_surface_options(execution_surface) ++
        [
          command: invocation,
          ready_mode: :immediate,
          notification_handler: fn notification ->
            Kernel.send(owner, {:jsonrpc_notification, notification})
          end,
          protocol_error_handler: fn reason ->
            Kernel.send(owner, {:jsonrpc_protocol_error, reason})
          end,
          stderr_handler: fn chunk ->
            Kernel.send(owner, {:jsonrpc_stderr, IO.iodata_to_binary(chunk)})
          end,
          peer_request_handler: fn request ->
            Kernel.send(owner, {:jsonrpc_peer_request, request})
            {:error, :unsupported_peer_request}
          end
        ]
    )
  end

  defp build_command(opts) do
    case Keyword.get(opts, :command) do
      nil ->
        {:error, :missing_command}

      command when is_binary(command) ->
        args = Keyword.get(opts, :args, [])

        {:ok,
         Command.new(command, Enum.map(List.wrap(args), &to_string/1),
           cwd: Keyword.get(opts, :cwd),
           env: build_env(opts)
         )}

      argv when is_list(argv) ->
        case Enum.map(argv, &to_string/1) do
          [command | args] ->
            {:ok, Command.new(command, args, cwd: Keyword.get(opts, :cwd), env: build_env(opts))}

          [] ->
            {:error, :missing_command}
        end
    end
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
  end

  defp close_session(session) when is_pid(session) do
    JSONRPC.close(session)
  catch
    :exit, _reason -> :ok
  end

  defp close_session(_session), do: :ok

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
