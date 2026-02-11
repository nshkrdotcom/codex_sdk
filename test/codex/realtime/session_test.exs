defmodule Codex.Realtime.SessionTest do
  use ExUnit.Case, async: true

  alias Codex.Realtime
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
    test "adds subscriber to receive turn start events", %{agent: agent} do
      {:ok, mock_ws} = MockWebSocket.start_link(test_pid: self())

      {:ok, session} =
        Session.start_link(
          agent: agent,
          websocket_pid: mock_ws,
          websocket_module: MockWebSocket
        )

      :ok = Session.subscribe(session, self())

      # Simulate turn started event
      send(session, {:model_event, ModelEvents.turn_started()})

      assert_receive {:session_event, %Events.AgentStartEvent{}}
      Session.close(session)
    end

    test "emits agent start only after turn starts", %{agent: agent} do
      {:ok, mock_ws} = MockWebSocket.start_link(test_pid: self())

      {:ok, session} =
        Session.start_link(
          agent: agent,
          websocket_pid: mock_ws,
          websocket_module: MockWebSocket
        )

      :ok = Session.subscribe(session, self())

      send(session, {:model_event, ModelEvents.connection_status(:connected)})
      refute_receive {:session_event, %Events.AgentStartEvent{}}, 50

      send(session, {:model_event, ModelEvents.turn_started()})
      assert_receive {:session_event, %Events.AgentStartEvent{}}
      refute_receive {:session_event, %Events.AgentStartEvent{}}, 50

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

  describe "terminate cleanup" do
    test "close/1 terminates pending tool tasks", %{agent: _agent} do
      parent = self()

      agent = %{
        name: "CleanupAgent",
        model: "gpt-4o-realtime-preview",
        instructions: "Use tools",
        tools: [
          %{
            name: "blocking_tool",
            on_invoke: fn _args, _ctx ->
              send(parent, :blocking_tool_started)

              receive do
                :release_tool -> "released"
              end
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

      tool_call =
        ModelEvents.tool_call(
          name: "blocking_tool",
          call_id: "call_cleanup",
          arguments: "{}",
          id: "item_cleanup"
        )

      send(session, {:model_event, tool_call})
      assert_receive :blocking_tool_started

      pending_pid = wait_for_pending_tool_pid(session)

      on_exit(fn ->
        if is_pid(pending_pid) and Process.alive?(pending_pid) do
          send(pending_pid, :release_tool)
        end
      end)

      assert Process.alive?(pending_pid)
      Session.close(session)
      refute wait_until_alive(pending_pid, 300)
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

      send(session, {:model_event, ModelEvents.turn_started()})

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
      refute_receive {:session_event, %Events.AgentStartEvent{}}, 50

      send(session, {:model_event, ModelEvents.turn_started()})

      assert_receive {:session_event, %Events.AgentStartEvent{}}

      messages = MockWebSocket.get_sent_messages(mock_ws)

      assert Enum.any?(messages, fn msg ->
               msg["type"] == "session.update" and
                 get_in(msg, ["session", "instructions"]) == "Hello Alice!"
             end)

      Session.close(session)
    end
  end

  describe "response.done failure handling" do
    test "emits an error event when response.done reports failed status", %{agent: agent} do
      {:ok, mock_ws} = MockWebSocket.start_link(test_pid: self())

      {:ok, session} =
        Session.start_link(
          agent: agent,
          websocket_pid: mock_ws,
          websocket_module: MockWebSocket
        )

      :ok = Session.subscribe(session, self())

      send(session, {
        :websocket_event,
        %{
          "type" => "response.done",
          "response" => %{
            "id" => "resp_failed_1",
            "status" => "failed",
            "status_details" => %{
              "error" => %{
                "code" => "insufficient_quota",
                "message" => "You exceeded your current quota.",
                "type" => "insufficient_quota"
              }
            }
          }
        }
      })

      assert_receive {:session_event,
                      %Events.ErrorEvent{
                        error: %{
                          "code" => "insufficient_quota",
                          "source_event" => "response.done",
                          "response_id" => "resp_failed_1"
                        }
                      }}

      assert_receive {:session_event, %Events.AgentEndEvent{agent: %{name: "TestAgent"}}}

      Session.close(session)
    end

    test "emits an error event when raw response.done server event reports failed status", %{
      agent: agent
    } do
      {:ok, mock_ws} = MockWebSocket.start_link(test_pid: self())

      {:ok, session} =
        Session.start_link(
          agent: agent,
          websocket_pid: mock_ws,
          websocket_module: MockWebSocket
        )

      :ok = Session.subscribe(session, self())

      send(
        session,
        {:model_event,
         ModelEvents.raw_server_event(%{
           "type" => "response.done",
           "response" => %{
             "id" => "resp_failed_2",
             "status" => "failed",
             "status_details" => %{
               "error" => %{
                 "code" => "model_not_found",
                 "message" => "Model not available",
                 "type" => "invalid_request_error"
               }
             }
           }
         })}
      )

      assert_receive {:session_event,
                      %Events.ErrorEvent{
                        error: %{
                          "code" => "model_not_found",
                          "source_event" => "response.done",
                          "response_id" => "resp_failed_2"
                        }
                      }}

      assert_receive {:session_event, %Events.RawModelEvent{}}

      Session.close(session)
    end
  end

  describe "handoffs" do
    test "includes handoff tools in initial session.update payload", %{agent: _agent} do
      tech_support =
        Realtime.agent(
          name: "TechSupport",
          instructions: "Handle technical support issues."
        )

      billing =
        Realtime.agent(
          name: "BillingAgent",
          instructions: "Handle billing issues."
        )

      greeter =
        Realtime.agent(
          name: "Greeter",
          instructions: "Route users to specialists.",
          handoffs: [tech_support, billing]
        )

      {:ok, mock_ws} = MockWebSocket.start_link(test_pid: self())

      {:ok, session} =
        Session.start_link(
          agent: greeter,
          websocket_pid: mock_ws,
          websocket_module: MockWebSocket
        )

      :ok = Session.subscribe(session, self())
      send(session, {:model_event, ModelEvents.connection_status(:connected)})
      send(session, {:model_event, ModelEvents.turn_started()})

      assert_receive {:session_event, %Events.AgentStartEvent{}}

      tools =
        mock_ws
        |> MockWebSocket.get_sent_messages()
        |> Enum.find(&(&1["type"] == "session.update"))
        |> get_in(["session", "tools"])

      tool_names = Enum.map(tools, &Map.get(&1, "name"))

      assert "transfer_to_techsupport" in tool_names
      assert "transfer_to_billingagent" in tool_names

      Session.close(session)
    end

    test "handoff tool call switches active agent and sends tool output", %{agent: _agent} do
      tech_support =
        Realtime.agent(
          name: "TechSupport",
          instructions: "You are now technical support."
        )

      greeter =
        Realtime.agent(
          name: "Greeter",
          instructions: "You route requests.",
          handoffs: [tech_support]
        )

      {:ok, mock_ws} = MockWebSocket.start_link(test_pid: self())

      {:ok, session} =
        Session.start_link(
          agent: greeter,
          websocket_pid: mock_ws,
          websocket_module: MockWebSocket
        )

      :ok = Session.subscribe(session, self())
      send(session, {:model_event, ModelEvents.connection_status(:connected)})
      send(session, {:model_event, ModelEvents.turn_started()})
      assert_receive {:session_event, %Events.AgentStartEvent{}}
      :ok = MockWebSocket.clear_sent_messages(mock_ws)

      handoff_call =
        ModelEvents.tool_call(
          name: "transfer_to_techsupport",
          call_id: "call_handoff_1",
          arguments: "{}",
          id: "item_handoff_1"
        )

      send(session, {:model_event, handoff_call})

      assert_receive {:session_event, %Events.ToolStartEvent{}}

      assert_receive {:session_event,
                      %Events.HandoffEvent{from_agent: from_agent, to_agent: to_agent}},
                     200

      assert from_agent.name == "Greeter"
      assert to_agent.name == "TechSupport"

      assert_receive {:session_event, %Events.ToolEndEvent{output: output}}, 200
      assert output =~ "TechSupport"

      assert Session.current_agent(session).name == "TechSupport"

      messages = MockWebSocket.get_sent_messages(mock_ws)

      assert Enum.any?(messages, fn msg ->
               msg["type"] == "session.update" and
                 get_in(msg, ["session", "instructions"]) == "You are now technical support."
             end)

      assert Enum.any?(messages, fn msg ->
               msg["type"] == "conversation.item.create" and
                 get_in(msg, ["item", "type"]) == "function_call_output" and
                 get_in(msg, ["item", "call_id"]) == "call_handoff_1"
             end)

      Session.close(session)
    end
  end

  defp wait_for_pending_tool_pid(session) do
    wait_for_value(fn ->
      case :sys.get_state(session).pending_tool_calls |> Map.values() do
        [%{pid: pid}] when is_pid(pid) -> {:ok, pid}
        _ -> :retry
      end
    end)
  end

  defp wait_for_value(fun) do
    started = System.monotonic_time(:millisecond)
    do_wait_for_value(fun, started)
  end

  defp do_wait_for_value(fun, started) do
    case fun.() do
      {:ok, value} ->
        value

      :retry ->
        if System.monotonic_time(:millisecond) - started > 1_000 do
          flunk("timed out waiting for pending tool task")
        else
          Process.sleep(10)
          do_wait_for_value(fun, started)
        end
    end
  end

  defp wait_until_alive(pid, timeout_ms) do
    started = System.monotonic_time(:millisecond)
    do_wait_until_alive(pid, timeout_ms, started)
  end

  defp do_wait_until_alive(pid, timeout_ms, started) do
    if Process.alive?(pid) do
      if System.monotonic_time(:millisecond) - started > timeout_ms do
        true
      else
        Process.sleep(10)
        do_wait_until_alive(pid, timeout_ms, started)
      end
    else
      false
    end
  end
end
