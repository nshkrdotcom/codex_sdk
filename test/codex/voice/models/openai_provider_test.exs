defmodule Codex.Voice.Models.OpenAIProviderTest do
  use ExUnit.Case, async: true

  alias Codex.Voice.Models.OpenAIProvider
  alias Codex.Voice.Models.OpenAISTT
  alias Codex.Voice.Models.OpenAITTS

  describe "new/1" do
    test "creates with default options" do
      provider = OpenAIProvider.new()
      assert provider.api_key == nil
      assert provider.base_url == nil
      assert provider.organization == nil
      assert provider.project == nil
    end

    test "creates with custom API key" do
      provider = OpenAIProvider.new(api_key: "sk-test")
      assert provider.api_key == "sk-test"
    end

    test "creates with custom base URL" do
      provider = OpenAIProvider.new(base_url: "https://custom.api.com")
      assert provider.base_url == "https://custom.api.com"
    end

    test "creates with all options" do
      provider =
        OpenAIProvider.new(
          api_key: "sk-test",
          base_url: "https://custom.api.com",
          organization: "org-123",
          project: "proj-456"
        )

      assert provider.api_key == "sk-test"
      assert provider.base_url == "https://custom.api.com"
      assert provider.organization == "org-123"
      assert provider.project == "proj-456"
    end
  end

  describe "get_stt_model/2" do
    test "returns default STT model when name is nil" do
      provider = OpenAIProvider.new()
      model = OpenAIProvider.get_stt_model(provider, nil)

      assert %OpenAISTT{} = model
      assert model.model == "gpt-4o-transcribe"
    end

    test "returns custom STT model when name is provided" do
      provider = OpenAIProvider.new()
      model = OpenAIProvider.get_stt_model(provider, "whisper-1")

      assert %OpenAISTT{} = model
      assert model.model == "whisper-1"
    end

    test "passes API key to model" do
      provider = OpenAIProvider.new(api_key: "sk-test")
      model = OpenAIProvider.get_stt_model(provider, nil)

      assert model.api_key == "sk-test"
    end

    test "passes base URL to model" do
      provider = OpenAIProvider.new(base_url: "https://custom.api.com")
      model = OpenAIProvider.get_stt_model(provider, nil)

      assert model.base_url == "https://custom.api.com"
    end
  end

  describe "get_tts_model/2" do
    test "returns default TTS model when name is nil" do
      provider = OpenAIProvider.new()
      model = OpenAIProvider.get_tts_model(provider, nil)

      assert %OpenAITTS{} = model
      assert model.model == "gpt-4o-mini-tts"
    end

    test "returns custom TTS model when name is provided" do
      provider = OpenAIProvider.new()
      model = OpenAIProvider.get_tts_model(provider, "tts-1")

      assert %OpenAITTS{} = model
      assert model.model == "tts-1"
    end

    test "passes API key to model" do
      provider = OpenAIProvider.new(api_key: "sk-test")
      model = OpenAIProvider.get_tts_model(provider, nil)

      assert model.api_key == "sk-test"
    end

    test "passes base URL to model" do
      provider = OpenAIProvider.new(base_url: "https://custom.api.com")
      model = OpenAIProvider.get_tts_model(provider, nil)

      assert model.base_url == "https://custom.api.com"
    end
  end

  describe "behaviour callbacks" do
    test "get_stt_model/1 works with just model name" do
      model = OpenAIProvider.get_stt_model(nil)
      assert %OpenAISTT{} = model
      assert model.model == "gpt-4o-transcribe"
    end

    test "get_tts_model/1 works with just model name" do
      model = OpenAIProvider.get_tts_model(nil)
      assert %OpenAITTS{} = model
      assert model.model == "gpt-4o-mini-tts"
    end
  end

  describe "struct" do
    test "has expected fields" do
      provider = %OpenAIProvider{}
      assert Map.has_key?(provider, :api_key)
      assert Map.has_key?(provider, :base_url)
      assert Map.has_key?(provider, :organization)
      assert Map.has_key?(provider, :project)
    end
  end
end
