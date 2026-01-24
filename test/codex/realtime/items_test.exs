defmodule Codex.Realtime.ItemsTest do
  use ExUnit.Case, async: true

  alias Codex.Realtime.Items

  describe "InputText" do
    test "creates input text content" do
      content = Items.input_text("Hello world")
      assert content.type == :input_text
      assert content.text == "Hello world"
    end

    test "serializes to JSON" do
      content = Items.input_text("Hello")
      json = Items.to_json(content)
      assert json == %{"type" => "input_text", "text" => "Hello"}
    end
  end

  describe "InputAudio" do
    test "creates input audio content" do
      content = Items.input_audio("base64data", "transcription")
      assert content.type == :input_audio
      assert content.audio == "base64data"
      assert content.transcript == "transcription"
    end
  end

  describe "InputImage" do
    test "creates input image content" do
      content = Items.input_image("https://example.com/image.png", "high")
      assert content.type == :input_image
      assert content.image_url == "https://example.com/image.png"
      assert content.detail == "high"
    end
  end

  describe "AssistantText" do
    test "creates assistant text content" do
      content = Items.assistant_text("Hello!")
      assert content.type == :text
      assert content.text == "Hello!"
    end
  end

  describe "AssistantAudio" do
    test "creates assistant audio content" do
      content = Items.assistant_audio("base64audio", "Hi there")
      assert content.type == :audio
      assert content.audio == "base64audio"
      assert content.transcript == "Hi there"
    end
  end

  describe "SystemMessageItem" do
    test "creates system message" do
      msg = Items.system_message("item_123", [Items.input_text("System prompt")])
      assert msg.item_id == "item_123"
      assert msg.type == :message
      assert msg.role == :system
      assert length(msg.content) == 1
    end

    test "serializes to JSON" do
      msg = Items.system_message("item_123", [Items.input_text("System prompt")])
      json = Items.to_json(msg)
      assert json["item_id"] == "item_123"
      assert json["type"] == "message"
      assert json["role"] == "system"
    end
  end

  describe "UserMessageItem" do
    test "creates user message with text" do
      msg = Items.user_message("item_456", [Items.input_text("Hello")])
      assert msg.role == :user
      assert msg.type == :message
    end

    test "creates user message with audio" do
      msg = Items.user_message("item_789", [Items.input_audio("base64", "Hello")])
      assert msg.role == :user
    end
  end

  describe "AssistantMessageItem" do
    test "creates assistant message" do
      msg =
        Items.assistant_message(
          "item_abc",
          [Items.assistant_text("Hi there!")],
          status: :completed
        )

      assert msg.role == :assistant
      assert msg.status == :completed
    end

    test "handles in_progress status" do
      msg = Items.assistant_message("item_def", [], status: :in_progress)
      assert msg.status == :in_progress
    end
  end

  describe "RealtimeToolCallItem" do
    test "creates tool call item" do
      item =
        Items.tool_call_item(
          item_id: "item_tool",
          call_id: "call_123",
          name: "get_weather",
          arguments: ~s({"location": "NYC"}),
          status: :completed
        )

      assert item.type == :function_call
      assert item.name == "get_weather"
      assert item.call_id == "call_123"
    end

    test "includes output when provided" do
      item =
        Items.tool_call_item(
          item_id: "item_tool",
          call_id: "call_123",
          name: "get_weather",
          arguments: "{}",
          status: :completed,
          output: "Sunny, 72F"
        )

      assert item.output == "Sunny, 72F"
    end
  end

  describe "parsing from JSON" do
    test "parses system message" do
      json = %{
        "item_id" => "item_1",
        "type" => "message",
        "role" => "system",
        "content" => [%{"type" => "input_text", "text" => "Be helpful"}]
      }

      {:ok, item} = Items.from_json(json)
      assert item.role == :system
      assert hd(item.content).text == "Be helpful"
    end

    test "parses user message with mixed content" do
      json = %{
        "item_id" => "item_2",
        "type" => "message",
        "role" => "user",
        "content" => [
          %{"type" => "input_text", "text" => "What's this?"},
          %{"type" => "input_image", "image_url" => "https://example.com/img.png"}
        ]
      }

      {:ok, item} = Items.from_json(json)
      assert item.role == :user
      assert length(item.content) == 2
    end

    test "parses tool call item" do
      json = %{
        "item_id" => "item_3",
        "type" => "function_call",
        "call_id" => "call_xyz",
        "name" => "search",
        "arguments" => "{}",
        "status" => "completed"
      }

      {:ok, item} = Items.from_json(json)
      assert item.type == :function_call
      assert item.name == "search"
    end

    test "returns error for invalid type" do
      json = %{"type" => "unknown"}
      assert {:error, _} = Items.from_json(json)
    end
  end
end
