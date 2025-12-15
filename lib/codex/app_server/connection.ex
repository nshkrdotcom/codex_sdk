defmodule Codex.AppServer.Connection do
  @moduledoc false

  use GenServer

  require Logger

  alias Codex.AppServer.Protocol
  alias Codex.AppServer.Subprocess.Erlexec
  alias Codex.Options

  @default_init_timeout_ms 10_000
  @default_request_timeout_ms 30_000

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
           subprocess_mod.start(command, start_opts(codex_opts), subprocess_opts),
         :ok <-
           subprocess_mod.send(
             subprocess_pid,
             Protocol.encode_request(0, "initialize", %{
               "clientInfo" =>
                 %{"name" => client_name, "version" => client_version}
                 |> put_optional("title", client_title)
             }),
             subprocess_opts
           ) do
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

    filters = %{
      thread_id: Keyword.get(opts, :thread_id),
      methods: Keyword.get(opts, :methods)
    }

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
    {:noreply, %State{state | stderr: [chunk | state.stderr]}}
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
    method_ok? =
      case filters.methods do
        nil -> true
        methods when is_list(methods) -> method in methods
      end

    thread_ok? =
      case filters.thread_id do
        nil ->
          true

        thread_id when is_binary(thread_id) ->
          params_thread_id =
            Map.get(params, "threadId") || Map.get(params, "thread_id") ||
              Map.get(params, :thread_id)

          thread_id == params_thread_id
      end

    method_ok? and thread_ok?
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
    case Application.ensure_all_started(:erlexec) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
      {:error, {:erlexec, {:already_started, _}}} -> :ok
      {:error, reason} -> {:error, reason}
    end
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
    base_env =
      []
      |> maybe_put_key("CODEX_API_KEY", opts.api_key)
      |> maybe_put_key("OPENAI_API_KEY", opts.api_key)
      |> maybe_put_key(
        "OPENAI_BASE_URL",
        if(opts.base_url != "https://api.openai.com/v1", do: opts.base_url, else: nil)
      )
      |> Map.new()

    Enum.map(base_env, fn {key, value} -> {key, value} end)
  end

  defp maybe_put_key(env, _key, nil), do: env
  defp maybe_put_key(env, _key, ""), do: env
  defp maybe_put_key(env, key, value), do: [{key, value} | env]

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
