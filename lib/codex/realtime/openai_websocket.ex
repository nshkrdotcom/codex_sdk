defmodule Codex.Realtime.OpenAIWebSocket do
  @moduledoc """
  WebSocket client for OpenAI Realtime API.

  This module manages the WebSocket connection to OpenAI's Realtime API,
  handling connection lifecycle, message parsing, and event dispatching.

  ## Architecture

  The WebSocket client operates as a separate process that:

  1. Establishes and maintains the WebSocket connection
  2. Parses incoming JSON messages into structured events
  3. Forwards events to the session process and any registered listeners
  4. Sends outgoing messages (audio, user input, tool outputs, etc.)

  ## Usage

  This module is typically not used directly. Instead, use `Codex.Realtime.Session`
  which manages the WebSocket connection internally.

      {:ok, ws} = OpenAIWebSocket.start_link(
        session_pid: self(),
        config: %ModelConfig{api_key: "sk-..."},
        model_name: "gpt-4o-realtime-preview"
      )

      OpenAIWebSocket.send_message(ws, %{"type" => "response.create"})
  """

  use WebSockex

  alias Codex.Realtime.Config.ModelConfig
  alias Codex.Realtime.ModelEvents

  require Logger

  defstruct [:session_pid, :config, listeners: []]

  @type t :: %__MODULE__{
          session_pid: pid(),
          listeners: [pid()],
          config: ModelConfig.t()
        }

  @user_agent "CodexSDK/Elixir"

  # Client API

  @doc """
  Start the WebSocket connection.

  ## Options

    * `:session_pid` - Required. The session process to receive events.
    * `:config` - Required. The model configuration.
    * `:model_name` - Optional model name to use in the URL.

  ## Returns

    * `{:ok, pid}` on successful connection
    * `{:error, reason}` on failure
  """
  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(opts) do
    session_pid = Keyword.fetch!(opts, :session_pid)
    config = Keyword.fetch!(opts, :config)
    model_name = Keyword.get(opts, :model_name)

    url = ModelConfig.build_url(config, model_name)
    api_key = ModelConfig.resolve_api_key(config)

    headers = build_headers(api_key, config.headers)

    state = %__MODULE__{
      session_pid: session_pid,
      listeners: [],
      config: config
    }

    WebSockex.start_link(url, __MODULE__, state, extra_headers: headers)
  end

  @doc """
  Send a message to the WebSocket.

  Accepts a single message map or a list of message maps.

  ## Examples

      OpenAIWebSocket.send_message(ws, %{"type" => "response.create"})

      OpenAIWebSocket.send_message(ws, [
        %{"type" => "input_audio_buffer.append", "audio" => base64_audio},
        %{"type" => "input_audio_buffer.commit"}
      ])
  """
  @spec send_message(pid(), map() | [map()]) :: :ok
  def send_message(pid, messages) when is_list(messages) do
    Enum.each(messages, &send_message(pid, &1))
  end

  def send_message(pid, message) when is_map(message) do
    json = Jason.encode!(message)
    WebSockex.send_frame(pid, {:text, json})
  end

  @doc """
  Add a listener for events.

  Listeners receive `{:model_event, event}` messages for all events.
  """
  @spec add_listener(pid(), pid()) :: :ok
  def add_listener(pid, listener_pid) do
    WebSockex.cast(pid, {:add_listener, listener_pid})
  end

  @doc """
  Remove a listener.
  """
  @spec remove_listener(pid(), pid()) :: :ok
  def remove_listener(pid, listener_pid) do
    WebSockex.cast(pid, {:remove_listener, listener_pid})
  end

  # WebSockex Callbacks

  @impl true
  def handle_connect(_conn, state) do
    Logger.debug("Realtime WebSocket connected")
    notify_listeners(state, ModelEvents.connection_status(:connected))
    {:ok, state}
  end

  @impl true
  def handle_frame({:text, msg}, state) do
    case Jason.decode(msg) do
      {:ok, json} ->
        handle_json_message(json, state)

      {:error, reason} ->
        Logger.warning("Failed to decode WebSocket message: #{inspect(reason)}")
        {:ok, state}
    end
  end

  def handle_frame(_frame, state) do
    {:ok, state}
  end

  @impl true
  def handle_cast({:add_listener, pid}, state) do
    if pid in state.listeners do
      {:ok, state}
    else
      {:ok, %{state | listeners: [pid | state.listeners]}}
    end
  end

  def handle_cast({:remove_listener, pid}, state) do
    {:ok, %{state | listeners: List.delete(state.listeners, pid)}}
  end

  @impl true
  def handle_disconnect(disconnect_map, state) do
    Logger.info("Realtime WebSocket disconnected: #{inspect(disconnect_map)}")
    notify_listeners(state, ModelEvents.connection_status(:disconnected))
    {:ok, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.debug("Realtime WebSocket terminating: #{inspect(reason)}")
    notify_listeners(state, ModelEvents.connection_status(:disconnected))
    :ok
  end

  # Private Functions

  defp build_headers(api_key, custom_headers) do
    base_headers = [
      {"Authorization", "Bearer #{api_key}"},
      {"OpenAI-Beta", "realtime=v1"},
      {"User-Agent", @user_agent}
    ]

    case custom_headers do
      nil -> base_headers
      headers when is_map(headers) -> base_headers ++ Map.to_list(headers)
    end
  end

  defp handle_json_message(json, state) do
    # First emit raw server event
    raw_event = ModelEvents.raw_server_event(json)
    notify_listeners(state, raw_event)

    # Then parse and emit structured event
    case ModelEvents.from_json(json) do
      {:ok, event} ->
        notify_listeners(state, event)
        {:ok, state}

      {:error, reason} ->
        Logger.warning("Failed to parse model event: #{inspect(reason)}")
        {:ok, state}
    end
  end

  defp notify_listeners(state, event) do
    send(state.session_pid, {:model_event, event})

    Enum.each(state.listeners, fn pid ->
      send(pid, {:model_event, event})
    end)
  end
end
