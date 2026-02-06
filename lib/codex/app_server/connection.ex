defmodule Codex.AppServer.Connection do
  @moduledoc false

  use GenServer

  require Logger

  alias Codex.AppServer.Protocol
  alias Codex.AppServer.Subprocess.Erlexec
  alias Codex.Options
  alias Codex.Runtime.Env, as: RuntimeEnv
  alias Codex.Runtime.Erlexec, as: RuntimeErlexec

  @default_init_timeout_ms 10_000
  @default_request_timeout_ms 30_000
  @stderr_buffer_limit 50

  defmodule State do
    @moduledoc false

    defstruct [
      :codex_opts,
      :subprocess_mod,
      :subprocess_opts,
      :subprocess_pid,
      :os_pid,
      :phase,
      :next_id,
      :stdout_buffer,
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
    subprocess_mod = resolve_subprocess_module(opts)
    subprocess_opts = resolve_subprocess_opts(opts)

    init_timeout_ms = Keyword.get(opts, :init_timeout_ms, @default_init_timeout_ms)

    client_name = Keyword.get(opts, :client_name, "codex_sdk")
    client_title = Keyword.get(opts, :client_title)
    client_version = Keyword.get(opts, :client_version, default_client_version())

    with :ok <- ensure_erlexec_started(subprocess_mod),
         {:ok, command} <- build_command(codex_opts),
         {:ok, subprocess_pid, os_pid} <-
           subprocess_mod.start(command, start_opts(codex_opts), subprocess_opts) do
      case subprocess_mod.send(
             subprocess_pid,
             Protocol.encode_request(0, "initialize", %{
               "clientInfo" =>
                 %{"name" => client_name, "version" => client_version}
                 |> put_optional("title", client_title)
             }),
             subprocess_opts
           ) do
        :ok ->
          timer_ref = Process.send_after(self(), {:request_timeout, 0}, init_timeout_ms)

          {:ok,
           %State{
             codex_opts: codex_opts,
             subprocess_mod: subprocess_mod,
             subprocess_opts: subprocess_opts,
             subprocess_pid: subprocess_pid,
             os_pid: os_pid,
             phase: :initializing,
             next_id: 1,
             stdout_buffer: "",
             stderr: [],
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
          _ = subprocess_mod.stop(subprocess_pid, subprocess_opts)
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
  def handle_info({:stdout, os_pid, chunk}, %State{os_pid: os_pid} = state) do
    {messages, buffer, non_json} = Protocol.decode_lines(state.stdout_buffer, chunk)

    Enum.each(non_json, fn raw ->
      Logger.debug("Ignoring non-JSON app-server output: #{inspect(raw)}")
    end)

    state =
      Enum.reduce(messages, %State{state | stdout_buffer: buffer}, fn msg, acc ->
        handle_incoming_message(acc, msg)
      end)

    {:noreply, state}
  end

  def handle_info({:stderr, os_pid, chunk}, %State{os_pid: os_pid} = state) do
    stderr = [chunk | state.stderr] |> Enum.take(@stderr_buffer_limit)
    {:noreply, %State{state | stderr: stderr}}
  end

  def handle_info({:DOWN, os_pid, :process, _pid, reason}, %State{os_pid: os_pid} = state) do
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

  defp resolve_subprocess_module(opts) do
    case Keyword.get(opts, :subprocess) do
      nil -> Erlexec
      {module, _} when is_atom(module) -> module
      module when is_atom(module) -> module
      other -> raise ArgumentError, "invalid subprocess option: #{inspect(other)}"
    end
  end

  defp resolve_subprocess_opts(opts) do
    case Keyword.get(opts, :subprocess) do
      {_module, sub_opts} when is_list(sub_opts) -> sub_opts
      _ -> []
    end
  end

  defp ensure_erlexec_started(Erlexec) do
    RuntimeErlexec.ensure_started()
  end

  defp ensure_erlexec_started(_other), do: :ok

  defp build_command(%Options{} = opts) do
    with {:ok, binary_path} <- Options.codex_path(opts) do
      command = Enum.map([binary_path, "app-server"], &to_charlist/1)
      {:ok, command}
    end
  end

  defp start_opts(%Options{} = opts) do
    env = build_env(opts)
    base = [:stdin, {:stdout, self()}, {:stderr, self()}, :monitor]

    if env == [] do
      base
    else
      [{:env, env} | base]
    end
  end

  defp build_env(%Options{} = opts) do
    opts.api_key
    |> RuntimeEnv.base_overrides(opts.base_url)
    |> RuntimeEnv.to_charlist_env()
  end

  defp send_iolist(%State{} = state, data) do
    state.subprocess_mod.send(state.subprocess_pid, data, state.subprocess_opts)
  end

  defp stop_subprocess(%State{} = state) do
    state.subprocess_mod.stop(state.subprocess_pid, state.subprocess_opts)
  end

  defp default_client_version do
    case Application.spec(:codex_sdk, :vsn) do
      nil -> "0.0.0"
      vsn -> to_string(vsn)
    end
  end

  defp put_optional(map, _key, nil), do: map
  defp put_optional(map, key, value), do: Map.put(map, key, value)
end
