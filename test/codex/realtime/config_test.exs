defmodule Codex.Realtime.ConfigTest do
  use ExUnit.Case, async: true

  alias Codex.Realtime.Config

  describe "SessionModelSettings" do
    test "creates with defaults" do
      settings = %Config.SessionModelSettings{}
      assert settings.model_name == nil
      assert settings.modalities == nil
    end

    test "creates with all options" do
      settings = %Config.SessionModelSettings{
        model_name: "gpt-4o-realtime-preview",
        instructions: "Be helpful",
        modalities: [:text, :audio],
        voice: "alloy",
        speed: 1.0,
        input_audio_format: :pcm16,
        output_audio_format: :pcm16,
        turn_detection: %Config.TurnDetectionConfig{
          type: :semantic_vad,
          eagerness: :medium
        }
      }

      assert settings.model_name == "gpt-4o-realtime-preview"
      assert settings.modalities == [:text, :audio]
      assert settings.turn_detection.type == :semantic_vad
    end

    test "serializes to JSON" do
      settings = %Config.SessionModelSettings{
        model_name: "gpt-4o-realtime-preview",
        voice: "alloy",
        modalities: [:text, :audio]
      }

      json = Config.SessionModelSettings.to_json(settings)

      assert json["model"] == "gpt-4o-realtime-preview"
      assert json["voice"] == "alloy"
      assert json["modalities"] == ["text", "audio"]
    end

    test "serializes nested configs to JSON" do
      settings = %Config.SessionModelSettings{
        model_name: "gpt-4o-realtime-preview",
        turn_detection: %Config.TurnDetectionConfig{
          type: :server_vad,
          threshold: 0.5
        },
        input_audio_transcription: %Config.TranscriptionConfig{
          model: "whisper-1"
        }
      }

      json = Config.SessionModelSettings.to_json(settings)

      assert json["turn_detection"]["type"] == "server_vad"
      assert json["turn_detection"]["threshold"] == 0.5
      assert json["input_audio_transcription"]["model"] == "whisper-1"
    end

    test "omits nil values from JSON" do
      settings = %Config.SessionModelSettings{
        voice: "alloy"
      }

      json = Config.SessionModelSettings.to_json(settings)

      assert json["voice"] == "alloy"
      refute Map.has_key?(json, "model")
      refute Map.has_key?(json, "modalities")
      refute Map.has_key?(json, "instructions")
    end
  end

  describe "TurnDetectionConfig" do
    test "creates semantic VAD config" do
      config = %Config.TurnDetectionConfig{
        type: :semantic_vad,
        eagerness: :high,
        create_response: true
      }

      assert config.type == :semantic_vad
      assert config.eagerness == :high
    end

    test "creates server VAD config" do
      config = %Config.TurnDetectionConfig{
        type: :server_vad,
        threshold: 0.5,
        silence_duration_ms: 500,
        prefix_padding_ms: 300
      }

      assert config.type == :server_vad
      assert config.threshold == 0.5
    end

    test "serializes to JSON" do
      config = %Config.TurnDetectionConfig{
        type: :server_vad,
        threshold: 0.5,
        silence_duration_ms: 500
      }

      json = Config.TurnDetectionConfig.to_json(config)

      assert json["type"] == "server_vad"
      assert json["threshold"] == 0.5
      assert json["silence_duration_ms"] == 500
    end

    test "serializes eagerness values" do
      for {eagerness, expected} <- [
            {:auto, "auto"},
            {:low, "low"},
            {:medium, "medium"},
            {:high, "high"}
          ] do
        config = %Config.TurnDetectionConfig{type: :semantic_vad, eagerness: eagerness}
        json = Config.TurnDetectionConfig.to_json(config)
        assert json["eagerness"] == expected
      end
    end

    test "includes interrupt_response and idle_timeout_ms" do
      config = %Config.TurnDetectionConfig{
        type: :semantic_vad,
        interrupt_response: true,
        idle_timeout_ms: 5000
      }

      json = Config.TurnDetectionConfig.to_json(config)

      assert json["interrupt_response"] == true
      assert json["idle_timeout_ms"] == 5000
    end
  end

  describe "TranscriptionConfig" do
    test "creates transcription config" do
      config = %Config.TranscriptionConfig{
        model: "whisper-1",
        language: "en",
        prompt: "Technical conversation"
      }

      assert config.model == "whisper-1"
      assert config.language == "en"
    end

    test "serializes to JSON" do
      config = %Config.TranscriptionConfig{model: "whisper-1"}
      json = Config.TranscriptionConfig.to_json(config)
      assert json["model"] == "whisper-1"
    end

    test "omits nil values from JSON" do
      config = %Config.TranscriptionConfig{model: "whisper-1"}
      json = Config.TranscriptionConfig.to_json(config)

      assert json["model"] == "whisper-1"
      refute Map.has_key?(json, "language")
      refute Map.has_key?(json, "prompt")
    end
  end

  describe "NoiseReductionConfig" do
    test "creates near field config" do
      config = %Config.NoiseReductionConfig{type: :near_field}
      assert config.type == :near_field
    end

    test "creates far field config" do
      config = %Config.NoiseReductionConfig{type: :far_field}
      assert config.type == :far_field
    end

    test "serializes to JSON" do
      near_field = %Config.NoiseReductionConfig{type: :near_field}
      far_field = %Config.NoiseReductionConfig{type: :far_field}

      assert Config.NoiseReductionConfig.to_json(near_field) == %{"type" => "near_field"}
      assert Config.NoiseReductionConfig.to_json(far_field) == %{"type" => "far_field"}
    end

    test "returns empty map for nil type" do
      config = %Config.NoiseReductionConfig{type: nil}
      assert Config.NoiseReductionConfig.to_json(config) == %{}
    end
  end

  describe "TracingConfig" do
    test "creates tracing config" do
      config = %Config.TracingConfig{
        workflow_name: "voice_agent",
        group_id: "session_123",
        metadata: %{"user_id" => "user_456"}
      }

      assert config.workflow_name == "voice_agent"
      assert config.metadata["user_id"] == "user_456"
    end

    test "creates with partial fields" do
      config = %Config.TracingConfig{workflow_name: "my_workflow"}

      assert config.workflow_name == "my_workflow"
      assert config.group_id == nil
      assert config.metadata == nil
    end
  end

  describe "GuardrailsSettings" do
    test "creates with default debounce" do
      settings = %Config.GuardrailsSettings{}
      assert settings.debounce_text_length == 100
    end

    test "creates with custom debounce" do
      settings = %Config.GuardrailsSettings{debounce_text_length: 200}
      assert settings.debounce_text_length == 200
    end
  end

  describe "RunConfig" do
    test "creates run config" do
      config = %Config.RunConfig{
        model_settings: %Config.SessionModelSettings{voice: "nova"},
        tracing_disabled: false,
        async_tool_calls: true
      }

      assert config.model_settings.voice == "nova"
      assert config.async_tool_calls == true
    end

    test "has correct defaults" do
      config = %Config.RunConfig{}

      assert config.tracing_disabled == false
      assert config.async_tool_calls == true
      assert config.model_settings == nil
      assert config.output_guardrails == nil
    end

    test "creates with guardrails" do
      config = %Config.RunConfig{
        output_guardrails: [:content_filter],
        guardrails_settings: %Config.GuardrailsSettings{debounce_text_length: 50}
      }

      assert config.guardrails_settings.debounce_text_length == 50
    end
  end

  describe "ModelConfig" do
    test "creates model config with API key" do
      config = %Config.ModelConfig{
        api_key: "sk-test-key",
        url: "wss://api.openai.com/v1/realtime"
      }

      assert config.api_key == "sk-test-key"
      assert config.url == "wss://api.openai.com/v1/realtime"
    end

    test "creates model config with headers" do
      config = %Config.ModelConfig{
        headers: %{"X-Custom" => "value"}
      }

      assert config.headers["X-Custom"] == "value"
    end

    test "creates model config with call_id for SIP" do
      config = %Config.ModelConfig{
        call_id: "call_abc123"
      }

      assert config.call_id == "call_abc123"
    end

    test "supports function for API key" do
      config = %Config.ModelConfig{
        api_key: fn -> "dynamic-key" end
      }

      assert is_function(config.api_key)
    end

    test "resolves static API key" do
      config = %Config.ModelConfig{api_key: "sk-static-key"}
      assert Config.ModelConfig.resolve_api_key(config) == "sk-static-key"
    end

    test "resolves function API key" do
      config = %Config.ModelConfig{api_key: fn -> "sk-dynamic-key" end}
      assert Config.ModelConfig.resolve_api_key(config) == "sk-dynamic-key"
    end

    test "builds URL with model name" do
      config = %Config.ModelConfig{url: "wss://api.openai.com/v1/realtime"}
      url = Config.ModelConfig.build_url(config, "gpt-4o-realtime-preview")

      assert url == "wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview"
    end

    test "builds URL with call_id for SIP" do
      config = %Config.ModelConfig{
        url: "wss://api.openai.com/v1/realtime",
        call_id: "call_123"
      }

      url = Config.ModelConfig.build_url(config, "gpt-4o-realtime-preview")

      # call_id takes precedence over model name
      assert url == "wss://api.openai.com/v1/realtime?call_id=call_123"
    end

    test "uses default URL when not specified" do
      config = %Config.ModelConfig{}
      url = Config.ModelConfig.build_url(config, "gpt-4o-realtime-preview")

      assert url == "wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview"
    end
  end

  describe "merge_settings/2" do
    test "merges session settings" do
      base = %Config.SessionModelSettings{
        voice: "alloy",
        speed: 1.0
      }

      override = %Config.SessionModelSettings{
        voice: "nova"
      }

      merged = Config.merge_settings(base, override)

      assert merged.voice == "nova"
      assert merged.speed == 1.0
    end

    test "override takes precedence for non-nil values" do
      base = %Config.SessionModelSettings{
        model_name: "gpt-4o-realtime-preview",
        voice: "alloy"
      }

      override = %Config.SessionModelSettings{
        voice: "coral"
      }

      merged = Config.merge_settings(base, override)

      assert merged.model_name == "gpt-4o-realtime-preview"
      assert merged.voice == "coral"
    end

    test "preserves all fields from base when override has nil" do
      base = %Config.SessionModelSettings{
        model_name: "gpt-4o-realtime-preview",
        voice: "alloy",
        speed: 1.2,
        modalities: [:text, :audio],
        input_audio_format: :pcm16
      }

      override = %Config.SessionModelSettings{}

      merged = Config.merge_settings(base, override)

      assert merged.model_name == "gpt-4o-realtime-preview"
      assert merged.voice == "alloy"
      assert merged.speed == 1.2
      assert merged.modalities == [:text, :audio]
      assert merged.input_audio_format == :pcm16
    end
  end

  describe "default_session_settings/0" do
    test "returns default settings" do
      settings = Config.default_session_settings()

      assert settings.modalities == [:text, :audio]
      assert settings.input_audio_format == :pcm16
      assert settings.output_audio_format == :pcm16
      assert settings.turn_detection.type == :semantic_vad
      assert settings.turn_detection.create_response == true
      assert settings.turn_detection.interrupt_response == true
    end
  end
end
