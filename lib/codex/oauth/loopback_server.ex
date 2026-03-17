defmodule Codex.OAuth.LoopbackServer do
  @moduledoc false

  use GenServer

  alias Codex.OAuth.CallbackPlug

  defstruct [:pid, :callback_url, :port, :callback_path, :expected_state]

  @type t :: %__MODULE__{
          pid: pid(),
          callback_url: String.t(),
          port: non_neg_integer(),
          callback_path: String.t(),
          expected_state: String.t()
        }

  defmodule State do
    @moduledoc false

    defstruct [
      :bandit_pid,
      :callback_url,
      :callback_path,
      :expected_state,
      :port,
      :result,
      :waiter
    ]
  end

  @type callback_result ::
          {:ok, %{code: String.t(), state: String.t()}}
          | {:error, term()}

  @spec start(keyword()) :: {:ok, t()} | {:error, term()}
  def start(opts \\ []) when is_list(opts) do
    with {:ok, pid} <- GenServer.start_link(__MODULE__, opts),
         {:ok, info} <- GenServer.call(pid, :info) do
      {:ok,
       %__MODULE__{
         pid: pid,
         callback_url: info.callback_url,
         port: info.port,
         callback_path: info.callback_path,
         expected_state: info.expected_state
       }}
    end
  end

  @spec await_result(t(), pos_integer()) :: callback_result()
  def await_result(%__MODULE__{pid: pid}, timeout_ms)
      when is_integer(timeout_ms) and timeout_ms > 0 do
    GenServer.call(pid, {:await, timeout_ms}, timeout_ms + 100)
  catch
    :exit, {:normal, _} ->
      {:error, :not_running}

    :exit, reason ->
      {:error, reason}
  end

  @spec cancel(t()) :: :ok
  def cancel(%__MODULE__{pid: pid}) do
    GenServer.cast(pid, :cancel)
    :ok
  end

  @spec handle_callback(pid(), String.t(), map()) :: %{status: pos_integer(), body: String.t()}
  def handle_callback(pid, request_path, params)
      when is_pid(pid) and is_binary(request_path) and is_map(params) do
    GenServer.call(pid, {:callback, request_path, params}, 5_000)
  end

  @impl true
  def init(opts) do
    callback_path = Keyword.get(opts, :callback_path, "/auth/callback")
    expected_state = Keyword.fetch!(opts, :expected_state)
    port = Keyword.get(opts, :port, 0)

    with {:ok, bandit_pid} <-
           Bandit.start_link(
             plug: {CallbackPlug, server: self()},
             ip: {127, 0, 0, 1},
             port: port
           ),
         {:ok, {{127, 0, 0, 1}, actual_port}} <- ThousandIsland.listener_info(bandit_pid) do
      {:ok,
       %State{
         bandit_pid: bandit_pid,
         callback_url: "http://127.0.0.1:#{actual_port}#{callback_path}",
         callback_path: callback_path,
         expected_state: expected_state,
         port: actual_port
       }}
    else
      {:error, _} = error -> error
    end
  end

  @impl true
  def handle_call(:info, _from, %State{} = state) do
    {:reply,
     {:ok,
      %{
        callback_url: state.callback_url,
        callback_path: state.callback_path,
        expected_state: state.expected_state,
        port: state.port
      }}, state}
  end

  def handle_call({:await, _timeout_ms}, _from, %State{result: result} = state)
      when not is_nil(result) do
    {:reply, result, state}
  end

  def handle_call({:await, timeout_ms}, from, %State{} = state) do
    Process.send_after(self(), {:await_timeout, from}, timeout_ms)
    {:noreply, %State{state | waiter: from}}
  end

  def handle_call(
        {:callback, request_path, _params},
        _from,
        %State{callback_path: callback_path} = state
      )
      when request_path != callback_path do
    {:reply, %{status: 404, body: html_response("Not Found")}, state}
  end

  def handle_call(
        {:callback, _request_path, params},
        _from,
        %State{expected_state: expected_state} = state
      ) do
    case callback_result(params, expected_state) do
      {:ok, %{code: _code, state: _state} = result} ->
        state = put_result(state, {:ok, result})

        {:reply,
         %{
           status: 200,
           body: html_response("Login completed. You can return to the application.")
         }, state}

      {:error, reason, status, message} ->
        state = put_result(state, {:error, reason})
        {:reply, %{status: status, body: html_response(message)}, state}
    end
  end

  @impl true
  def handle_cast(:cancel, %State{} = state) do
    {:noreply, put_result(state, {:error, :cancelled})}
  end

  @impl true
  def handle_info({:await_timeout, from}, %State{waiter: from, result: nil} = state) do
    GenServer.reply(from, {:error, :timeout})
    {:noreply, %State{state | waiter: nil}}
  end

  def handle_info({:await_timeout, _from}, %State{} = state) do
    {:noreply, state}
  end

  def handle_info(:shutdown_bandit, %State{bandit_pid: bandit_pid} = state)
      when is_pid(bandit_pid) do
    _ = Supervisor.stop(bandit_pid)
    {:noreply, state}
  end

  def handle_info(:shutdown_bandit, %State{} = state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, %State{bandit_pid: bandit_pid}) when is_pid(bandit_pid) do
    _ = Supervisor.stop(bandit_pid)
    :ok
  end

  def terminate(_reason, _state), do: :ok

  defp callback_result(params, expected_state) do
    received_state = normalize_string(Map.get(params, "state"))

    cond do
      received_state != expected_state ->
        {:error, {:state_mismatch, %{expected: expected_state, received: received_state}}, 400,
         "OAuth state mismatch"}

      error = normalize_string(Map.get(params, "error")) ->
        message = normalize_string(Map.get(params, "error_description")) || error
        {:error, {:oauth_error, error, message}, 400, "OAuth login failed: #{message}"}

      code = normalize_string(Map.get(params, "code")) ->
        {:ok, %{code: code, state: expected_state}}

      true ->
        {:error, :missing_authorization_code, 400,
         "OAuth login failed: missing authorization code"}
    end
  end

  defp put_result(%State{result: nil, waiter: waiter} = state, result) do
    if waiter, do: GenServer.reply(waiter, result)
    send(self(), :shutdown_bandit)
    %State{state | result: result, waiter: nil}
  end

  defp put_result(%State{} = state, _result), do: state

  defp html_response(message) do
    """
    <!doctype html>
    <html>
      <body>
        <p>#{message}</p>
      </body>
    </html>
    """
  end

  defp normalize_string(nil), do: nil

  defp normalize_string(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end
end
