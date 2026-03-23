defmodule Codex.AppServer.Connection do
  @moduledoc false

  use GenServer

  require Logger

  alias CliSubprocessCore.{Command, RawSession, Transport}
  alias Codex.AppServer.Protocol
  alias Codex.Config.Defaults
  alias Codex.IO.Buffer
  alias Codex.Options
  alias Codex.Runtime.Env, as: RuntimeEnv

  @default_init_timeout_ms Defaults.app_server_init_timeout_ms()
  @default_request_timeout_ms Defaults.app_server_request_timeout_ms()
  @default_call_timeout_ms 5_000

  defmodule State do
    @moduledoc false

    defstruct [
      :codex_opts,
      :raw_session,
      :phase,
      :next_id,
      :pending,
      :ready_waiters,
      :subscribers,
      :subscriber_refs
    ]
  end

  @type connection :: pid()
  @type request_id :: integer() | String.t()

  @spec start_link(Options.t(), keyword()) :: GenServer.on_start()
  def start_link(%Options{} = codex_opts, opts) when is_list(opts) do
    GenServer.start_link(__MODULE__, {codex_opts, opts})
  end

  @spec start_link({Options.t(), keyword()}) :: GenServer.on_start()
  def start_link({%Options{} = codex_opts, opts}) when is_list(opts) do
    start_link(codex_opts, opts)
  end

  @spec start_link(Options.t()) :: GenServer.on_start()
  def start_link(%Options{} = codex_opts) do
    start_link(codex_opts, [])
  end

  @spec await_ready(connection(), pos_integer()) :: :ok | {:error, term()}
  def await_ready(conn, timeout_ms)
      when is_pid(conn) and is_integer(timeout_ms) and timeout_ms > 0 do
    case safe_connection_call(conn, :await_ready, timeout_ms) do
      {:ok, reply} -> reply
      {:error, reason} -> {:error, reason}
    end
  end

  @spec subscribe(connection(), keyword()) :: :ok | {:error, term()}
  def subscribe(conn, opts \\ []) when is_pid(conn) and is_list(opts) do
    case safe_connection_call(conn, {:subscribe, self(), opts}, @default_call_timeout_ms) do
      {:ok, reply} -> reply
      {:error, reason} -> {:error, reason}
    end
  end

  @spec unsubscribe(connection()) :: :ok
  def unsubscribe(conn) when is_pid(conn) do
    case safe_connection_call(conn, {:unsubscribe, self()}, @default_call_timeout_ms) do
      {:ok, :ok} -> :ok
      {:error, _reason} -> :ok
    end
  end

  @spec request(connection(), String.t(), map() | list() | nil, keyword()) ::
          {:ok, term()} | {:error, term()}
  def request(conn, method, params \\ nil, opts \\ [])
      when is_pid(conn) and is_binary(method) and is_list(opts) do
    timeout_ms = Keyword.get(opts, :timeout_ms, @default_request_timeout_ms)

    case safe_connection_call(conn, {:request, method, params, timeout_ms}, timeout_ms + 1_000) do
      {:ok, reply} -> reply
      {:error, reason} -> {:error, reason}
    end
  end

  @spec respond(connection(), request_id(), map()) :: :ok | {:error, term()}
  def respond(conn, id, result) when is_pid(conn) and is_map(result) do
    case safe_connection_call(conn, {:respond, id, result}, @default_call_timeout_ms) do
      {:ok, reply} -> reply
      {:error, reason} -> {:error, reason}
    end
  end

  @spec respond_error(connection(), request_id(), integer(), String.t(), map() | nil) ::
          :ok | {:error, term()}
  def respond_error(conn, id, code, message, data \\ nil)
      when is_pid(conn) and is_integer(code) and is_binary(message) do
    case safe_connection_call(
           conn,
           {:respond_error, id, code, message, data},
           @default_call_timeout_ms
         ) do
      {:ok, reply} -> reply
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def init({%Options{} = codex_opts, opts}) do
    {transport_mod, transport_opts} = resolve_transport(opts)
    init_timeout_ms = Keyword.get(opts, :init_timeout_ms, @default_init_timeout_ms)

    client_name = Keyword.get(opts, :client_name, "codex_sdk")
    client_title = Keyword.get(opts, :client_title)
    client_version = Keyword.get(opts, :client_version, default_client_version())
    experimental_api = Keyword.get(opts, :experimental_api, false)

    init_params =
      initialize_params(client_name, client_version, client_title, experimental_api)

    with {:ok, binary_path} <- build_command(codex_opts),
         {:ok, cwd} <- normalize_cwd(Keyword.get(opts, :cwd)),
         {:ok, env} <- build_env(codex_opts, opts),
         invocation <- Command.new(binary_path, ["app-server"], cwd: cwd, env: env),
         {:ok, raw_session} <-
           RawSession.start_link(
             invocation,
             [
               receiver: self(),
               event_tag: :codex_io_transport,
               transport_module: transport_mod,
               stdout_mode: :line,
               stdin_mode: :raw
             ] ++ transport_opts
           ) do
      initialize_transport(raw_session, codex_opts, init_timeout_ms, init_params)
    else
      {:error, _} = error -> error
    end
  end

  defp initialize_transport(raw_session, codex_opts, init_timeout_ms, init_params) do
    case RawSession.send_input(
           raw_session,
           Protocol.encode_request(
             0,
             "initialize",
             init_params
           )
         ) do
      :ok ->
        timer_ref = Process.send_after(self(), {:request_timeout, 0}, init_timeout_ms)

        {:ok,
         %State{
           codex_opts: codex_opts,
           raw_session: raw_session,
           phase: :initializing,
           next_id: 1,
           pending: %{
             0 => %{
               from: :init,
               method: "initialize",
               timeout_ms: init_timeout_ms,
               timer_ref: timer_ref
             }
           },
           ready_waiters: [],
           subscribers: %{},
           subscriber_refs: %{}
         }}

      {:error, _} = error ->
        _ = RawSession.force_close(raw_session)
        error
    end
  end

  defp initialize_params(client_name, client_version, client_title, experimental_api) do
    %{
      "clientInfo" =>
        %{"name" => client_name, "version" => client_version}
        |> put_optional("title", client_title)
    }
    |> put_optional(
      "capabilities",
      if(experimental_api, do: %{"experimentalApi" => true}, else: nil)
    )
  end

  @impl true
  def handle_call(:await_ready, _from, %State{phase: :ready} = state) do
    {:reply, :ok, state}
  end

  def handle_call(:await_ready, from, %State{} = state) do
    {:noreply, %State{state | ready_waiters: [from | state.ready_waiters]}}
  end

  def handle_call({:subscribe, pid, opts}, _from, %State{} = state) do
    ref = Process.monitor(pid)

    filters = normalize_subscriber_filters(opts)

    {:reply, :ok,
     %State{
       state
       | subscribers: Map.put(state.subscribers, pid, filters),
         subscriber_refs: Map.put(state.subscriber_refs, ref, pid)
     }}
  end

  def handle_call({:unsubscribe, pid}, _from, %State{} = state) do
    {refs_to_drop, subscriber_refs} =
      Enum.reduce(state.subscriber_refs, {[], %{}}, fn {ref, sub_pid}, {refs, acc} ->
        if sub_pid == pid, do: {[ref | refs], acc}, else: {refs, Map.put(acc, ref, sub_pid)}
      end)

    Enum.each(refs_to_drop, &Process.demonitor(&1, [:flush]))

    {:reply, :ok,
     %State{
       state
       | subscribers: Map.delete(state.subscribers, pid),
         subscriber_refs: subscriber_refs
     }}
  end

  def handle_call({:respond, id, result}, _from, %State{} = state) do
    with :ok <- send_iolist(state, Protocol.encode_response(id, result)) do
      {:reply, :ok, state}
    end
  end

  def handle_call({:respond_error, id, code, message, data}, _from, %State{} = state) do
    with :ok <- send_iolist(state, Protocol.encode_error(id, code, message, data)) do
      {:reply, :ok, state}
    end
  end

  def handle_call({:request, _method, _params, _timeout_ms}, _from, %State{phase: phase} = state)
      when phase != :ready do
    {:reply, {:error, :not_ready}, state}
  end

  def handle_call({:request, method, params, timeout_ms}, from, %State{} = state) do
    id = state.next_id
    timer_ref = Process.send_after(self(), {:request_timeout, id}, timeout_ms)

    pending =
      Map.put(state.pending, id, %{
        from: from,
        method: method,
        timeout_ms: timeout_ms,
        timer_ref: timer_ref
      })

    case send_iolist(state, Protocol.encode_request(id, method, params)) do
      :ok ->
        {:noreply, %State{state | next_id: id + 1, pending: pending}}

      {:error, reason} ->
        _ = Process.cancel_timer(timer_ref)
        {:reply, {:error, reason}, %State{state | pending: state.pending}}
    end
  end

  @impl true
  def handle_info(
        {:codex_io_transport, ref, {:message, line}},
        %State{raw_session: %RawSession{transport_ref: ref}} = state
      ) do
    case Buffer.decode_line(line) do
      {:ok, msg} ->
        handle_incoming_result(handle_incoming_message(state, msg))

      {:non_json, raw} ->
        Logger.debug("Ignoring non-JSON app-server output: #{inspect(raw)}")
        {:noreply, state}
    end
  end

  def handle_info(
        {:codex_io_transport, ref, {:stderr, data}},
        %State{raw_session: %RawSession{transport_ref: ref}} = state
      ) do
    Logger.debug("codex app-server stderr: #{String.trim(IO.iodata_to_binary(data))}")
    {:noreply, state}
  end

  def handle_info(
        {:codex_io_transport, ref, {:error, reason}},
        %State{raw_session: %RawSession{transport_ref: ref}} = state
      ) do
    Logger.debug("Transport error from codex app-server: #{inspect(reason)}")
    {:noreply, state}
  end

  def handle_info(
        {:codex_io_transport, ref, {:exit, reason}},
        %State{raw_session: %RawSession{transport_ref: ref}} = state
      ) do
    failure = app_server_down_failure(state, reason)
    Logger.warning("codex app-server exited: #{inspect(failure)}")
    state = fail_transport_waiters(state, failure)
    {:stop, {:shutdown, failure}, state}
  end

  # Backward-compatibility for tests that still send legacy subprocess-shaped messages.
  def handle_info(
        {:stdout, ref, chunk},
        %State{raw_session: %RawSession{transport_ref: ref}} = state
      ) do
    {messages, _buffer, non_json} = Protocol.decode_lines("", chunk)

    Enum.each(non_json, fn raw ->
      Logger.debug("Ignoring non-JSON app-server output: #{inspect(raw)}")
    end)

    state =
      Enum.reduce_while(messages, {:ok, state}, fn msg, {:ok, acc} ->
        case handle_incoming_message(acc, msg) do
          {:ok, next_state} ->
            {:cont, {:ok, next_state}}

          {:stop, reason, next_state} ->
            {:halt, {:stop, reason, next_state}}
        end
      end)

    case state do
      {:ok, next_state} ->
        {:noreply, next_state}

      {:stop, reason, next_state} ->
        {:stop, reason, next_state}
    end
  end

  def handle_info(
        {:stderr, ref, data},
        %State{raw_session: %RawSession{transport_ref: ref}} = state
      ) do
    Logger.debug("codex app-server stderr: #{String.trim(IO.iodata_to_binary(data))}")
    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, pid, _reason}, %State{} = state) do
    state =
      case Map.pop(state.subscriber_refs, ref) do
        {nil, _refs} ->
          state

        {^pid, refs} ->
          %State{state | subscriber_refs: refs, subscribers: Map.delete(state.subscribers, pid)}
      end

    {:noreply, state}
  end

  def handle_info({:request_timeout, id}, %State{} = state) do
    case Map.pop(state.pending, id) do
      {nil, _pending} ->
        {:noreply, state}

      {%{from: :init, timeout_ms: timeout_ms}, pending} ->
        Enum.each(state.ready_waiters, fn from ->
          GenServer.reply(from, {:error, {:init_timeout, timeout_ms}})
        end)

        stop_subprocess(state)
        {:stop, :normal, %State{state | pending: pending, ready_waiters: []}}

      {%{from: from, method: method, timeout_ms: timeout_ms}, pending} ->
        GenServer.reply(from, {:error, {:timeout, method, timeout_ms}})
        {:noreply, %State{state | pending: pending}}
    end
  end

  def handle_info(_msg, %State{} = state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, %State{} = state) do
    stop_subprocess(state)
    :ok
  end

  defp handle_incoming_message(%State{} = state, msg) when is_map(msg) do
    case Protocol.message_type(msg) do
      :notification ->
        method = Map.get(msg, "method")
        params = Map.get(msg, "params") || %{}
        {:ok, broadcast_notification(state, method, params)}

      :request ->
        id = Map.get(msg, "id")
        method = Map.get(msg, "method")
        params = Map.get(msg, "params") || %{}
        {:ok, broadcast_request(state, id, method, params)}

      :response ->
        handle_response(state, Map.get(msg, "id"), {:ok, Map.get(msg, "result")})

      :error ->
        handle_response(state, Map.get(msg, "id"), {:error, Map.get(msg, "error")})

      :unknown ->
        Logger.debug("Ignoring unknown JSON-RPC message: #{inspect(msg)}")
        {:ok, state}
    end
  end

  defp handle_response(%State{} = state, id, reply) do
    case Map.pop(state.pending, id) do
      {nil, _pending} ->
        Logger.debug("Ignoring response for unknown request id: #{inspect(id)}")
        {:ok, state}

      {%{from: :init, timer_ref: timer_ref}, pending} ->
        _ = Process.cancel_timer(timer_ref)
        handle_init_reply(%State{state | pending: pending}, reply)

      {%{from: from, timer_ref: timer_ref}, pending} ->
        _ = Process.cancel_timer(timer_ref)
        GenServer.reply(from, reply)
        {:ok, %State{state | pending: pending}}
    end
  end

  defp handle_init_reply(%State{} = state, {:ok, _result}) do
    case send_iolist(state, Protocol.encode_notification("initialized")) do
      :ok ->
        reply_ready_waiters(state.ready_waiters, :ok)
        {:ok, %State{state | phase: :ready, ready_waiters: []}}

      {:error, reason} ->
        fail_init(state, reason)
    end
  end

  defp handle_init_reply(%State{} = state, {:error, reason}) do
    fail_init(state, reason)
  end

  defp fail_init(%State{} = state, reason) do
    failure = {:init_failed, reason}
    reply_ready_waiters(state.ready_waiters, {:error, failure})
    stop_subprocess(state)
    {:stop, :normal, %State{state | ready_waiters: []}}
  end

  defp reply_ready_waiters(waiters, reply) do
    Enum.each(waiters, fn from -> GenServer.reply(from, reply) end)
  end

  defp fail_transport_waiters(%State{} = state, failure) do
    reply_ready_waiters(state.ready_waiters, {:error, failure})

    Enum.each(state.pending, fn
      {_id, %{from: :init, timer_ref: timer_ref}} ->
        _ = Process.cancel_timer(timer_ref)

      {_id, %{from: from, timer_ref: timer_ref}} ->
        _ = Process.cancel_timer(timer_ref)
        GenServer.reply(from, {:error, failure})
    end)

    %State{state | pending: %{}, ready_waiters: []}
  end

  defp handle_incoming_result({:ok, %State{} = state}), do: {:noreply, state}
  defp handle_incoming_result({:stop, reason, %State{} = state}), do: {:stop, reason, state}

  defp broadcast_notification(%State{} = state, method, params) do
    Enum.each(state.subscribers, fn {pid, filters} ->
      if subscriber_match?(filters, method, params) do
        send(pid, {:codex_notification, method, params})
      end
    end)

    state
  end

  defp broadcast_request(%State{} = state, id, method, params) do
    Enum.each(state.subscribers, fn {pid, filters} ->
      if subscriber_match?(filters, method, params) do
        send(pid, {:codex_request, id, method, params})
      end
    end)

    state
  end

  defp subscriber_match?(%{methods: nil, thread_id: nil}, _method, _params), do: true

  defp subscriber_match?(filters, method, params) do
    method_matches?(filters.methods, method) and thread_matches?(filters.thread_id, params)
  end

  defp method_matches?(nil, _method), do: true
  defp method_matches?(methods, method) when is_list(methods), do: method in methods
  defp method_matches?(_methods, _method), do: false

  defp thread_matches?(nil, _params), do: true

  defp thread_matches?(thread_id, params) when is_binary(thread_id) do
    case Map.get(params, "threadId") || Map.get(params, "thread_id") ||
           Map.get(params, :thread_id) do
      nil -> true
      params_thread_id -> thread_id == params_thread_id
    end
  end

  defp thread_matches?(_thread_id, _params), do: false

  defp normalize_subscriber_filters(opts) do
    methods =
      case Keyword.get(opts, :methods) do
        nil -> nil
        list when is_list(list) -> normalize_methods(list)
        _ -> :invalid
      end

    thread_id =
      case Keyword.get(opts, :thread_id) do
        nil -> nil
        id when is_binary(id) -> id
        _ -> :invalid
      end

    %{methods: methods, thread_id: thread_id}
  end

  defp normalize_methods(list) do
    list
    |> Enum.reduce([], fn method, acc ->
      case normalize_method(method) do
        {:ok, value} -> [value | acc]
        :error -> acc
      end
    end)
    |> Enum.reverse()
  end

  defp normalize_method(value) when is_binary(value), do: {:ok, value}

  defp normalize_method(value) do
    case String.Chars.impl_for(value) do
      nil -> :error
      _ -> {:ok, to_string(value)}
    end
  end

  defp build_command(%Options{} = opts), do: Options.codex_path(opts)

  defp resolve_transport(opts) do
    opts
    |> Keyword.get(:transport)
    |> normalize_transport_option(opts)
  end

  defp normalize_transport_option(nil, opts) do
    opts
    |> Keyword.get(:subprocess)
    |> normalize_transport_value("subprocess")
  end

  defp normalize_transport_option(value, _opts) do
    normalize_transport_value(value, "transport")
  end

  defp normalize_transport_value(nil, _source), do: {Transport, []}

  defp normalize_transport_value({module, transport_opts}, _source)
       when is_atom(module) and is_list(transport_opts) do
    {module, transport_opts}
  end

  defp normalize_transport_value(module, _source) when is_atom(module), do: {module, []}

  defp normalize_transport_value(other, source) do
    raise ArgumentError, "invalid #{source} option: #{inspect(other)}"
  end

  defp safe_connection_call(conn, message, timeout) do
    {:ok, GenServer.call(conn, message, timeout)}
  catch
    :exit, reason ->
      {:error, normalize_call_exit(reason)}
  end

  defp normalize_call_exit({reason, {GenServer, :call, _}}), do: normalize_call_exit(reason)
  defp normalize_call_exit({:shutdown, reason}), do: normalize_call_exit(reason)
  defp normalize_call_exit({:init_failed, _} = reason), do: reason
  defp normalize_call_exit({:init_timeout, _} = reason), do: reason
  defp normalize_call_exit({:app_server_down, _} = reason), do: reason
  defp normalize_call_exit(:noproc), do: :not_connected
  defp normalize_call_exit(:timeout), do: :timeout
  defp normalize_call_exit(reason), do: reason

  defp app_server_down_failure(%State{} = state, reason) do
    details =
      %{reason: failure_reason(reason)}
      |> maybe_put_detail(:stderr, failure_stderr(state, reason))

    {:app_server_down, details}
  end

  defp maybe_put_detail(details, _key, value) when value in [nil, ""], do: details
  defp maybe_put_detail(details, key, value), do: Map.put(details, key, value)

  defp send_iolist(%State{raw_session: %RawSession{} = raw_session}, data) do
    RawSession.send_input(raw_session, data)
  end

  defp send_iolist(%State{}, _data), do: {:error, {:transport, :not_connected}}

  defp stop_subprocess(%State{raw_session: %RawSession{} = raw_session}) do
    RawSession.force_close(raw_session)
  catch
    :exit, _reason -> :ok
  end

  defp stop_subprocess(%State{}), do: :ok

  defp build_env(%Options{} = codex_opts, opts) when is_list(opts) do
    process_env = Keyword.get(opts, :process_env, Keyword.get(opts, :env, %{}))

    with {:ok, custom_env} <- RuntimeEnv.normalize_overrides(process_env) do
      codex_opts.api_key
      |> RuntimeEnv.base_overrides(codex_opts.base_url)
      |> Map.merge(custom_env, fn _key, _base, custom -> custom end)
      |> then(&{:ok, &1})
    end
  end

  defp transport_stderr(%State{raw_session: %RawSession{} = raw_session}) do
    RawSession.stderr(raw_session)
  catch
    :exit, _reason -> ""
  end

  defp failure_reason(%CliSubprocessCore.ProcessExit{reason: reason}), do: reason
  defp failure_reason(reason), do: reason

  defp failure_stderr(_state, %CliSubprocessCore.ProcessExit{stderr: stderr})
       when stderr not in [nil, ""] do
    stderr
  end

  defp failure_stderr(state, _reason), do: transport_stderr(state)

  defp default_client_version, do: Defaults.client_version()

  defp put_optional(map, _key, nil), do: map
  defp put_optional(map, key, value), do: Map.put(map, key, value)

  defp normalize_cwd(nil), do: {:ok, nil}

  defp normalize_cwd(cwd) when is_binary(cwd) do
    if String.trim(cwd) == "", do: {:error, {:invalid_cwd, cwd}}, else: {:ok, cwd}
  end

  defp normalize_cwd(cwd), do: {:error, {:invalid_cwd, cwd}}
end
