defmodule Codex.Voice.Models.OpenAITTSTest do
  use ExUnit.Case, async: true

  alias Codex.Voice.Config.TTSSettings
  alias Codex.Voice.Models.OpenAITTS

  describe "new/2" do
    test "creates with default model" do
      model = OpenAITTS.new()
      assert model.model == "gpt-4o-mini-tts"
    end

    test "creates with custom model" do
      model = OpenAITTS.new("tts-1")
      assert model.model == "tts-1"
    end

    test "creates with custom options" do
      model = OpenAITTS.new("tts-1-hd", api_key: "sk-test", base_url: "https://custom.api.com")
      assert model.model == "tts-1-hd"
      assert model.api_key == "sk-test"
      assert model.base_url == "https://custom.api.com"
    end

    test "uses default base URL" do
      model = OpenAITTS.new()
      assert model.base_url == "https://api.openai.com/v1"
    end
  end

  describe "model_name/0" do
    test "returns default model name" do
      assert OpenAITTS.model_name() == "gpt-4o-mini-tts"
    end
  end

  describe "struct" do
    test "has expected fields" do
      model = %OpenAITTS{}
      assert Map.has_key?(model, :model)
      assert Map.has_key?(model, :client)
      assert Map.has_key?(model, :api_key)
      assert Map.has_key?(model, :base_url)
    end
  end

  describe "TTSSettings integration" do
    test "works with default TTSSettings" do
      model = OpenAITTS.new()
      settings = TTSSettings.new()

      assert model.model == "gpt-4o-mini-tts"
      assert settings.voice == nil
      assert settings.speed == nil
    end

    test "works with custom TTSSettings" do
      model = OpenAITTS.new()
      settings = TTSSettings.new(voice: :nova, speed: 1.2)

      assert model.model == "gpt-4o-mini-tts"
      assert settings.voice == :nova
      assert settings.speed == 1.2
    end

    test "supports all voice options" do
      voices = [:alloy, :ash, :coral, :echo, :fable, :onyx, :nova, :sage, :shimmer]

      for voice <- voices do
        settings = TTSSettings.new(voice: voice)
        assert settings.voice == voice
      end
    end
  end

  describe "run/3 (integration)" do
    @describetag :integration

    @tag :skip
    test "generates audio stream" do
      # This test requires a real API key and would make actual API calls
      # Uncomment and set OPENAI_API_KEY to run
      #
      # model = OpenAITTS.new()
      # settings = TTSSettings.new(voice: :nova)
      #
      # audio_stream = OpenAITTS.run(model, "Hello, world!", settings)
      # chunks = Enum.take(audio_stream, 5)
      #
      # assert length(chunks) > 0
      # assert Enum.all?(chunks, &is_binary/1)
    end
  end
end
