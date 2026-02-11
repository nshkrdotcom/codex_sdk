defmodule Codex.MCP.Transport.StreamableHTTP do
  @moduledoc """
  Implements MCP JSON-RPC over HTTP with optional bearer or OAuth auth.
  """

  use GenServer

  alias Codex.Config.Defaults
  alias Codex.MCP.OAuth

  defmodule State do
    @moduledoc false

    defstruct [
      :url,
      :server_name,
      :bearer_token,
      :http_headers,
      :env_http_headers,
      :oauth_tokens,
      :oauth_store_mode,
      :work_queue,
      :in_flight,
      :pending,
      :responses
    ]
  end

  @type t :: pid()

  @default_notification_timeout_ms Defaults.mcp_notification_timeout_ms()

  @doc "Starts a streamable HTTP transport process."
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
    url = Keyword.fetch!(opts, :url)
    server_name = Keyword.fetch!(opts, :server_name)
    http_headers = normalize_headers(Keyword.get(opts, :http_headers))
    env_http_headers = normalize_headers(Keyword.get(opts, :env_http_headers))
    oauth_store_mode = Keyword.get(opts, :oauth_store_mode)

    bearer_token = resolve_bearer_token(opts)

    oauth_tokens =
      if bearer_token do
        nil
      else
        OAuth.load_tokens(server_name, url, oauth_store_mode)
      end

    {:ok,
     %State{
       url: url,
       server_name: server_name,
       bearer_token: bearer_token,
       http_headers: http_headers,
       env_http_headers: env_http_headers,
       oauth_tokens: oauth_tokens,
       oauth_store_mode: oauth_store_mode,
       work_queue: :queue.new(),
       in_flight: nil,
       pending: :queue.new(),
       responses: :queue.new()
     }}
  end

  @impl true
  def handle_call({:send, message}, from, %State{} = state) do
    if Map.has_key?(message, "id") do
      {:reply, :ok, %{state | pending: :queue.in(message, state.pending)}}
    else
      timeout_ms = @default_notification_timeout_ms
      job = {:send, from, message, timeout_ms}
      state = state |> enqueue_work(job) |> maybe_start_work()
      {:noreply, state}
    end
  end

  def handle_call({:recv, timeout_ms}, from, %State{} = state) do
    case pop_response(state) do
      {:ok, message, next_state} ->
        {:reply, {:ok, message}, next_state}

      :empty ->
        case :queue.out(state.pending) do
          {:empty, _} ->
            {:reply, {:error, :empty}, state}

          {{:value, request}, pending} ->
            job = {:recv, from, request, timeout_ms}
            state = %{state | pending: pending} |> enqueue_work(job) |> maybe_start_work()
            {:noreply, state}
        end
    end
  end

  @impl true
  def handle_info({:work_result, pid, result}, %State{in_flight: %{pid: pid} = in_flight} = state) do
    Process.demonitor(in_flight.ref, [:flush])
    state = %{state | in_flight: nil}
    state = handle_work_result(state, in_flight.job, result)
    {:noreply, maybe_start_work(state)}
  end

  def handle_info({:work_result, _pid, _result}, %State{} = state), do: {:noreply, state}

  def handle_info(
        {:DOWN, ref, :process, _pid, reason},
        %State{in_flight: %{ref: ref, job: job}} = state
      ) do
    state = %{state | in_flight: nil}
    state = handle_work_failure(state, job, {:worker_down, reason})
    {:noreply, maybe_start_work(state)}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, %State{} = state), do: {:noreply, state}

  def handle_info(_msg, %State{} = state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %State{} = state) do
    maybe_cleanup_in_flight(state.in_flight)

    state.work_queue
    |> :queue.to_list()
    |> Enum.each(&reply_job_error(&1, :closed))

    :ok
  end

  defp resolve_bearer_token(opts) do
    opts
    |> Keyword.get(:bearer_token)
    |> normalize_token()
    |> case do
      nil -> resolve_env_token(opts)
      token -> token
    end
  end

  defp resolve_env_token(opts) do
    opts
    |> Keyword.get(:bearer_token_env_var)
    |> resolve_env_var_token()
  end

  defp resolve_env_var_token(env_var) when is_binary(env_var) do
    env_var
    |> System.get_env()
    |> normalize_token()
  end

  defp resolve_env_var_token(_), do: nil

  defp normalize_token(token) when is_binary(token) and token != "", do: token
  defp normalize_token(_), do: nil

  defp enqueue_work(%State{} = state, job) do
    %{state | work_queue: :queue.in(job, state.work_queue)}
  end

  defp maybe_start_work(%State{in_flight: nil, work_queue: queue} = state) do
    case :queue.out(queue) do
      {:empty, _} ->
        state

      {{:value, job}, rest} ->
        start_work(state, job, rest)
    end
  end

  defp maybe_start_work(%State{} = state), do: state

  defp start_work(%State{} = state, job, rest_queue) do
    parent = self()

    runner = fn ->
      result = execute_work(state, job)
      Kernel.send(parent, {:work_result, self(), result})
    end

    {:ok, pid} = start_task(runner)
    ref = Process.monitor(pid)
    %{state | work_queue: rest_queue, in_flight: %{pid: pid, ref: ref, job: job}}
  end

  defp execute_work(%State{} = state, {_kind, _from, message, timeout_ms}) do
    case post_json(state, message, timeout_ms) do
      {:ok, messages, updated} ->
        {:ok, %{messages: messages, oauth_tokens: updated.oauth_tokens}}

      {:error, reason, updated} ->
        {:error, %{reason: reason, oauth_tokens: updated.oauth_tokens}}
    end
  rescue
    error -> {:error, %{reason: error, oauth_tokens: state.oauth_tokens}}
  catch
    kind, reason -> {:error, %{reason: {kind, reason}, oauth_tokens: state.oauth_tokens}}
  end

  defp handle_work_result(
         %State{} = state,
         job,
         {:ok, %{messages: messages, oauth_tokens: oauth_tokens}}
       ) do
    state = update_oauth_tokens(state, oauth_tokens)

    case job do
      {:send, from, _message, _timeout_ms} ->
        GenServer.reply(from, :ok)
        state

      {:recv, from, _message, _timeout_ms} ->
        {reply, next_state} = deliver_responses(state, messages)
        GenServer.reply(from, reply)
        next_state
    end
  end

  defp handle_work_result(
         %State{} = state,
         job,
         {:error, %{reason: reason, oauth_tokens: oauth_tokens}}
       ) do
    state = update_oauth_tokens(state, oauth_tokens)

    case job do
      {:send, from, _message, _timeout_ms} ->
        GenServer.reply(from, {:error, reason})
        state

      {:recv, from, _message, _timeout_ms} ->
        GenServer.reply(from, {:error, reason})
        state
    end
  end

  defp handle_work_result(%State{} = state, job, {:error, reason}) do
    case job do
      {:send, from, _message, _timeout_ms} ->
        GenServer.reply(from, {:error, reason})
        state

      {:recv, from, _message, _timeout_ms} ->
        GenServer.reply(from, {:error, reason})
        state
    end
  end

  defp handle_work_failure(%State{} = state, job, reason) do
    case job do
      {:send, from, _message, _timeout_ms} ->
        GenServer.reply(from, {:error, reason})
        state

      {:recv, from, _message, _timeout_ms} ->
        GenServer.reply(from, {:error, reason})
        state
    end
  end

  defp maybe_cleanup_in_flight(nil), do: :ok

  defp maybe_cleanup_in_flight(%{pid: pid, ref: ref, job: job}) do
    Process.demonitor(ref, [:flush])

    if Process.alive?(pid) do
      Process.exit(pid, :shutdown)
    end

    reply_job_error(job, :closed)
  end

  defp reply_job_error({:send, from, _message, _timeout_ms}, reason) do
    GenServer.reply(from, {:error, reason})
  end

  defp reply_job_error({:recv, from, _message, _timeout_ms}, reason) do
    GenServer.reply(from, {:error, reason})
  end

  defp update_oauth_tokens(%State{} = state, nil), do: state

  defp update_oauth_tokens(%State{} = state, tokens) do
    %{state | oauth_tokens: tokens}
  end

  defp deliver_responses(%State{} = state, messages) do
    case enqueue_responses(state, messages) do
      {:ok, message, next_state} -> {{:ok, message}, next_state}
      :empty -> {{:error, :empty}, state}
    end
  end

  @spec start_task((-> any())) :: {:ok, pid()}
  defp start_task(fun) do
    case Task.Supervisor.start_child(Codex.TaskSupervisor, fun) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, _} -> Task.start(fun)
    end
  catch
    :exit, _ -> Task.start(fun)
  end

  defp post_json(%State{} = state, message, timeout_ms) do
    with {:ok, updated} <- maybe_refresh_oauth(state, timeout_ms),
         {:ok, headers} <- build_headers(updated),
         {:ok, body} <- encode_body(message),
         {:ok, response} <- do_post(updated.url, body, headers, timeout_ms),
         {:ok, messages} <- decode_body(response) do
      {:ok, messages, updated}
    else
      {:error, reason} -> {:error, reason, state}
    end
  end

  defp do_post(url, body, headers, timeout_ms) do
    opts = [headers: headers, body: body, receive_timeout: timeout_ms]

    case Req.post(url, opts) do
      {:ok, %Req.Response{status: status, body: response_body}} when status in 200..299 ->
        {:ok, response_body}

      {:ok, %Req.Response{status: status, body: response_body}} ->
        {:error, {:http_error, status, response_body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp encode_body(message) do
    case Jason.encode(message) do
      {:ok, body} -> {:ok, body}
      {:error, reason} -> {:error, reason}
    end
  end

  defp decode_body(%{} = body), do: {:ok, [body]}

  defp decode_body(body) when is_binary(body) do
    trimmed = String.trim(body)

    cond do
      trimmed == "" ->
        {:ok, []}

      String.contains?(body, "data:") ->
        {:ok, parse_sse(body)}

      true ->
        case Jason.decode(body) do
          {:ok, %{} = map} ->
            {:ok, [map]}

          {:ok, list} when is_list(list) ->
            {:ok, Enum.filter(list, &is_map/1)}

          _ ->
            {:ok, parse_ndjson(body)}
        end
    end
  end

  defp decode_body(body), do: {:ok, [%{"raw" => inspect(body)}]}

  defp parse_sse(body) do
    body
    |> String.split(~r/\r?\n\r?\n/, trim: true)
    |> Enum.flat_map(&decode_sse_event/1)
  end

  defp decode_sse_event(event) do
    data =
      event
      |> String.split(~r/\r?\n/)
      |> Enum.filter(&String.starts_with?(&1, "data:"))
      |> Enum.map_join("\n", fn line ->
        line
        |> String.trim_leading("data:")
        |> String.trim_leading()
      end)

    case data do
      "" -> []
      "[DONE]" -> []
      _ -> decode_sse_payload(data)
    end
  end

  defp decode_sse_payload(data) do
    case Jason.decode(data) do
      {:ok, %{} = map} -> [map]
      _ -> []
    end
  end

  defp parse_ndjson(body) do
    body
    |> String.split(~r/\r?\n/, trim: true)
    |> Enum.flat_map(fn line ->
      case Jason.decode(line) do
        {:ok, %{} = map} -> [map]
        _ -> []
      end
    end)
  end

  defp maybe_refresh_oauth(%State{bearer_token: token} = state, _timeout_ms)
       when is_binary(token) and token != "" do
    {:ok, state}
  end

  defp maybe_refresh_oauth(%State{oauth_tokens: nil} = state, _timeout_ms), do: {:ok, state}

  defp maybe_refresh_oauth(%State{} = state, timeout_ms) do
    case OAuth.refresh_if_needed(state.oauth_tokens, state.url,
           timeout_ms: timeout_ms,
           http_headers: state.http_headers,
           env_http_headers: state.env_http_headers,
           store_mode: state.oauth_store_mode
         ) do
      {:ok, tokens} -> {:ok, %{state | oauth_tokens: tokens}}
      {:error, _} = error -> error
    end
  end

  defp build_headers(%State{} = state) do
    headers =
      [{"content-type", "application/json"}]
      |> add_default_headers(state.http_headers)
      |> add_env_headers(state.env_http_headers)
      |> add_auth_header(state)

    {:ok, headers}
  end

  defp add_default_headers(headers, http_headers) do
    Enum.reduce(http_headers, headers, fn {key, value}, acc ->
      [{key, value} | acc]
    end)
  end

  defp add_env_headers(headers, env_http_headers) do
    Enum.reduce(env_http_headers, headers, fn {key, env_var}, acc ->
      case System.get_env(env_var) do
        value when is_binary(value) and value != "" ->
          [{key, value} | acc]

        _ ->
          acc
      end
    end)
  end

  defp add_auth_header(headers, %State{bearer_token: token}) when is_binary(token) do
    [{"authorization", "Bearer " <> token} | headers]
  end

  defp add_auth_header(headers, %State{oauth_tokens: %{access_token: token}})
       when is_binary(token) and token != "" do
    [{"authorization", "Bearer " <> token} | headers]
  end

  defp add_auth_header(headers, _state), do: headers

  defp normalize_headers(nil), do: []
  defp normalize_headers(%{} = map), do: Enum.map(map, &stringify_header/1)
  defp normalize_headers(list) when is_list(list), do: Enum.map(list, &stringify_header/1)
  defp normalize_headers(_), do: []

  defp stringify_header({key, value}), do: {to_string(key), to_string(value)}

  defp pop_response(%State{} = state) do
    case :queue.out(state.responses) do
      {{:value, message}, responses} -> {:ok, message, %{state | responses: responses}}
      {:empty, _} -> :empty
    end
  end

  defp enqueue_responses(%State{} = state, messages) do
    updated = Enum.reduce(messages, state.responses, &:queue.in/2)
    pop_response(%{state | responses: updated})
  end
end
