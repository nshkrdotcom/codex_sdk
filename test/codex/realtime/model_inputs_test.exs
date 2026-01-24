defmodule Codex.Realtime.ModelInputsTest do
  use ExUnit.Case, async: true

  alias Codex.Realtime.Config.SessionModelSettings
  alias Codex.Realtime.ModelEvents
  alias Codex.Realtime.ModelInputs

  describe "SendRawMessage" do
    test "creates send raw message" do
      msg = %{"type" => "session.update", "session" => %{}}
      event = ModelInputs.send_raw_message(msg)
      assert event.message == msg
    end

    test "serializes to JSON" do
      msg = %{"type" => "session.update", "session" => %{}}
      event = ModelInputs.send_raw_message(msg)
      json = ModelInputs.to_json(event)
      assert json == msg
    end
  end

  describe "SendUserInput" do
    test "creates send user input with string" do
      event = ModelInputs.send_user_input("Hello")
      assert event.user_input == "Hello"
    end

    test "creates send user input with message map" do
      msg = %{"type" => "message", "role" => "user", "content" => []}
      event = ModelInputs.send_user_input(msg)
      assert event.user_input == msg
    end

    test "serializes string input to JSON" do
      event = ModelInputs.send_user_input("Hello")
      json = ModelInputs.to_json(event)

      assert json == %{
               "type" => "conversation.item.create",
               "item" => %{
                 "type" => "message",
                 "role" => "user",
                 "content" => [%{"type" => "input_text", "text" => "Hello"}]
               }
             }
    end

    test "serializes message input to JSON" do
      msg = %{"type" => "message", "role" => "user", "content" => []}
      event = ModelInputs.send_user_input(msg)
      json = ModelInputs.to_json(event)

      assert json == %{
               "type" => "conversation.item.create",
               "item" => msg
             }
    end
  end

  describe "SendAudio" do
    test "creates send audio without commit" do
      event = ModelInputs.send_audio(<<1, 2, 3>>)
      assert event.audio == <<1, 2, 3>>
      assert event.commit == false
    end

    test "creates send audio with commit" do
      event = ModelInputs.send_audio(<<1, 2, 3>>, true)
      assert event.audio == <<1, 2, 3>>
      assert event.commit == true
    end

    test "serializes audio without commit to JSON" do
      event = ModelInputs.send_audio(<<1, 2, 3>>)
      json = ModelInputs.to_json(event)

      assert json == %{
               "type" => "input_audio_buffer.append",
               "audio" => Base.encode64(<<1, 2, 3>>)
             }
    end

    test "serializes audio with commit to JSON" do
      event = ModelInputs.send_audio(<<1, 2, 3>>, true)
      json = ModelInputs.to_json(event)

      assert json == [
               %{
                 "type" => "input_audio_buffer.append",
                 "audio" => Base.encode64(<<1, 2, 3>>)
               },
               %{"type" => "input_audio_buffer.commit"}
             ]
    end
  end

  describe "SendToolOutput" do
    test "creates send tool output with start response" do
      tool_call =
        ModelEvents.tool_call(
          name: "get_weather",
          call_id: "call_123",
          arguments: "{}"
        )

      event = ModelInputs.send_tool_output(tool_call, "Sunny")
      assert event.tool_call == tool_call
      assert event.output == "Sunny"
      assert event.start_response == true
    end

    test "creates send tool output without start response" do
      tool_call =
        ModelEvents.tool_call(
          name: "get_weather",
          call_id: "call_123",
          arguments: "{}"
        )

      event = ModelInputs.send_tool_output(tool_call, "Sunny", false)
      assert event.start_response == false
    end

    test "serializes tool output with start response to JSON" do
      tool_call =
        ModelEvents.tool_call(
          name: "get_weather",
          call_id: "call_123",
          arguments: "{}"
        )

      event = ModelInputs.send_tool_output(tool_call, "Sunny")
      json = ModelInputs.to_json(event)

      assert json == [
               %{
                 "type" => "conversation.item.create",
                 "item" => %{
                   "type" => "function_call_output",
                   "call_id" => "call_123",
                   "output" => "Sunny"
                 }
               },
               %{"type" => "response.create"}
             ]
    end

    test "serializes tool output without start response to JSON" do
      tool_call =
        ModelEvents.tool_call(
          name: "get_weather",
          call_id: "call_123",
          arguments: "{}"
        )

      event = ModelInputs.send_tool_output(tool_call, "Sunny", false)
      json = ModelInputs.to_json(event)

      assert json == [
               %{
                 "type" => "conversation.item.create",
                 "item" => %{
                   "type" => "function_call_output",
                   "call_id" => "call_123",
                   "output" => "Sunny"
                 }
               }
             ]
    end
  end

  describe "SendInterrupt" do
    test "creates send interrupt without force" do
      event = ModelInputs.send_interrupt()
      assert event.force_response_cancel == false
    end

    test "creates send interrupt with force" do
      event = ModelInputs.send_interrupt(true)
      assert event.force_response_cancel == true
    end

    test "serializes interrupt to JSON" do
      event = ModelInputs.send_interrupt()
      json = ModelInputs.to_json(event)
      assert json == %{"type" => "response.cancel"}
    end
  end

  describe "SendSessionUpdate" do
    test "creates send session update" do
      settings = %SessionModelSettings{voice: "alloy"}
      event = ModelInputs.send_session_update(settings)
      assert event.session_settings == settings
    end

    test "serializes session update to JSON" do
      settings = %SessionModelSettings{voice: "alloy", modalities: [:text, :audio]}
      event = ModelInputs.send_session_update(settings)
      json = ModelInputs.to_json(event)

      assert json == %{
               "type" => "session.update",
               "session" => %{"voice" => "alloy", "modalities" => ["text", "audio"]}
             }
    end
  end
end
