defmodule Codex.Voice.Models.OpenAISTTTest do
  use ExUnit.Case, async: true

  alias Codex.Voice.Config.STTSettings
  alias Codex.Voice.Input.StreamedAudioInput
  alias Codex.Voice.Models.OpenAISTT
  alias Codex.Voice.Models.OpenAISTTSession

  describe "new/2" do
    test "creates with default model" do
      model = OpenAISTT.new()
      assert model.model == "gpt-4o-transcribe"
    end

    test "creates with custom model" do
      model = OpenAISTT.new("whisper-1")
      assert model.model == "whisper-1"
    end

    test "creates with custom options" do
      model = OpenAISTT.new("whisper-1", api_key: "sk-test", base_url: "https://custom.api.com")
      assert model.model == "whisper-1"
      assert model.api_key == "sk-test"
      assert model.base_url == "https://custom.api.com"
    end

    test "uses default base URL" do
      model = OpenAISTT.new()
      assert model.base_url == "https://api.openai.com/v1"
    end
  end

  describe "model_name/0" do
    test "returns default model name" do
      assert OpenAISTT.model_name() == "gpt-4o-transcribe"
    end
  end

  describe "struct" do
    test "has expected fields" do
      model = %OpenAISTT{}
      assert Map.has_key?(model, :model)
      assert Map.has_key?(model, :client)
      assert Map.has_key?(model, :api_key)
      assert Map.has_key?(model, :base_url)
    end
  end

  describe "OpenAISTTSession" do
    test "starts with required options" do
      input = StreamedAudioInput.new()
      settings = STTSettings.new()

      assert {:ok, pid} =
               OpenAISTTSession.start_link(
                 input: input,
                 settings: settings
               )

      assert is_pid(pid)
      OpenAISTTSession.close(pid)
    end

    test "starts with all options" do
      input = StreamedAudioInput.new()
      settings = STTSettings.new(language: "en", temperature: 0.0)

      assert {:ok, pid} =
               OpenAISTTSession.start_link(
                 input: input,
                 settings: settings,
                 model: "whisper-1",
                 api_key: "sk-test",
                 trace_include_sensitive_data: false,
                 trace_include_sensitive_audio_data: false
               )

      assert is_pid(pid)
      OpenAISTTSession.close(pid)
    end

    test "default_turn_detection returns semantic_vad" do
      assert OpenAISTTSession.default_turn_detection() == %{"type" => "semantic_vad"}
    end

    test "close/1 stops the session" do
      input = StreamedAudioInput.new()
      settings = STTSettings.new()

      {:ok, pid} =
        OpenAISTTSession.start_link(
          input: input,
          settings: settings
        )

      assert Process.alive?(pid)
      assert :ok = OpenAISTTSession.close(pid)
      refute Process.alive?(pid)
    end
  end

  describe "transcribe/5 (integration)" do
    @describetag :integration

    @tag :skip
    test "transcribes audio input" do
      # This test requires a real API key and would make actual API calls
      # Uncomment and set OPENAI_API_KEY to run
      #
      # model = OpenAISTT.new()
      # audio_data = File.read!("test/fixtures/sample.wav")
      # input = AudioInput.new(audio_data)
      # settings = STTSettings.new(language: "en")
      #
      # {:ok, text} = OpenAISTT.transcribe(model, input, settings, true, false)
      # assert is_binary(text)
    end
  end
end
