defmodule Codex.AppServer.Connection do
  @moduledoc false

  use GenServer

  require Logger

  alias CliSubprocessCore.{Command, JSONRPC, TaskSupport}
  alias Codex.Config.Defaults
  alias Codex.Options
  alias Codex.Runtime.Env, as: RuntimeEnv

  @default_init_timeout_ms Defaults.app_server_init_timeout_ms()
  @default_request_timeout_ms Defaults.app_server_request_timeout_ms()
  @default_call_timeout_ms 5_000
  @default_stderr_limit Defaults.transport_max_stderr_buffer_size()

  defmodule State do
    @moduledoc false

    defstruct [
      :codex_opts,
      :session,
      :session_monitor_ref,
      :phase,
      :init_task_ref,
      :init_timeout_ms,
      :ready_waiters,
      :pending_requests,
      :subscribers,
      :subscriber_refs,
      :pending_peer_requests,
      :pending_peer_request_refs,
      :stderr,
      :stderr_limit
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
    init_timeout_ms = Keyword.get(opts, :init_timeout_ms, @default_init_timeout_ms)
    client_name = Keyword.get(opts, :client_name, "codex_sdk")
    client_title = Keyword.get(opts, :client_title)
    client_version = Keyword.get(opts, :client_version, default_client_version())
    experimental_api = Keyword.get(opts, :experimental_api, false)

    init_params =
      initialize_params(client_name, client_version, client_title, experimental_api)

    with {:ok, command_spec} <- build_command(codex_opts),
         {:ok, cwd} <- normalize_cwd(Keyword.get(opts, :cwd)),
         {:ok, env} <- build_env(codex_opts, opts),
         {:ok, execution_surface} <- effective_execution_surface(codex_opts, opts),
         invocation <- Command.new(command_spec, app_server_args(codex_opts), cwd: cwd, env: env),
         {:ok, session} <- start_protocol_session(invocation, execution_surface) do
      {:ok,
       %State{
         codex_opts: codex_opts,
         session: session,
         session_monitor_ref: Process.monitor(session),
         phase: :initializing,
         init_task_ref: nil,
         init_timeout_ms: init_timeout_ms,
         ready_waiters: [],
         pending_requests: %{},
         subscribers: %{},
         subscriber_refs: %{},
         pending_peer_requests: %{},
         pending_peer_request_refs: %{},
         stderr: "",
         stderr_limit: @default_stderr_limit
       }, {:continue, {:initialize, init_timeout_ms, init_params}}}
    else
      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_continue({:initialize, init_timeout_ms, init_params}, %State{} = state) do
    case start_init_task(state, init_timeout_ms, init_params) do
      {:ok, next_state} ->
        {:noreply, next_state}

      {:error, reason, next_state} ->
        {:stop, :normal, fail_init(next_state, {:init_failed, reason})}
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

  def handle_call({:request, _method, _params, _timeout_ms}, _from, %State{phase: phase} = state)
      when phase != :ready do
    {:reply, {:error, :not_ready}, state}
  end

  def handle_call({:request, method, params, timeout_ms}, from, %State{} = state) do
    case start_request_task(state, from, method, params, timeout_ms) do
      {:ok, next_state} ->
        {:noreply, next_state}

      {:error, reason, next_state} ->
        {:reply, {:error, reason}, next_state}
    end
  end

  def handle_call({:respond, id, result}, _from, %State{} = state) do
    case deliver_or_store_peer_request_reply(state, id, {:ok, result}) do
      {:ok, next_state} ->
        {:reply, :ok, next_state}

      {:error, reason, next_state} ->
        {:reply, reason, next_state}
    end
  end

  def handle_call({:respond_error, id, code, message, data}, _from, %State{} = state) do
    case deliver_or_store_peer_request_reply(
           state,
           id,
           {:error, encode_peer_error(code, message, data)}
         ) do
      {:ok, next_state} ->
        {:reply, :ok, next_state}

      {:error, reason, next_state} ->
        {:reply, reason, next_state}
    end
  end

  @impl true
  def handle_info({:jsonrpc_notification, notification}, %State{} = state)
      when is_map(notification) do
    method = Map.get(notification, "method")
    params = Map.get(notification, "params") || %{}
    {:noreply, broadcast_notification(state, method, params)}
  end

  def handle_info({:jsonrpc_peer_request, id, %{} = request}, %State{} = state) do
    method = Map.get(request, "method")
    params = Map.get(request, "params") || %{}

    case mark_peer_request_announced(state, id) do
      {:already_announced, next_state} ->
        {:noreply, next_state}

      {:announced, next_state} ->
        {:noreply, broadcast_request(next_state, id, method, params)}
    end
  end

  def handle_info({ref, result}, %State{} = state) when is_reference(ref) do
    cond do
      ref == state.init_task_ref ->
        handle_init_task_result(state, ref, result)

      Map.has_key?(state.pending_requests, ref) ->
        {:noreply, complete_request_task(state, ref, result)}

      true ->
        {:noreply, state}
    end
  end

  def handle_info(
        {:peer_request_pending, task_pid, reply_ref, %{} = request},
        %State{} = state
      ) do
    id = Map.get(request, "id")
    monitor_ref = Process.monitor(task_pid)
    entry = Map.get(state.pending_peer_requests, id, new_pending_peer_request())

    next_state =
      %State{
        state
        | pending_peer_requests:
            Map.put(state.pending_peer_requests, id, %{
              entry
              | task_pid: task_pid,
                reply_ref: reply_ref,
                monitor_ref: monitor_ref
            }),
          pending_peer_request_refs: Map.put(state.pending_peer_request_refs, monitor_ref, id)
      }

    {:noreply, maybe_deliver_pending_peer_reply(next_state, id)}
  end

  def handle_info({:jsonrpc_stderr, chunk}, %State{} = state) do
    {:noreply, %{state | stderr: append_stderr(state.stderr, chunk, state.stderr_limit)}}
  end

  def handle_info({:jsonrpc_protocol_error, reason}, %State{} = state) do
    Logger.debug("Ignoring app-server protocol error: #{inspect(reason)}")
    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, pid, reason}, %State{} = state) do
    cond do
      ref == state.session_monitor_ref and pid == state.session ->
        failure = app_server_down_failure(state, reason)
        Logger.warning("codex app-server exited: #{inspect(failure)}")
        {:stop, {:shutdown, failure}, fail_transport_waiters(state, failure)}

      ref == state.init_task_ref ->
        {:stop, :normal,
         fail_init(clear_init_task(state, ref), {:init_failed, {:task_exit, reason}})}

      Map.has_key?(state.pending_requests, ref) ->
        {:noreply, fail_request_task(state, ref, reason)}

      Map.has_key?(state.pending_peer_request_refs, ref) ->
        {:noreply, drop_pending_peer_request_by_ref(state, ref)}

      true ->
        {:noreply, drop_subscriber_by_ref(state, ref, pid)}
    end
  end

  def handle_info(_msg, %State{} = state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, %State{} = state) do
    close_session(state.session)
    :ok
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

  defp mark_ready(%State{} = state) do
    reply_ready_waiters(state.ready_waiters, :ok)
    %State{state | phase: :ready, ready_waiters: []}
  end

  defp fail_init(%State{} = state, reason) do
    reply_ready_waiters(state.ready_waiters, {:error, reason})
    %State{state | ready_waiters: []}
  end

  defp reply_ready_waiters(waiters, reply) do
    Enum.each(waiters, fn from -> GenServer.reply(from, reply) end)
  end

  defp fail_transport_waiters(%State{} = state, failure) do
    reply_ready_waiters(state.ready_waiters, {:error, failure})

    Enum.each(state.pending_requests, fn
      {_ref, %{from: from}} ->
        GenServer.reply(from, {:error, failure})
    end)

    Enum.each(state.pending_peer_requests, fn
      {_id, %{task_pid: task_pid, reply_ref: reply_ref}}
      when is_pid(task_pid) and is_reference(reply_ref) ->
        send(task_pid, {:peer_request_reply, reply_ref, {:error, failure}})

      {_id, _pending} ->
        :ok
    end)

    %State{
      state
      | ready_waiters: [],
        init_task_ref: nil,
        pending_requests: %{},
        pending_peer_requests: %{},
        pending_peer_request_refs: %{}
    }
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

  defp build_command(%Options{} = opts), do: Options.codex_command_spec(opts)

  defp start_protocol_session(invocation, execution_surface) do
    owner = self()

    JSONRPC.start(
      Options.execution_surface_options(execution_surface) ++
        [
          command: invocation,
          ready_mode: :immediate,
          notification_handler: fn notification ->
            send(owner, {:jsonrpc_notification, notification})
          end,
          peer_request_notifier: fn correlation_key, request ->
            send(owner, {:jsonrpc_peer_request, correlation_key, request})
          end,
          protocol_error_handler: fn reason ->
            send(owner, {:jsonrpc_protocol_error, reason})
          end,
          stderr_handler: fn chunk ->
            send(owner, {:jsonrpc_stderr, IO.iodata_to_binary(chunk)})
          end,
          peer_request_handler: fn request ->
            await_peer_request_reply(owner, request)
          end
        ]
    )
  end

  defp await_peer_request_reply(owner, request) do
    reply_ref = make_ref()
    send(owner, {:peer_request_pending, self(), reply_ref, request})

    receive do
      {:peer_request_reply, ^reply_ref, reply} -> reply
    end
  end

  defp effective_execution_surface(%Options{} = codex_opts, opts) when is_list(opts) do
    case Keyword.fetch(opts, :execution_surface) do
      {:ok, execution_surface} -> Options.normalize_execution_surface(execution_surface)
      :error -> {:ok, codex_opts.execution_surface}
    end
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

  defp start_init_task(%State{session: session} = state, init_timeout_ms, init_params) do
    case TaskSupport.async_nolink(fn -> run_init_task(session, init_timeout_ms, init_params) end) do
      {:ok, task} ->
        {:ok, %State{state | init_task_ref: task.ref}}

      {:error, reason} ->
        {:error, reason, state}
    end
  end

  defp run_init_task(session, init_timeout_ms, init_params) do
    with :ok <- JSONRPC.await_ready(session, init_timeout_ms),
         {:ok, _result} <-
           JSONRPC.request(session, "initialize", init_params, timeout_ms: init_timeout_ms) do
      JSONRPC.notify(session, "initialized")
    end
  end

  defp start_request_task(%State{session: session} = state, from, method, params, timeout_ms) do
    case TaskSupport.async_nolink(fn ->
           JSONRPC.request(session, method, params, timeout_ms: timeout_ms)
         end) do
      {:ok, task} ->
        {:ok,
         %State{
           state
           | pending_requests:
               Map.put(state.pending_requests, task.ref, %{
                 from: from,
                 method: method,
                 timeout_ms: timeout_ms
               })
         }}

      {:error, reason} ->
        {:error, reason, state}
    end
  end

  defp handle_init_task_result(%State{} = state, ref, :ok) do
    {:noreply, mark_ready(clear_init_task(state, ref))}
  end

  defp handle_init_task_result(%State{} = state, ref, {:error, :timeout}) do
    next_state = clear_init_task(state, ref)
    {:stop, :normal, fail_init(next_state, {:init_timeout, next_state.init_timeout_ms})}
  end

  defp handle_init_task_result(%State{} = state, ref, {:error, reason}) do
    next_state = clear_init_task(state, ref)
    reason = normalize_session_error(next_state, reason)

    case reason do
      {:app_server_down, _} = failure ->
        {:stop, {:shutdown, failure}, fail_init(next_state, failure)}

      other ->
        {:stop, :normal, fail_init(next_state, {:init_failed, other})}
    end
  end

  defp complete_request_task(%State{} = state, ref, result) do
    case pop_pending_request(state, ref) do
      {nil, next_state} ->
        next_state

      {%{from: from} = request, next_state} ->
        GenServer.reply(from, normalize_request_result(next_state, request, result))
        next_state
    end
  end

  defp fail_request_task(%State{} = state, ref, reason) do
    case pop_pending_request(state, ref) do
      {nil, next_state} ->
        next_state

      {%{from: from}, next_state} ->
        GenServer.reply(from, {:error, {:request_task_exit, reason}})
        next_state
    end
  end

  defp normalize_request_result(%State{} = _state, _request, {:ok, _result} = ok), do: ok

  defp normalize_request_result(
         %State{} = _state,
         %{method: method, timeout_ms: timeout_ms},
         {:error, :timeout}
       ) do
    {:error, {:timeout, method, timeout_ms}}
  end

  defp normalize_request_result(%State{} = state, _request, {:error, reason}) do
    {:error, normalize_session_error(state, reason)}
  end

  defp normalize_request_result(%State{}, _request, other), do: {:ok, other}

  defp normalize_session_error(%State{} = state, reason) do
    reason = unwrap_session_error(reason)

    case reason do
      {:channel_exit, _} = channel_exit ->
        app_server_down_failure(state, channel_exit)

      {:channel_error, _} = channel_error ->
        app_server_down_failure(state, channel_error)

      {:fatal_protocol_error, _} = fatal ->
        app_server_down_failure(state, fatal)

      :noproc ->
        :not_connected

      other ->
        other
    end
  end

  defp unwrap_session_error({reason, {GenServer, :call, _}}), do: unwrap_session_error(reason)
  defp unwrap_session_error({:shutdown, reason}), do: unwrap_session_error(reason)
  defp unwrap_session_error(reason), do: reason

  defp clear_init_task(%State{} = state, ref) when ref == state.init_task_ref do
    Process.demonitor(ref, [:flush])
    %State{state | init_task_ref: nil}
  end

  defp clear_init_task(%State{} = state, _ref), do: state

  defp pop_pending_request(%State{} = state, ref) do
    case Map.pop(state.pending_requests, ref) do
      {nil, pending_requests} ->
        {nil, %State{state | pending_requests: pending_requests}}

      {request, pending_requests} ->
        Process.demonitor(ref, [:flush])
        {request, %State{state | pending_requests: pending_requests}}
    end
  end

  defp app_server_down_failure(%State{} = state, reason) do
    details =
      %{reason: failure_reason(reason)}
      |> maybe_put_detail(:stderr, failure_stderr(state, reason))

    {:app_server_down, details}
  end

  defp maybe_put_detail(details, _key, value) when value in [nil, ""], do: details
  defp maybe_put_detail(details, key, value), do: Map.put(details, key, value)

  defp build_env(%Options{} = codex_opts, opts) when is_list(opts) do
    process_env = Keyword.get(opts, :process_env, Keyword.get(opts, :env, %{}))

    with {:ok, custom_env} <- RuntimeEnv.normalize_overrides(process_env) do
      codex_opts.api_key
      |> RuntimeEnv.base_overrides(codex_opts.base_url)
      |> Map.merge(payload_env_overrides(codex_opts), fn _key, _base, payload -> payload end)
      |> Map.merge(custom_env, fn _key, _base, custom -> custom end)
      |> then(&{:ok, &1})
    end
  end

  defp app_server_args(%Options{} = codex_opts) do
    ["app-server"]
    |> maybe_append_configs(app_server_config_values(codex_opts))
  end

  defp app_server_config_values(%Options{} = codex_opts) do
    payload = codex_opts.model_payload
    metadata = payload_backend_metadata(payload)

    payload_values =
      metadata
      |> Map.get("config_values", [])
      |> List.wrap()
      |> Enum.filter(&(is_binary(&1) and &1 != ""))

    derived_values =
      []
      |> maybe_add_config_value("model_provider", app_server_model_provider(payload))
      |> maybe_add_config_value("model", normalize_option_string(codex_opts.model))

    (payload_values ++ derived_values)
    |> Enum.uniq()
  end

  defp app_server_model_provider(payload) when is_map(payload) do
    metadata = payload_backend_metadata(payload)

    case payload_provider_backend(payload) do
      backend when backend in [:oss, "oss"] ->
        Map.get(metadata, "oss_provider")

      backend when backend in [:model_provider, "model_provider"] ->
        Map.get(metadata, "model_provider")

      _ ->
        nil
    end
  end

  defp app_server_model_provider(_payload), do: nil

  defp payload_env_overrides(%Options{model_payload: payload}) do
    payload
    |> case do
      payload when is_map(payload) ->
        Map.get(payload, :env_overrides, Map.get(payload, "env_overrides", %{}))

      _ ->
        %{}
    end
    |> case do
      env when is_map(env) ->
        Map.new(env, fn {key, value} -> {to_string(key), to_string(value)} end)

      _ ->
        %{}
    end
  end

  defp payload_backend_metadata(payload) when is_map(payload) do
    Map.get(payload, :backend_metadata, Map.get(payload, "backend_metadata", %{}))
    |> case do
      metadata when is_map(metadata) -> metadata
      _ -> %{}
    end
  end

  defp payload_backend_metadata(_payload), do: %{}

  defp payload_provider_backend(payload) when is_map(payload) do
    Map.get(payload, :provider_backend, Map.get(payload, "provider_backend"))
  end

  defp maybe_add_config_value(values, _key, nil), do: values
  defp maybe_add_config_value(values, _key, ""), do: values

  defp maybe_add_config_value(values, key, value) when is_binary(key) do
    values ++ ["#{key}=#{inspect(value)}"]
  end

  defp maybe_append_configs(args, values) when is_list(values) do
    Enum.reduce(values, args, fn
      value, acc when is_binary(value) and value != "" -> acc ++ ["--config", value]
      _value, acc -> acc
    end)
  end

  defp normalize_option_string(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_option_string(value) when is_binary(value) and value != "", do: value
  defp normalize_option_string(_value), do: nil

  defp failure_reason({:channel_exit, %{reason: reason}}), do: reason
  defp failure_reason({:channel_error, reason}), do: reason
  defp failure_reason(reason), do: reason

  defp failure_stderr(_state, {:channel_exit, %{stderr: stderr}}) when stderr not in [nil, ""],
    do: stderr

  defp failure_stderr(%State{stderr: stderr}, _reason), do: stderr

  defp default_client_version, do: Defaults.client_version()

  defp put_optional(map, _key, nil), do: map
  defp put_optional(map, key, value), do: Map.put(map, key, value)

  defp normalize_cwd(nil), do: {:ok, nil}

  defp normalize_cwd(cwd) when is_binary(cwd) do
    if String.trim(cwd) == "", do: {:error, {:invalid_cwd, cwd}}, else: {:ok, cwd}
  end

  defp normalize_cwd(cwd), do: {:error, {:invalid_cwd, cwd}}

  defp append_stderr(current, chunk, limit) when is_binary(current) and is_integer(limit) do
    combined = current <> IO.iodata_to_binary(chunk)

    if byte_size(combined) <= limit do
      combined
    else
      :binary.part(combined, byte_size(combined) - limit, limit)
    end
  end

  defp drop_subscriber_by_ref(%State{} = state, ref, pid) do
    case Map.pop(state.subscriber_refs, ref) do
      {^pid, refs} ->
        %State{state | subscriber_refs: refs, subscribers: Map.delete(state.subscribers, pid)}

      _other ->
        state
    end
  end

  defp drop_pending_peer_request_by_ref(%State{} = state, ref) do
    case Map.pop(state.pending_peer_request_refs, ref) do
      {nil, refs} ->
        %State{state | pending_peer_request_refs: refs}

      {id, refs} ->
        %State{
          state
          | pending_peer_request_refs: refs,
            pending_peer_requests: Map.delete(state.pending_peer_requests, id)
        }
    end
  end

  defp missing_peer_request_reply(%State{session: session}, id) do
    if is_pid(session) and Process.alive?(session) do
      {:error, {:unknown_request, id}}
    else
      {:error, :not_connected}
    end
  end

  defp mark_peer_request_announced(%State{} = state, id) do
    case Map.get(state.pending_peer_requests, id) do
      %{announced?: true} ->
        {:already_announced, state}

      nil ->
        {:announced,
         %State{
           state
           | pending_peer_requests:
               Map.put(state.pending_peer_requests, id, %{
                 new_pending_peer_request()
                 | announced?: true
               })
         }}

      pending ->
        {:announced,
         %State{
           state
           | pending_peer_requests:
               Map.put(state.pending_peer_requests, id, %{pending | announced?: true})
         }}
    end
  end

  defp maybe_deliver_pending_peer_reply(%State{} = state, id) do
    case Map.get(state.pending_peer_requests, id) do
      %{pending_reply: reply, task_pid: task_pid, reply_ref: reply_ref}
      when not is_nil(reply) and is_pid(task_pid) and is_reference(reply_ref) ->
        deliver_peer_request_reply(state, id, task_pid, reply_ref, reply)

      _other ->
        state
    end
  end

  defp deliver_or_store_peer_request_reply(%State{} = state, id, reply) do
    case Map.get(state.pending_peer_requests, id) do
      nil ->
        {:error, missing_peer_request_reply(state, id), state}

      %{task_pid: task_pid, reply_ref: reply_ref}
      when is_pid(task_pid) and is_reference(reply_ref) ->
        {:ok, deliver_peer_request_reply(state, id, task_pid, reply_ref, reply)}

      pending ->
        {:ok,
         %State{
           state
           | pending_peer_requests:
               Map.put(state.pending_peer_requests, id, %{pending | pending_reply: reply})
         }}
    end
  end

  defp deliver_peer_request_reply(%State{} = state, id, task_pid, reply_ref, reply) do
    case Map.pop(state.pending_peer_requests, id) do
      {nil, _rest} ->
        state

      {%{monitor_ref: monitor_ref}, rest} ->
        if is_reference(monitor_ref) do
          Process.demonitor(monitor_ref, [:flush])
        end

        send(task_pid, {:peer_request_reply, reply_ref, reply})

        %State{
          state
          | pending_peer_requests: rest,
            pending_peer_request_refs:
              if(is_reference(monitor_ref),
                do: Map.delete(state.pending_peer_request_refs, monitor_ref),
                else: state.pending_peer_request_refs
              )
        }
    end
  end

  defp new_pending_peer_request do
    %{
      announced?: false,
      task_pid: nil,
      reply_ref: nil,
      monitor_ref: nil,
      pending_reply: nil
    }
  end

  defp encode_peer_error(code, message, nil), do: %{"code" => code, "message" => message}

  defp encode_peer_error(code, message, data) do
    %{"code" => code, "message" => message, "data" => data}
  end

  defp close_session(session) when is_pid(session) do
    JSONRPC.close(session)
  catch
    :exit, _reason -> :ok
  end

  defp close_session(_session), do: :ok
end
