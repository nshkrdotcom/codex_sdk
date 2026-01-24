defmodule Codex.Realtime.AudioTest do
  use ExUnit.Case, async: true

  alias Codex.Realtime.Audio

  describe "pcm16_to_base64/1" do
    test "encodes PCM16 bytes to base64" do
      # 4 samples of PCM16 (8 bytes)
      pcm_data = <<0, 0, 255, 127, 0, 128, 1, 0>>
      encoded = Audio.pcm16_to_base64(pcm_data)
      assert is_binary(encoded)
      assert Base.decode64!(encoded) == pcm_data
    end

    test "handles empty data" do
      assert Audio.pcm16_to_base64(<<>>) == ""
    end
  end

  describe "base64_to_pcm16/1" do
    test "decodes base64 to PCM16 bytes" do
      original = <<0, 0, 255, 127, 0, 128, 1, 0>>
      encoded = Base.encode64(original)
      decoded = Audio.base64_to_pcm16(encoded)
      assert decoded == original
    end

    test "returns error for invalid base64" do
      assert {:error, _} = Audio.base64_to_pcm16("not valid base64!!!")
    end
  end

  describe "calculate_audio_length_ms/2" do
    test "calculates length for pcm16 at 24kHz" do
      # 24000 samples/sec * 2 bytes/sample = 48000 bytes/sec
      # 1 second = 48000 bytes
      one_second = :binary.copy(<<0>>, 48_000)
      ms = Audio.calculate_audio_length_ms(:pcm16, one_second)
      assert_in_delta ms, 1000.0, 1.0
    end

    test "calculates length for shorter audio" do
      # 100ms of audio at 24kHz PCM16 = 4800 bytes
      audio = :binary.copy(<<0>>, 4_800)
      ms = Audio.calculate_audio_length_ms(:pcm16, audio)
      assert_in_delta ms, 100.0, 1.0
    end

    test "calculates length for g711_ulaw at 8kHz" do
      # 8000 samples/sec * 1 byte/sample = 8000 bytes/sec
      one_second = :binary.copy(<<0>>, 8_000)
      ms = Audio.calculate_audio_length_ms(:g711_ulaw, one_second)
      assert_in_delta ms, 1000.0, 1.0
    end

    test "calculates length for g711_alaw at 8kHz" do
      one_second = :binary.copy(<<0>>, 8_000)
      ms = Audio.calculate_audio_length_ms(:g711_alaw, one_second)
      assert_in_delta ms, 1000.0, 1.0
    end

    test "returns 0 for empty audio" do
      assert Audio.calculate_audio_length_ms(:pcm16, <<>>) == 0.0
    end
  end

  describe "audio format constants" do
    test "pcm16 sample rate is 24000" do
      assert Audio.sample_rate(:pcm16) == 24_000
    end

    test "pcm16 bytes per sample is 2" do
      assert Audio.bytes_per_sample(:pcm16) == 2
    end

    test "g711 sample rate is 8000" do
      assert Audio.sample_rate(:g711_ulaw) == 8_000
      assert Audio.sample_rate(:g711_alaw) == 8_000
    end

    test "g711 bytes per sample is 1" do
      assert Audio.bytes_per_sample(:g711_ulaw) == 1
      assert Audio.bytes_per_sample(:g711_alaw) == 1
    end
  end
end
