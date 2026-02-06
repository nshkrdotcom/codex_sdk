defmodule Codex.Realtime.SessionTest do
  use ExUnit.Case, async: true

  alias Codex.Realtime.Config.SessionModelSettings
  alias Codex.Realtime.Events
  alias Codex.Realtime.Items
  alias Codex.Realtime.ModelEvents
  alias Codex.Realtime.Session
  alias Codex.Test.MockWebSocket

  setup do
    agent = %{
      name: "TestAgent",
      model: "gpt-4o-realtime-preview",
      instructions: "Be helpful",
      tools: []
    }

    {:ok, agent: agent}
  end

  describe "start_link/1" do
    test "starts session with agent and mock websocket", %{agent: agent} do
      {:ok, mock_ws} = MockWebSocket.start_link(test_pid: self())

      {:ok, session} =
        Session.start_link(
          agent: agent,
          websocket_module: MockWebSocket,
          websocket_pid: mock_ws
        )

      assert Process.alive?(session)
      Session.close(session)
    end

    test "starts session with custom context", %{agent: agent} do
      {:ok, mock_ws} = MockWebSocket.start_link(test_pid: self())

      {:ok, session} =
        Session.start_link(
          agent: agent,
          websocket_pid: mock_ws,
          websocket_module: MockWebSocket,
          context: %{user_id: "123"}
        )

      assert Process.alive?(session)
      Session.close(session)
    end
  end

  describe "subscribe/2" do
    test "adds subscriber to receive events", %{agent: agent} do
      {:ok, mock_ws} = MockWebSocket.start_link(test_pid: self())

      {:ok, session} =
        Session.start_link(
          agent: agent,
          websocket_pid: mock_ws,
          websocket_module: MockWebSocket
        )

      :ok = Session.subscribe(session, self())

      # Simulate connection event
      send(session, {:model_event, ModelEvents.connection_status(:connected)})

      assert_receive {:session_event, %Events.AgentStartEvent{}}
      Session.close(session)
    end

    test "subscriber receives audio events", %{agent: agent} do
      {:ok, mock_ws} = MockWebSocket.start_link(test_pid: self())

      {:ok, session} =
        Session.start_link(
          agent: agent,
          websocket_pid: mock_ws,
          websocket_module: MockWebSocket
        )

      :ok = Session.subscribe(session, self())

      # Simulate audio event
      audio_event =
        ModelEvents.audio(
          data: <<1, 2, 3, 4>>,
          response_id: "resp_123",
          item_id: "item_456",
          content_index: 0
        )

      send(session, {:model_event, audio_event})

      assert_receive {:session_event, %Events.AudioEvent{item_id: "item_456"}}
      Session.close(session)
    end
  end

  describe "unsubscribe/2" do
    test "removes subscriber from receiving events", %{agent: agent} do
      {:ok, mock_ws} = MockWebSocket.start_link(test_pid: self())

      {:ok, session} =
        Session.start_link(
          agent: agent,
          websocket_pid: mock_ws,
          websocket_module: MockWebSocket
        )

      :ok = Session.subscribe(session, self())
      :ok = Session.unsubscribe(session, self())

      # Simulate event - should not receive it
      send(session, {:model_event, ModelEvents.connection_status(:connected)})

      refute_receive {:session_event, _}, 100
      Session.close(session)
    end
  end

  describe "send_audio/3" do
    test "sends audio to websocket", %{agent: agent} do
      {:ok, mock_ws} = MockWebSocket.start_link(test_pid: self())

      {:ok, session} =
        Session.start_link(
          agent: agent,
          websocket_pid: mock_ws,
          websocket_module: MockWebSocket
        )

      :ok = Session.send_audio(session, <<1, 2, 3, 4>>)

      messages = MockWebSocket.get_sent_messages(mock_ws)
      assert Enum.any?(messages, &(&1["type"] == "input_audio_buffer.append"))
      Session.close(session)
    end

    test "commits audio when requested", %{agent: agent} do
      {:ok, mock_ws} = MockWebSocket.start_link(test_pid: self())

      {:ok, session} =
        Session.start_link(
          agent: agent,
          websocket_pid: mock_ws,
          websocket_module: MockWebSocket
        )

      :ok = Session.send_audio(session, <<1, 2, 3, 4>>, commit: true)

      messages = MockWebSocket.get_sent_messages(mock_ws)
      assert Enum.any?(messages, &(&1["type"] == "input_audio_buffer.append"))
      assert Enum.any?(messages, &(&1["type"] == "input_audio_buffer.commit"))
      Session.close(session)
    end
  end

  describe "send_message/2" do
    test "sends text message", %{agent: agent} do
      {:ok, mock_ws} = MockWebSocket.start_link(test_pid: self())

      {:ok, session} =
        Session.start_link(
          agent: agent,
          websocket_pid: mock_ws,
          websocket_module: MockWebSocket
        )

      :ok = Session.send_message(session, "Hello!")

      messages = MockWebSocket.get_sent_messages(mock_ws)

      assert Enum.any?(messages, fn msg ->
               msg["type"] == "conversation.item.create" and
                 get_in(msg, ["item", "content", Access.at(0), "text"]) == "Hello!"
             end)

      # Also triggers response.create
      assert Enum.any?(messages, &(&1["type"] == "response.create"))
      Session.close(session)
    end

    test "sends structured message", %{agent: agent} do
      {:ok, mock_ws} = MockWebSocket.start_link(test_pid: self())

      {:ok, session} =
        Session.start_link(
          agent: agent,
          websocket_pid: mock_ws,
          websocket_module: MockWebSocket
        )

      message = %{
        "type" => "message",
        "role" => "user",
        "content" => [%{"type" => "input_text", "text" => "Hello structured!"}]
      }

      :ok = Session.send_message(session, message)

      messages = MockWebSocket.get_sent_messages(mock_ws)

      assert Enum.any?(messages, fn msg ->
               msg["type"] == "conversation.item.create" and
                 get_in(msg, ["item", "type"]) == "message"
             end)

      Session.close(session)
    end
  end

  describe "interrupt/1" do
    test "sends response cancel", %{agent: agent} do
      {:ok, mock_ws} = MockWebSocket.start_link(test_pid: self())

      {:ok, session} =
        Session.start_link(
          agent: agent,
          websocket_pid: mock_ws,
          websocket_module: MockWebSocket
        )

      :ok = Session.interrupt(session)

      messages = MockWebSocket.get_sent_messages(mock_ws)
      assert Enum.any?(messages, &(&1["type"] == "response.cancel"))
      Session.close(session)
    end
  end

  describe "send_raw_event/2" do
    test "sends raw event to websocket", %{agent: agent} do
      {:ok, mock_ws} = MockWebSocket.start_link(test_pid: self())

      {:ok, session} =
        Session.start_link(
          agent: agent,
          websocket_pid: mock_ws,
          websocket_module: MockWebSocket
        )

      :ok = Session.send_raw_event(session, %{"type" => "custom.event", "data" => "test"})

      messages = MockWebSocket.get_sent_messages(mock_ws)
      assert Enum.any?(messages, &(&1["type"] == "custom.event" and &1["data"] == "test"))
      Session.close(session)
    end
  end

  describe "update_session/2" do
    test "sends session update", %{agent: agent} do
      {:ok, mock_ws} = MockWebSocket.start_link(test_pid: self())

      {:ok, session} =
        Session.start_link(
          agent: agent,
          websocket_pid: mock_ws,
          websocket_module: MockWebSocket
        )

      settings = %SessionModelSettings{voice: "nova"}
      :ok = Session.update_session(session, settings)

      messages = MockWebSocket.get_sent_messages(mock_ws)

      assert Enum.any?(messages, fn msg ->
               msg["type"] == "session.update" and
                 get_in(msg, ["session", "voice"]) == "nova"
             end)

      Session.close(session)
    end
  end

  describe "history/1" do
    test "returns empty history initially", %{agent: agent} do
      {:ok, mock_ws} = MockWebSocket.start_link(test_pid: self())

      {:ok, session} =
        Session.start_link(
          agent: agent,
          websocket_pid: mock_ws,
          websocket_module: MockWebSocket
        )

      history = Session.history(session)
      assert history == []
      Session.close(session)
    end

    test "returns updated history after item events", %{agent: agent} do
      {:ok, mock_ws} = MockWebSocket.start_link(test_pid: self())

      {:ok, session} =
        Session.start_link(
          agent: agent,
          websocket_pid: mock_ws,
          websocket_module: MockWebSocket
        )

      :ok = Session.subscribe(session, self())

      # Simulate item update
      item =
        Items.user_message(
          "item_123",
          [Items.input_text("Hello!")],
          []
        )

      send(session, {:model_event, ModelEvents.item_updated(item)})

      # Wait for processing
      assert_receive {:session_event, %Events.HistoryAddedEvent{}}

      history = Session.history(session)
      assert length(history) == 1
      assert hd(history).item_id == "item_123"
      Session.close(session)
    end
  end

  describe "current_agent/1" do
    test "returns current agent", %{agent: agent} do
      {:ok, mock_ws} = MockWebSocket.start_link(test_pid: self())

      {:ok, session} =
        Session.start_link(
          agent: agent,
          websocket_pid: mock_ws,
          websocket_module: MockWebSocket
        )

      current = Session.current_agent(session)
      assert current.name == "TestAgent"
      Session.close(session)
    end
  end

  describe "tool execution" do
    test "executes tool and sends result", %{agent: _agent} do
      # Define agent with a tool
      agent = %{
        name: "ToolAgent",
        model: "gpt-4o-realtime-preview",
        instructions: "Use tools when needed",
        tools: [
          %{
            name: "get_weather",
            description: "Get weather for a city",
            on_invoke: fn args, _ctx -> "Weather in #{args["city"]}: Sunny, 72F" end
          }
        ]
      }

      {:ok, mock_ws} = MockWebSocket.start_link(test_pid: self())

      {:ok, session} =
        Session.start_link(
          agent: agent,
          websocket_pid: mock_ws,
          websocket_module: MockWebSocket
        )

      :ok = Session.subscribe(session, self())

      # Simulate tool call from model
      tool_call =
        ModelEvents.tool_call(
          name: "get_weather",
          call_id: "call_123",
          arguments: Jason.encode!(%{"city" => "Seattle"}),
          id: "item_456"
        )

      send(session, {:model_event, tool_call})

      # Should receive tool start and end events
      assert_receive {:session_event, %Events.ToolStartEvent{tool: %{name: "get_weather"}}}

      assert_receive {:session_event,
                      %Events.ToolEndEvent{output: "Weather in Seattle: Sunny, 72F"}}

      # Wait a moment for the session to send tool output
      Process.sleep(50)

      # Should send tool output to websocket
      messages = MockWebSocket.get_sent_messages(mock_ws)

      assert Enum.any?(messages, fn msg ->
               msg["type"] == "conversation.item.create" and
                 get_in(msg, ["item", "type"]) == "function_call_output" and
                 get_in(msg, ["item", "call_id"]) == "call_123"
             end)

      Session.close(session)
    end

    test "handles unknown tool gracefully", %{agent: agent} do
      {:ok, mock_ws} = MockWebSocket.start_link(test_pid: self())

      {:ok, session} =
        Session.start_link(
          agent: agent,
          websocket_pid: mock_ws,
          websocket_module: MockWebSocket
        )

      :ok = Session.subscribe(session, self())

      # Simulate tool call for unknown tool
      tool_call =
        ModelEvents.tool_call(
          name: "unknown_tool",
          call_id: "call_999",
          arguments: "{}",
          id: "item_999"
        )

      send(session, {:model_event, tool_call})

      assert_receive {:session_event,
                      %Events.ToolEndEvent{output: "Error: Unknown tool unknown_tool"}}

      Session.close(session)
    end
  end

  describe "tool execution responsiveness" do
    test "processes model events while a slow tool is running", %{agent: _agent} do
      agent = %{
        name: "SlowToolAgent",
        model: "gpt-4o-realtime-preview",
        instructions: "Use tools",
        tools: [
          %{
            name: "slow_tool",
            on_invoke: fn _args, _ctx ->
              Process.sleep(300)
              "slow-result"
            end
          }
        ]
      }

      {:ok, mock_ws} = MockWebSocket.start_link(test_pid: self())

      {:ok, session} =
        Session.start_link(
          agent: agent,
          websocket_pid: mock_ws,
          websocket_module: MockWebSocket
        )

      :ok = Session.subscribe(session, self())

      tool_call =
        ModelEvents.tool_call(
          name: "slow_tool",
          call_id: "call_slow",
          arguments: "{}",
          id: "item_slow"
        )

      send(session, {:model_event, tool_call})
      assert_receive {:session_event, %Events.ToolStartEvent{}}

      send(session, {:model_event, ModelEvents.error(%{"message" => "while_tool_running"})})

      assert_receive {:session_event,
                      %Events.ErrorEvent{error: %{"message" => "while_tool_running"}}},
                     120

      Session.close(session)
    end
  end

  describe "error handling" do
    test "forwards error events to subscribers", %{agent: agent} do
      {:ok, mock_ws} = MockWebSocket.start_link(test_pid: self())

      {:ok, session} =
        Session.start_link(
          agent: agent,
          websocket_pid: mock_ws,
          websocket_module: MockWebSocket
        )

      :ok = Session.subscribe(session, self())

      # Simulate error event
      send(session, {:model_event, ModelEvents.error(%{"message" => "Something went wrong"})})

      assert_receive {:session_event,
                      %Events.ErrorEvent{error: %{"message" => "Something went wrong"}}}

      Session.close(session)
    end
  end

  describe "subscriber cleanup" do
    test "removes subscriber when process dies", %{agent: agent} do
      {:ok, mock_ws} = MockWebSocket.start_link(test_pid: self())

      {:ok, session} =
        Session.start_link(
          agent: agent,
          websocket_pid: mock_ws,
          websocket_module: MockWebSocket
        )

      # Spawn a subscriber that will die
      {:ok, subscriber} =
        Task.start(fn ->
          receive do
            :die -> :ok
          end
        end)

      :ok = Session.subscribe(session, subscriber)

      # Kill the subscriber
      send(subscriber, :die)
      Process.sleep(50)

      # Session should still work and not crash
      assert Process.alive?(session)
      Session.close(session)
    end

    test "subscribe is idempotent and does not duplicate event delivery", %{agent: agent} do
      {:ok, mock_ws} = MockWebSocket.start_link(test_pid: self())

      {:ok, session} =
        Session.start_link(
          agent: agent,
          websocket_pid: mock_ws,
          websocket_module: MockWebSocket
        )

      :ok = Session.subscribe(session, self())
      :ok = Session.subscribe(session, self())

      send(session, {:model_event, ModelEvents.connection_status(:connected)})

      assert_receive {:session_event, %Events.AgentStartEvent{}}
      refute_receive {:session_event, %Events.AgentStartEvent{}}, 50

      Session.close(session)
    end

    test "unsubscribe is idempotent and fully removes subscriber", %{agent: agent} do
      {:ok, mock_ws} = MockWebSocket.start_link(test_pid: self())

      {:ok, session} =
        Session.start_link(
          agent: agent,
          websocket_pid: mock_ws,
          websocket_module: MockWebSocket
        )

      :ok = Session.subscribe(session, self())
      :ok = Session.subscribe(session, self())
      :ok = Session.unsubscribe(session, self())

      send(session, {:model_event, ModelEvents.connection_status(:connected)})
      refute_receive {:session_event, _}, 50

      Session.close(session)
    end
  end

  describe "websocket lifecycle" do
    test "traps exits and handles websocket exits without crashing", %{agent: agent} do
      {:ok, mock_ws} = MockWebSocket.start_link(test_pid: self())

      {:ok, session} =
        Session.start_link(
          agent: agent,
          websocket_pid: mock_ws,
          websocket_module: MockWebSocket
        )

      :ok = Session.subscribe(session, self())
      assert {:trap_exit, true} = Process.info(session, :trap_exit)

      send(session, {:EXIT, mock_ws, :ws_closed})

      assert_receive {:session_event,
                      %Events.ErrorEvent{
                        error: %{"type" => "websocket_exit", "reason" => "ws_closed"}
                      }}

      assert Process.alive?(session)
      assert :sys.get_state(session).websocket_pid == nil

      Session.close(session)
    end
  end

  describe "dynamic instructions" do
    test "resolves function-based instructions", %{agent: _agent} do
      agent = %{
        name: "DynamicAgent",
        model: "gpt-4o-realtime-preview",
        instructions: fn ctx -> "Hello #{ctx[:user_name] || "User"}!" end,
        tools: []
      }

      {:ok, mock_ws} = MockWebSocket.start_link(test_pid: self())

      {:ok, session} =
        Session.start_link(
          agent: agent,
          websocket_pid: mock_ws,
          websocket_module: MockWebSocket,
          context: %{user_name: "Alice"}
        )

      :ok = Session.subscribe(session, self())

      # Trigger connection which sends initial config
      send(session, {:model_event, ModelEvents.connection_status(:connected)})

      assert_receive {:session_event, %Events.AgentStartEvent{}}

      messages = MockWebSocket.get_sent_messages(mock_ws)

      assert Enum.any?(messages, fn msg ->
               msg["type"] == "session.update" and
                 get_in(msg, ["session", "instructions"]) == "Hello Alice!"
             end)

      Session.close(session)
    end
  end
end
