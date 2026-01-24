defmodule Codex.Voice.EventsTest do
  use ExUnit.Case, async: true

  alias Codex.Voice.Events

  describe "VoiceStreamEventAudio" do
    test "creates audio event" do
      event = Events.audio(<<1, 2, 3>>)
      assert event.type == :voice_stream_event_audio
      assert event.data == <<1, 2, 3>>
    end

    test "creates audio event with nil data" do
      event = Events.audio(nil)
      assert event.type == :voice_stream_event_audio
      assert event.data == nil
    end
  end

  describe "VoiceStreamEventLifecycle" do
    test "creates turn_started event" do
      event = Events.lifecycle(:turn_started)
      assert event.type == :voice_stream_event_lifecycle
      assert event.event == :turn_started
    end

    test "creates turn_ended event" do
      event = Events.lifecycle(:turn_ended)
      assert event.type == :voice_stream_event_lifecycle
      assert event.event == :turn_ended
    end

    test "creates session_ended event" do
      event = Events.lifecycle(:session_ended)
      assert event.type == :voice_stream_event_lifecycle
      assert event.event == :session_ended
    end
  end

  describe "VoiceStreamEventError" do
    test "creates error event" do
      error = %RuntimeError{message: "Something went wrong"}
      event = Events.error(error)
      assert event.type == :voice_stream_event_error
      assert event.error == error
    end

    test "creates error event with ArgumentError" do
      error = %ArgumentError{message: "Invalid argument"}
      event = Events.error(error)
      assert event.type == :voice_stream_event_error
      assert event.error == error
    end
  end

  describe "type union" do
    test "different event types have distinct type fields" do
      audio = Events.audio(<<1>>)
      lifecycle = Events.lifecycle(:turn_ended)
      error = Events.error(%RuntimeError{message: "test"})

      # Using a list of types to verify they are all distinct
      types = [audio.type, lifecycle.type, error.type]
      assert length(Enum.uniq(types)) == 3
    end
  end
end
