defmodule Codex.Voice.InputTest do
  use ExUnit.Case, async: true

  alias Codex.Voice.Input

  describe "AudioInput" do
    test "creates from binary with default settings" do
      data = :binary.copy(<<0>>, 4800)
      input = Input.AudioInput.new(data)

      assert input.frame_rate == 24_000
      assert input.sample_width == 2
      assert input.channels == 1
      assert input.data == data
    end

    test "creates from binary with custom settings" do
      data = <<0, 0, 255, 127>>
      input = Input.AudioInput.new(data, frame_rate: 16_000, sample_width: 1, channels: 2)

      assert input.frame_rate == 16_000
      assert input.sample_width == 1
      assert input.channels == 2
    end

    test "converts to base64" do
      data = <<0, 0, 255, 127>>
      input = Input.AudioInput.new(data)

      base64 = Input.AudioInput.to_base64(input)
      assert is_binary(base64)
      assert Base.decode64!(base64) == data
    end

    test "converts to WAV" do
      data = :binary.copy(<<0>>, 48_000)
      input = Input.AudioInput.new(data)

      {filename, wav_data, mime} = Input.AudioInput.to_audio_file(input)
      assert filename == "audio.wav"
      assert mime == "audio/wav"
      assert String.starts_with?(wav_data, "RIFF")
    end

    test "WAV header contains correct metadata" do
      # 100ms of mono 24kHz 16-bit audio = 4800 bytes
      data = :binary.copy(<<0, 0>>, 2400)
      input = Input.AudioInput.new(data)

      {_filename, wav_data, _mime} = Input.AudioInput.to_audio_file(input)

      # Parse WAV header
      <<"RIFF", _size::little-32, "WAVE", "fmt ", fmt_size::little-32, audio_format::little-16,
        channels::little-16, sample_rate::little-32, _byte_rate::little-32,
        _block_align::little-16, bits_per_sample::little-16, _rest::binary>> = wav_data

      assert fmt_size == 16
      assert audio_format == 1
      assert channels == 1
      assert sample_rate == 24_000
      assert bits_per_sample == 16
    end
  end

  describe "StreamedAudioInput" do
    test "creates with queue" do
      input = Input.StreamedAudioInput.new()
      assert is_pid(input.queue)
    end

    test "adds audio chunks" do
      input = Input.StreamedAudioInput.new()
      data = <<0, 0, 255, 127>>

      assert :ok = Input.StreamedAudioInput.add(input, data)
      assert {:ok, ^data} = Input.StreamedAudioInput.get(input)
    end

    test "returns empty when no data available" do
      input = Input.StreamedAudioInput.new()
      assert :empty = Input.StreamedAudioInput.get(input)
    end

    test "closes stream" do
      input = Input.StreamedAudioInput.new()
      :ok = Input.StreamedAudioInput.close(input)

      assert :eof = Input.StreamedAudioInput.get(input)
    end

    test "preserves order of chunks" do
      input = Input.StreamedAudioInput.new()

      :ok = Input.StreamedAudioInput.add(input, <<1>>)
      :ok = Input.StreamedAudioInput.add(input, <<2>>)
      :ok = Input.StreamedAudioInput.add(input, <<3>>)
      :ok = Input.StreamedAudioInput.close(input)

      assert {:ok, <<1>>} = Input.StreamedAudioInput.get(input)
      assert {:ok, <<2>>} = Input.StreamedAudioInput.get(input)
      assert {:ok, <<3>>} = Input.StreamedAudioInput.get(input)
      assert :eof = Input.StreamedAudioInput.get(input)
    end

    test "stream/1 returns all chunks until eof" do
      input = Input.StreamedAudioInput.new()

      :ok = Input.StreamedAudioInput.add(input, <<1>>)
      :ok = Input.StreamedAudioInput.add(input, <<2>>)
      :ok = Input.StreamedAudioInput.add(input, <<3>>)
      :ok = Input.StreamedAudioInput.close(input)

      chunks = input |> Input.StreamedAudioInput.stream() |> Enum.to_list()
      assert chunks == [<<1>>, <<2>>, <<3>>]
    end
  end
end
