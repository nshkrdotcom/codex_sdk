defmodule Codex.Realtime.EventsTest do
  use ExUnit.Case, async: true

  alias Codex.Realtime.Events
  alias Codex.Realtime.Items

  describe "AgentStartEvent" do
    test "creates agent start event" do
      agent = %{name: "TestAgent"}
      context = %{}
      event = Events.agent_start(agent, context)
      assert event.type == :agent_start
      assert event.agent.name == "TestAgent"
      assert event.info.context == %{}
    end
  end

  describe "AgentEndEvent" do
    test "creates agent end event" do
      agent = %{name: "TestAgent"}
      context = %{}
      event = Events.agent_end(agent, context)
      assert event.type == :agent_end
      assert event.agent.name == "TestAgent"
    end
  end

  describe "HandoffEvent" do
    test "creates handoff event" do
      from_agent = %{name: "Agent1"}
      to_agent = %{name: "Agent2"}
      context = %{}
      event = Events.handoff(from_agent, to_agent, context)
      assert event.type == :handoff
      assert event.from_agent.name == "Agent1"
      assert event.to_agent.name == "Agent2"
    end
  end

  describe "ToolStartEvent" do
    test "creates tool start event" do
      agent = %{name: "Agent"}
      tool = %{name: "get_weather"}
      event = Events.tool_start(agent, tool, ~s({"location": "NYC"}), %{})
      assert event.type == :tool_start
      assert event.arguments == ~s({"location": "NYC"})
      assert event.agent.name == "Agent"
      assert event.tool.name == "get_weather"
    end
  end

  describe "ToolEndEvent" do
    test "creates tool end event" do
      agent = %{name: "Agent"}
      tool = %{name: "get_weather"}
      event = Events.tool_end(agent, tool, "{}", "Sunny, 72F", %{})
      assert event.type == :tool_end
      assert event.output == "Sunny, 72F"
      assert event.arguments == "{}"
    end
  end

  describe "AudioEvent" do
    test "creates audio event" do
      model_audio = %{
        data: <<1, 2, 3>>,
        response_id: "resp_123",
        item_id: "item_456",
        content_index: 0
      }

      event = Events.audio(model_audio, "item_456", 0, %{})
      assert event.type == :audio
      assert event.audio.data == <<1, 2, 3>>
      assert event.item_id == "item_456"
      assert event.content_index == 0
    end
  end

  describe "AudioEndEvent" do
    test "creates audio end event" do
      event = Events.audio_end("item_123", 0, %{})
      assert event.type == :audio_end
      assert event.item_id == "item_123"
      assert event.content_index == 0
    end
  end

  describe "AudioInterruptedEvent" do
    test "creates audio interrupted event" do
      event = Events.audio_interrupted("item_123", 0, %{})
      assert event.type == :audio_interrupted
      assert event.item_id == "item_123"
      assert event.content_index == 0
    end
  end

  describe "ErrorEvent" do
    test "creates error event" do
      event = Events.error(%{message: "Something went wrong"}, %{})
      assert event.type == :error
      assert event.error.message == "Something went wrong"
    end
  end

  describe "HistoryUpdatedEvent" do
    test "creates history updated event" do
      history = [Items.user_message("item_1", [])]
      event = Events.history_updated(history, %{})
      assert event.type == :history_updated
      assert length(event.history) == 1
    end
  end

  describe "HistoryAddedEvent" do
    test "creates history added event" do
      item = Items.user_message("item_1", [])
      event = Events.history_added(item, %{})
      assert event.type == :history_added
      assert event.item.item_id == "item_1"
    end
  end

  describe "GuardrailTrippedEvent" do
    test "creates guardrail tripped event" do
      results = [%{guardrail: :content_filter, tripped: true}]
      event = Events.guardrail_tripped(results, "Bad content", %{})
      assert event.type == :guardrail_tripped
      assert event.message == "Bad content"
      assert event.guardrail_results == results
    end
  end

  describe "InputAudioTimeoutTriggeredEvent" do
    test "creates input audio timeout triggered event" do
      event = Events.input_audio_timeout_triggered(%{})
      assert event.type == :input_audio_timeout_triggered
      assert event.info.context == %{}
    end
  end

  describe "RawModelEvent" do
    test "wraps model event" do
      model_event = %{type: :audio, data: <<>>}
      event = Events.raw_model_event(model_event, %{})
      assert event.type == :raw_model_event
      assert event.data == model_event
    end
  end

  describe "EventInfo" do
    test "contains context" do
      info = %Events.EventInfo{context: %{session_id: "sess_123"}}
      assert info.context.session_id == "sess_123"
    end
  end
end
