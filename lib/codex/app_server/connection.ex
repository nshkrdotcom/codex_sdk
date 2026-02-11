defmodule Codex.AppServer.Connection do
  @moduledoc false

  use GenServer

  require Logger

  alias Codex.AppServer.Protocol
  alias Codex.Config.Defaults
  alias Codex.IO.Buffer
  alias Codex.IO.Transport.Erlexec, as: IOTransportErlexec
  alias Codex.Options
  alias Codex.Runtime.Env, as: RuntimeEnv
  alias Codex.Runtime.Erlexec, as: RuntimeErlexec

  @default_init_timeout_ms Defaults.app_server_init_timeout_ms()
  @default_request_timeout_ms Defaults.app_server_request_timeout_ms()

  defmodule State do
    @moduledoc false

    defstruct [
      :codex_opts,
      :transport_mod,
      :transport,
      :transport_ref,
      :phase,
      :next_id,
      :stderr,
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
    GenServer.call(conn, :await_ready, timeout_ms)
  end

  @spec subscribe(connection(), keyword()) :: :ok | {:error, term()}
  def subscribe(conn, opts \\ []) when is_pid(conn) and is_list(opts) do
    GenServer.call(conn, {:subscribe, self(), opts})
  end

  @spec unsubscribe(connection()) :: :ok
  def unsubscribe(conn) when is_pid(conn) do
    GenServer.call(conn, {:unsubscribe, self()})
  end

  @spec request(connection(), String.t(), map() | list() | nil, keyword()) ::
          {:ok, term()} | {:error, term()}
  def request(conn, method, params \\ nil, opts \\ [])
      when is_pid(conn) and is_binary(method) and is_list(opts) do
    timeout_ms = Keyword.get(opts, :timeout_ms, @default_request_timeout_ms)
    GenServer.call(conn, {:request, method, params, timeout_ms}, timeout_ms + 1_000)
  end

  @spec respond(connection(), request_id(), map()) :: :ok | {:error, term()}
  def respond(conn, id, result) when is_pid(conn) and is_map(result) do
    GenServer.call(conn, {:respond, id, result})
  end

  @impl true
  def init({%Options{} = codex_opts, opts}) do
    {transport_mod, transport_opts} = resolve_transport(opts)
    init_timeout_ms = Keyword.get(opts, :init_timeout_ms, @default_init_timeout_ms)

    client_name = Keyword.get(opts, :client_name, "codex_sdk")
    client_title = Keyword.get(opts, :client_title)
    client_version = Keyword.get(opts, :client_version, default_client_version())
    transport_ref = make_ref()

    with :ok <- maybe_ensure_erlexec(transport_mod),
         {:ok, command} <- build_command(codex_opts),
         {:ok, transport} <-
           transport_mod.start_link(
             [
               command: command,
               env: build_env(codex_opts),
               subscriber: {self(), transport_ref}
             ] ++ transport_opts
           ) do
      case transport_mod.send(
             transport,
             Protocol.encode_request(0, "initialize", %{
               "clientInfo" =>
                 %{"name" => client_name, "version" => client_version}
                 |> put_optional("title", client_title)
             })
           ) do
        :ok ->
          timer_ref = Process.send_after(self(), {:request_timeout, 0}, init_timeout_ms)

          {:ok,
           %State{
             codex_opts: codex_opts,
             transport_mod: transport_mod,
             transport: transport,
             transport_ref: transport_ref,
             phase: :initializing,
             next_id: 1,
             stderr: "",
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
          _ = transport_mod.force_close(transport)
          error
      end
    else
      {:error, _} = error ->
        error

      other ->
        {:stop, other}
    end
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
        %State{transport_ref: ref} = state
      ) do
    case Buffer.decode_line(line) do
      {:ok, msg} ->
        {:noreply, handle_incoming_message(state, msg)}

      {:non_json, raw} ->
        Logger.debug("Ignoring non-JSON app-server output: #{inspect(raw)}")
        {:noreply, state}
    end
  end

  def handle_info(
        {:codex_io_transport, ref, {:stderr, data}},
        %State{transport_ref: ref} = state
      ) do
    {:noreply, %State{state | stderr: state.stderr <> IO.iodata_to_binary(data)}}
  end

  def handle_info(
        {:codex_io_transport, ref, {:error, reason}},
        %State{transport_ref: ref} = state
      ) do
    Logger.debug("Transport error from codex app-server: #{inspect(reason)}")
    {:noreply, state}
  end

  def handle_info({:codex_io_transport, ref, {:exit, reason}}, %State{transport_ref: ref} = state) do
    Logger.warning("codex app-server exited: #{inspect(reason)}")
    {:stop, {:app_server_down, reason}, state}
  end

  # Backward-compatibility for tests that still send legacy subprocess-shaped messages.
  def handle_info({:stdout, ref, chunk}, %State{transport_ref: ref} = state) do
    {messages, _buffer, non_json} = Protocol.decode_lines("", chunk)

    Enum.each(non_json, fn raw ->
      Logger.debug("Ignoring non-JSON app-server output: #{inspect(raw)}")
    end)

    state =
      Enum.reduce(messages, state, fn msg, acc ->
        handle_incoming_message(acc, msg)
      end)

    {:noreply, state}
  end

  def handle_info({:stderr, ref, data}, %State{transport_ref: ref} = state) do
    {:noreply, %State{state | stderr: state.stderr <> IO.iodata_to_binary(data)}}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %State{transport_ref: ref} = state) do
    Logger.warning("codex app-server exited: #{inspect(reason)}")
    {:stop, {:app_server_down, reason}, state}
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
        {:stop, {:init_timeout, timeout_ms}, %State{state | pending: pending}}

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
        broadcast_notification(state, method, params)

      :request ->
        id = Map.get(msg, "id")
        method = Map.get(msg, "method")
        params = Map.get(msg, "params") || %{}
        broadcast_request(state, id, method, params)

      :response ->
        handle_response(state, Map.get(msg, "id"), {:ok, Map.get(msg, "result")})

      :error ->
        handle_response(state, Map.get(msg, "id"), {:error, Map.get(msg, "error")})

      :unknown ->
        Logger.debug("Ignoring unknown JSON-RPC message: #{inspect(msg)}")
        state
    end
  end

  defp handle_response(%State{} = state, id, reply) do
    case Map.pop(state.pending, id) do
      {nil, _pending} ->
        Logger.debug("Ignoring response for unknown request id: #{inspect(id)}")
        state

      {%{from: :init, timer_ref: timer_ref}, pending} ->
        _ = Process.cancel_timer(timer_ref)
        _ = send_iolist(state, Protocol.encode_notification("initialized"))
        Enum.each(state.ready_waiters, fn from -> GenServer.reply(from, :ok) end)
        %State{state | phase: :ready, pending: pending, ready_waiters: []}

      {%{from: from, timer_ref: timer_ref}, pending} ->
        _ = Process.cancel_timer(timer_ref)
        GenServer.reply(from, reply)
        %State{state | pending: pending}
    end
  end

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
    params_thread_id =
      Map.get(params, "threadId") || Map.get(params, "thread_id") ||
        Map.get(params, :thread_id)

    thread_id == params_thread_id
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

  defp build_command(%Options{} = opts) do
    with {:ok, binary_path} <- Options.codex_path(opts) do
      command = Enum.map([binary_path, "app-server"], &to_charlist/1)
      {:ok, command}
    end
  end

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

  defp normalize_transport_value(nil, _source), do: {IOTransportErlexec, []}

  defp normalize_transport_value({module, transport_opts}, _source)
       when is_atom(module) and is_list(transport_opts) do
    {module, transport_opts}
  end

  defp normalize_transport_value(module, _source) when is_atom(module), do: {module, []}

  defp normalize_transport_value(other, source) do
    raise ArgumentError, "invalid #{source} option: #{inspect(other)}"
  end

  defp maybe_ensure_erlexec(IOTransportErlexec), do: RuntimeErlexec.ensure_started()
  defp maybe_ensure_erlexec(_other), do: :ok

  defp send_iolist(%State{transport_mod: transport_mod, transport: transport}, data)
       when is_atom(transport_mod) and is_pid(transport) do
    transport_mod.send(transport, data)
  end

  defp send_iolist(%State{}, _data), do: {:error, {:transport, :not_connected}}

  defp stop_subprocess(%State{transport_mod: transport_mod, transport: transport})
       when is_atom(transport_mod) and is_pid(transport) do
    transport_mod.force_close(transport)
  end

  defp stop_subprocess(%State{}), do: :ok

  defp build_env(%Options{} = opts) do
    opts.api_key
    |> RuntimeEnv.base_overrides(opts.base_url)
    |> RuntimeEnv.to_charlist_env()
  end

  defp default_client_version, do: Defaults.client_version()

  defp put_optional(map, _key, nil), do: map
  defp put_optional(map, key, value), do: Map.put(map, key, value)
end
