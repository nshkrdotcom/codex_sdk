defmodule Codex.Realtime.ModelEventsTest do
  use ExUnit.Case, async: true

  alias Codex.Realtime.Items
  alias Codex.Realtime.ModelEvents

  describe "ConnectionStatusEvent" do
    test "creates connecting status" do
      event = ModelEvents.connection_status(:connecting)
      assert event.type == :connection_status
      assert event.status == :connecting
    end

    test "creates connected status" do
      event = ModelEvents.connection_status(:connected)
      assert event.status == :connected
    end

    test "creates disconnected status" do
      event = ModelEvents.connection_status(:disconnected)
      assert event.status == :disconnected
    end
  end

  describe "ErrorEvent" do
    test "creates error event" do
      event = ModelEvents.error(%{code: "invalid_request", message: "Bad input"})
      assert event.type == :error
      assert event.error.code == "invalid_request"
    end
  end

  describe "ToolCallEvent" do
    test "creates tool call event" do
      event =
        ModelEvents.tool_call(
          name: "get_weather",
          call_id: "call_123",
          arguments: ~s({"location": "NYC"})
        )

      assert event.type == :function_call
      assert event.name == "get_weather"
      assert event.call_id == "call_123"
    end

    test "includes optional item_id" do
      event =
        ModelEvents.tool_call(
          name: "search",
          call_id: "call_456",
          arguments: "{}",
          id: "item_789"
        )

      assert event.id == "item_789"
    end

    test "includes optional previous_item_id" do
      event =
        ModelEvents.tool_call(
          name: "search",
          call_id: "call_456",
          arguments: "{}",
          previous_item_id: "prev_123"
        )

      assert event.previous_item_id == "prev_123"
    end
  end

  describe "AudioEvent" do
    test "creates audio event" do
      event =
        ModelEvents.audio(
          data: <<1, 2, 3, 4>>,
          response_id: "resp_123",
          item_id: "item_456",
          content_index: 0
        )

      assert event.type == :audio
      assert event.data == <<1, 2, 3, 4>>
      assert event.item_id == "item_456"
      assert event.response_id == "resp_123"
      assert event.content_index == 0
    end
  end

  describe "AudioDoneEvent" do
    test "creates audio done event" do
      event = ModelEvents.audio_done(item_id: "item_123", content_index: 0)
      assert event.type == :audio_done
      assert event.item_id == "item_123"
      assert event.content_index == 0
    end
  end

  describe "AudioInterruptedEvent" do
    test "creates audio interrupted event" do
      event = ModelEvents.audio_interrupted(item_id: "item_123", content_index: 0)
      assert event.type == :audio_interrupted
      assert event.item_id == "item_123"
      assert event.content_index == 0
    end
  end

  describe "TranscriptDeltaEvent" do
    test "creates transcript delta event" do
      event =
        ModelEvents.transcript_delta(
          item_id: "item_123",
          delta: "Hello ",
          response_id: "resp_456"
        )

      assert event.type == :transcript_delta
      assert event.delta == "Hello "
      assert event.item_id == "item_123"
      assert event.response_id == "resp_456"
    end
  end

  describe "ItemUpdatedEvent" do
    test "creates item updated event" do
      item = Items.user_message("item_1", [])
      event = ModelEvents.item_updated(item)
      assert event.type == :item_updated
      assert event.item.item_id == "item_1"
    end
  end

  describe "ItemDeletedEvent" do
    test "creates item deleted event" do
      event = ModelEvents.item_deleted("item_123")
      assert event.type == :item_deleted
      assert event.item_id == "item_123"
    end
  end

  describe "TurnStartedEvent" do
    test "creates turn started event" do
      event = ModelEvents.turn_started()
      assert event.type == :turn_started
    end
  end

  describe "TurnEndedEvent" do
    test "creates turn ended event" do
      event = ModelEvents.turn_ended()
      assert event.type == :turn_ended
    end
  end

  describe "InputAudioTranscriptionCompletedEvent" do
    test "creates transcription completed event" do
      event =
        ModelEvents.input_audio_transcription_completed(
          item_id: "item_123",
          transcript: "Hello world"
        )

      assert event.type == :input_audio_transcription_completed
      assert event.transcript == "Hello world"
      assert event.item_id == "item_123"
    end
  end

  describe "OtherEvent" do
    test "creates other event" do
      event = ModelEvents.other(%{"type" => "unknown.event", "data" => "something"})
      assert event.type == :other
      assert event.data == %{"type" => "unknown.event", "data" => "something"}
    end
  end

  describe "ExceptionEvent" do
    test "creates exception event" do
      exception = RuntimeError.exception("boom")
      event = ModelEvents.exception(exception)
      assert event.type == :exception
      assert event.exception == exception
      assert event.context == nil
    end

    test "creates exception event with context" do
      exception = RuntimeError.exception("boom")
      event = ModelEvents.exception(exception, "during parsing")
      assert event.type == :exception
      assert event.context == "during parsing"
    end
  end

  describe "RawServerEvent" do
    test "creates raw server event" do
      event = ModelEvents.raw_server_event(%{"type" => "session.created", "session" => %{}})
      assert event.type == :raw_server_event
      assert event.data == %{"type" => "session.created", "session" => %{}}
    end
  end

  describe "parsing from JSON" do
    test "parses error event" do
      json = %{
        "type" => "error",
        "error" => %{"code" => "rate_limit", "message" => "Too fast"}
      }

      {:ok, event} = ModelEvents.from_json(json)
      assert event.type == :error
      assert event.error == %{"code" => "rate_limit", "message" => "Too fast"}
    end

    test "parses audio delta event" do
      json = %{
        "type" => "response.audio.delta",
        "response_id" => "resp_123",
        "item_id" => "item_456",
        "content_index" => 0,
        "delta" => Base.encode64(<<1, 2, 3>>)
      }

      {:ok, event} = ModelEvents.from_json(json)
      assert event.type == :audio
      assert event.data == <<1, 2, 3>>
      assert event.item_id == "item_456"
      assert event.response_id == "resp_123"
    end

    test "parses audio delta event with output_index fallback" do
      json = %{
        "type" => "response.audio.delta",
        "response_id" => "resp_123",
        "item_id" => "item_456",
        "output_index" => 1,
        "delta" => Base.encode64(<<1, 2, 3>>)
      }

      {:ok, event} = ModelEvents.from_json(json)
      assert event.content_index == 1
    end

    test "parses audio done event" do
      json = %{
        "type" => "response.audio.done",
        "item_id" => "item_456",
        "content_index" => 0
      }

      {:ok, event} = ModelEvents.from_json(json)
      assert event.type == :audio_done
      assert event.item_id == "item_456"
    end

    test "parses function call event" do
      json = %{
        "type" => "response.function_call_arguments.done",
        "response_id" => "resp_123",
        "item_id" => "item_456",
        "call_id" => "call_789",
        "name" => "search",
        "arguments" => "{}"
      }

      {:ok, event} = ModelEvents.from_json(json)
      assert event.type == :function_call
      assert event.name == "search"
      assert event.call_id == "call_789"
      assert event.id == "item_456"
    end

    test "parses transcript delta event" do
      json = %{
        "type" => "response.audio_transcript.delta",
        "response_id" => "resp_123",
        "item_id" => "item_456",
        "delta" => "Hello"
      }

      {:ok, event} = ModelEvents.from_json(json)
      assert event.type == :transcript_delta
      assert event.delta == "Hello"
    end

    test "parses conversation item created event" do
      json = %{
        "type" => "conversation.item.created",
        "item" => %{
          "type" => "message",
          "role" => "user",
          "item_id" => "item_123",
          "content" => [%{"type" => "input_text", "text" => "Hello"}]
        }
      }

      {:ok, event} = ModelEvents.from_json(json)
      assert event.type == :item_updated
      assert event.item.item_id == "item_123"
    end

    test "parses conversation item deleted event" do
      json = %{
        "type" => "conversation.item.deleted",
        "item_id" => "item_123"
      }

      {:ok, event} = ModelEvents.from_json(json)
      assert event.type == :item_deleted
      assert event.item_id == "item_123"
    end

    test "parses response created event" do
      json = %{"type" => "response.created"}
      {:ok, event} = ModelEvents.from_json(json)
      assert event.type == :turn_started
    end

    test "parses response done event" do
      json = %{"type" => "response.done"}
      {:ok, event} = ModelEvents.from_json(json)
      assert event.type == :turn_ended
    end

    test "parses input audio transcription completed event" do
      json = %{
        "type" => "conversation.item.input_audio_transcription.completed",
        "item_id" => "item_123",
        "transcript" => "Hello world"
      }

      {:ok, event} = ModelEvents.from_json(json)
      assert event.type == :input_audio_transcription_completed
      assert event.transcript == "Hello world"
    end

    test "parses speech started event as turn started" do
      json = %{"type" => "input_audio_buffer.speech_started"}
      {:ok, event} = ModelEvents.from_json(json)
      assert event.type == :turn_started
    end

    test "parses speech stopped event as turn ended" do
      json = %{"type" => "input_audio_buffer.speech_stopped"}
      {:ok, event} = ModelEvents.from_json(json)
      assert event.type == :turn_ended
    end

    test "wraps unknown events as other" do
      json = %{"type" => "unknown.event", "data" => "something"}
      {:ok, event} = ModelEvents.from_json(json)
      assert event.type == :other
      assert event.data == json
    end
  end
end
