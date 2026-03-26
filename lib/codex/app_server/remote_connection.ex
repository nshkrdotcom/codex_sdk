defmodule Codex.AppServer.RemoteConnection do
  @moduledoc false

  use GenServer

  require Logger

  alias Codex.AppServer.Protocol
  alias Codex.Config.Defaults

  @default_init_timeout_ms Defaults.app_server_init_timeout_ms()

  defmodule State do
    @moduledoc false

    defstruct [
      :websocket_url,
      :websocket_pid,
      :phase,
      :next_id,
      :pending,
      :ready_waiters,
      :subscribers,
      :subscriber_refs,
      :buffered_events,
      :disconnect_info
    ]
  end

  defmodule Socket do
    @moduledoc false

    use WebSockex

    alias Codex.Net.CA

    @type send_text_error ::
            %WebSockex.ConnError{}
            | %WebSockex.FrameEncodeError{}
            | %WebSockex.InvalidFrameError{}
            | %WebSockex.NotConnectedError{}

    @spec start_link(String.t(), pid(), [{String.t(), String.t()}]) :: GenServer.on_start()
    def start_link(url, owner, headers) when is_binary(url) and is_pid(owner) do
      ws_opts =
        [extra_headers: headers]
        |> maybe_put_ssl_options(CA.websocket_ssl_options())

      WebSockex.start_link(url, __MODULE__, %{owner: owner}, ws_opts)
    end

    @spec send_text(pid(), binary()) :: :ok | {:error, send_text_error()}
    def send_text(pid, text) when is_pid(pid) and is_binary(text) do
      WebSockex.send_frame(pid, {:text, text})
    end

    @spec close(pid()) :: :ok
    def close(pid) when is_pid(pid) do
      WebSockex.cast(pid, :close)
    end

    @impl true
    def handle_frame({:text, text}, %{owner: owner} = state) do
      send(owner, {:remote_socket, self(), {:text, text}})
      {:ok, state}
    end

    def handle_frame(_frame, state) do
      {:ok, state}
    end

    @impl true
    def handle_cast(:close, state) do
      {:close, state}
    end

    @impl true
    def handle_disconnect(status_map, %{owner: owner} = state) do
      send(owner, {:remote_socket, self(), {:disconnected, status_map}})
      {:ok, state}
    end

    defp maybe_put_ssl_options(opts, []), do: opts

    defp maybe_put_ssl_options(opts, ssl_options),
      do: Keyword.put(opts, :ssl_options, ssl_options)
  end

  @spec start_link({String.t(), keyword()}) :: GenServer.on_start()
  def start_link({websocket_url, opts}) when is_binary(websocket_url) and is_list(opts) do
    GenServer.start_link(__MODULE__, {websocket_url, opts})
  end

  @impl true
  def init({websocket_url, opts}) do
    Process.flag(:trap_exit, true)

    init_timeout_ms = Keyword.get(opts, :init_timeout_ms, @default_init_timeout_ms)
    client_name = Keyword.get(opts, :client_name, "codex_sdk")
    client_title = Keyword.get(opts, :client_title)
    client_version = Keyword.get(opts, :client_version, Defaults.client_version())
    experimental_api = Keyword.get(opts, :experimental_api, false)
    auth_headers = authorization_headers(Keyword.get(opts, :auth_token))

    init_params =
      initialize_params(client_name, client_version, client_title, experimental_api)

    with {:ok, websocket_pid} <- Socket.start_link(websocket_url, self(), auth_headers),
         :ok <-
           send_text_frame(websocket_pid, Protocol.encode_request(0, "initialize", init_params)) do
      timer_ref = Process.send_after(self(), {:request_timeout, 0}, init_timeout_ms)

      {:ok,
       %State{
         websocket_url: websocket_url,
         websocket_pid: websocket_pid,
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
         subscriber_refs: %{},
         buffered_events: [],
         disconnect_info: nil
       }}
    else
      {:error, _} = error -> error
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

    state = %State{
      state
      | subscribers: Map.put(state.subscribers, pid, filters),
        subscriber_refs: Map.put(state.subscriber_refs, ref, pid)
    }

    state =
      case state.buffered_events do
        [] ->
          state

        events ->
          send_buffered_events(pid, events)
          %State{state | buffered_events: []}
      end

    {:reply, :ok, state}
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
    with :ok <- send_text_frame(state.websocket_pid, Protocol.encode_response(id, result)) do
      {:reply, :ok, state}
    end
  end

  def handle_call({:respond_error, id, code, message, data}, _from, %State{} = state) do
    with :ok <-
           send_text_frame(state.websocket_pid, Protocol.encode_error(id, code, message, data)) do
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

    case send_text_frame(state.websocket_pid, Protocol.encode_request(id, method, params)) do
      :ok ->
        {:noreply, %State{state | next_id: id + 1, pending: pending}}

      {:error, reason} ->
        _ = Process.cancel_timer(timer_ref)
        {:reply, {:error, reason}, %State{state | pending: state.pending}}
    end
  end

  @impl true
  def handle_info(
        {:remote_socket, websocket_pid, {:text, text}},
        %State{websocket_pid: websocket_pid} = state
      ) do
    case Jason.decode(text) do
      {:ok, message} ->
        handle_incoming_result(handle_incoming_message(state, message))

      {:error, reason} ->
        failure = {:app_server_down, %{reason: {:invalid_jsonrpc, reason}, message: text}}
        state = fail_transport_waiters(state, failure)
        {:stop, {:shutdown, failure}, state}
    end
  end

  def handle_info(
        {:remote_socket, websocket_pid, {:disconnected, status_map}},
        %State{websocket_pid: websocket_pid} = state
      ) do
    {:noreply, %State{state | disconnect_info: status_map}}
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

        {:stop, :normal, %State{state | pending: pending, ready_waiters: []}}

      {%{from: from, method: method, timeout_ms: timeout_ms}, pending} ->
        GenServer.reply(from, {:error, {:timeout, method, timeout_ms}})
        {:noreply, %State{state | pending: pending}}
    end
  end

  def handle_info({:EXIT, websocket_pid, reason}, %State{websocket_pid: websocket_pid} = state) do
    failure = app_server_down_failure(state, reason)
    state = fail_transport_waiters(state, failure)
    {:stop, {:shutdown, failure}, state}
  end

  def handle_info(_message, %State{} = state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, %State{websocket_pid: websocket_pid}) do
    if is_pid(websocket_pid) do
      _ = Socket.close(websocket_pid)
    end

    :ok
  end

  defp handle_incoming_message(%State{} = state, message) when is_map(message) do
    case Protocol.message_type(message) do
      :notification ->
        method = Map.get(message, "method")
        params = Map.get(message, "params") || %{}
        {:ok, buffer_or_broadcast_notification(state, method, params)}

      :request ->
        id = Map.get(message, "id")
        method = Map.get(message, "method")
        params = Map.get(message, "params") || %{}
        {:ok, buffer_or_broadcast_request(state, id, method, params)}

      :response ->
        handle_response(state, Map.get(message, "id"), {:ok, Map.get(message, "result")})

      :error ->
        handle_response(state, Map.get(message, "id"), {:error, Map.get(message, "error")})

      :unknown ->
        Logger.debug("Ignoring unknown remote JSON-RPC message: #{inspect(message)}")
        {:ok, state}
    end
  end

  defp buffer_or_broadcast_notification(%State{phase: :initializing} = state, method, params) do
    %State{state | buffered_events: state.buffered_events ++ [{:notification, method, params}]}
  end

  defp buffer_or_broadcast_notification(%State{} = state, method, params) do
    broadcast_notification(state, method, params)
  end

  defp buffer_or_broadcast_request(%State{phase: :initializing} = state, id, method, params) do
    %State{state | buffered_events: state.buffered_events ++ [{:request, id, method, params}]}
  end

  defp buffer_or_broadcast_request(%State{} = state, id, method, params) do
    broadcast_request(state, id, method, params)
  end

  defp handle_response(%State{} = state, id, reply) do
    case Map.pop(state.pending, id) do
      {nil, _pending} ->
        Logger.debug("Ignoring response for unknown remote request id: #{inspect(id)}")
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
    case send_text_frame(state.websocket_pid, Protocol.encode_notification("initialized")) do
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

  defp send_buffered_events(pid, events) when is_pid(pid) do
    Enum.each(events, fn
      {:notification, method, params} ->
        send(pid, {:codex_notification, method, params})

      {:request, id, method, params} ->
        send(pid, {:codex_request, id, method, params})
    end)
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

  defp authorization_headers(nil), do: []
  defp authorization_headers(token), do: [{"authorization", "Bearer " <> token}]

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

  defp send_text_frame(websocket_pid, payload) when is_pid(websocket_pid) do
    payload =
      payload
      |> IO.iodata_to_binary()
      |> String.trim_trailing("\n")

    Socket.send_text(websocket_pid, payload)
  end

  defp send_text_frame(_websocket_pid, _payload), do: {:error, :not_connected}

  defp app_server_down_failure(%State{} = state, reason) do
    details =
      %{reason: normalize_disconnect_reason(reason)}
      |> maybe_put_detail(:message, disconnect_message(state.disconnect_info))

    {:app_server_down, details}
  end

  defp normalize_disconnect_reason({:shutdown, reason}), do: normalize_disconnect_reason(reason)
  defp normalize_disconnect_reason(reason), do: reason

  defp disconnect_message(%{reason: reason}) do
    inspect(reason)
  end

  defp disconnect_message(_), do: nil

  defp maybe_put_detail(details, _key, value) when value in [nil, ""], do: details
  defp maybe_put_detail(details, key, value), do: Map.put(details, key, value)

  defp put_optional(map, _key, nil), do: map
  defp put_optional(map, key, value), do: Map.put(map, key, value)
end
