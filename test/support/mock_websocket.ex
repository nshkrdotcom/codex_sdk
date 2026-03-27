defmodule Codex.Test.MockWebSocket do
  @moduledoc """
  Mock WebSocket for testing realtime sessions.

  This module provides a mock implementation that simulates WebSocket behavior
  for testing the realtime session without making actual network connections.

  ## Usage

      {:ok, mock_ws} = MockWebSocket.start_link(test_pid: self())
      {:ok, session} = Session.start_link(agent: agent, websocket_pid: mock_ws)

      # Simulate receiving an event from the server
      MockWebSocket.send_event(mock_ws, %{"type" => "response.created"})

      # Check what was sent to the server
      messages = MockWebSocket.get_sent_messages(mock_ws)
  """

  use GenServer

  defstruct [:test_pid, :events_to_send, sent_messages: []]

  @type t :: %__MODULE__{
          test_pid: pid(),
          events_to_send: [map()],
          sent_messages: [map()]
        }

  # Client API

  @doc """
  Start a mock WebSocket process.

  ## Options

    * `:test_pid` - Required. The test process to receive event notifications.
    * `:events` - Optional list of events to send on startup.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Simulate sending an event from the server to the session.
  """
  @spec send_event(GenServer.server(), map()) :: :ok
  def send_event(pid, event) do
    GenServer.cast(pid, {:send_event, event})
  end

  @doc """
  Get all messages that were sent to the server.
  """
  @spec get_sent_messages(GenServer.server()) :: [map()]
  def get_sent_messages(pid) do
    GenServer.call(pid, :get_sent_messages)
  end

  @doc """
  Clear all sent messages.
  """
  @spec clear_sent_messages(GenServer.server()) :: :ok
  def clear_sent_messages(pid) do
    GenServer.call(pid, :clear_sent_messages)
  end

  @doc """
  Check if the mock is alive.
  """
  @spec alive?(GenServer.server()) :: boolean()
  def alive?(pid) do
    Process.alive?(pid)
  end

  # Mock WebSockex interface - used by Session to send frames

  @doc """
  Simulate `send_frame/2` for the session transport contract.
  """
  @spec send_frame(GenServer.server(), {:text, String.t()}) :: :ok
  def send_frame(pid, {:text, json}) do
    GenServer.call(pid, {:send_to_server, Jason.decode!(json)})
  end

  @doc """
  Simulate graceful websocket shutdown for the session transport contract.
  """
  @spec close(GenServer.server()) :: :ok
  def close(pid) do
    GenServer.cast(pid, :close)
    :ok
  end

  # GenServer Callbacks

  @impl true
  def init(opts) do
    test_pid = Keyword.fetch!(opts, :test_pid)
    events = Keyword.get(opts, :events, [])
    {:ok, %__MODULE__{test_pid: test_pid, events_to_send: events}}
  end

  @impl true
  def handle_cast({:send_event, event}, state) do
    send(state.test_pid, {:websocket_event, event})
    {:noreply, state}
  end

  def handle_cast({:send_to_server, message}, state) do
    {:noreply, %{state | sent_messages: [message | state.sent_messages]}}
  end

  def handle_cast(:close, state) do
    {:stop, :normal, state}
  end

  @impl true
  def handle_call({:send_to_server, message}, _from, state) do
    send(state.test_pid, {:websocket_sent, message})
    {:reply, :ok, %{state | sent_messages: [message | state.sent_messages]}}
  end

  def handle_call(:get_sent_messages, _from, state) do
    {:reply, Enum.reverse(state.sent_messages), state}
  end

  def handle_call(:clear_sent_messages, _from, state) do
    {:reply, :ok, %{state | sent_messages: []}}
  end
end
