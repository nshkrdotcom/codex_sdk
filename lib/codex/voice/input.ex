defmodule Codex.Voice.Input do
  @moduledoc """
  Audio input types for voice pipelines.

  This module provides two types of audio input:

  - `AudioInput` - A complete, static audio buffer
  - `StreamedAudioInput` - A streaming audio input that can be appended to

  Both types support the standard PCM16 format at 24kHz, which is the default
  format for OpenAI's voice APIs.

  ## Examples

      # Static audio input
      data = File.read!("recording.pcm")
      input = AudioInput.new(data)
      base64 = AudioInput.to_base64(input)

      # Streaming audio input
      input = StreamedAudioInput.new()
      spawn(fn ->
        Enum.each(chunks, &StreamedAudioInput.add(input, &1))
        StreamedAudioInput.close(input)
      end)
      for chunk <- StreamedAudioInput.stream(input) do
        process(chunk)
      end
  """

  @default_sample_rate 24_000

  defmodule AudioInput do
    @moduledoc """
    A single, complete audio input buffer.

    This struct holds static audio data along with its format parameters.
    The default format is PCM16 at 24kHz mono, which is the standard format
    for OpenAI's voice APIs.
    """

    defstruct [:data, frame_rate: 24_000, sample_width: 2, channels: 1]

    @type t :: %__MODULE__{
            data: binary(),
            frame_rate: pos_integer(),
            sample_width: pos_integer(),
            channels: pos_integer()
          }

    @doc """
    Create a new audio input from binary data.

    ## Options

    - `:frame_rate` - Sample rate in Hz (default: 24000)
    - `:sample_width` - Bytes per sample (default: 2)
    - `:channels` - Number of audio channels (default: 1)

    ## Examples

        iex> data = <<0, 0, 255, 127>>
        iex> input = Codex.Voice.Input.AudioInput.new(data)
        iex> input.frame_rate
        24000
    """
    @spec new(binary(), keyword()) :: t()
    def new(data, opts \\ []) when is_binary(data) do
      %__MODULE__{
        data: data,
        frame_rate: Keyword.get(opts, :frame_rate, 24_000),
        sample_width: Keyword.get(opts, :sample_width, 2),
        channels: Keyword.get(opts, :channels, 1)
      }
    end

    @doc """
    Encode audio data to base64.

    This is useful when sending audio data to APIs that expect base64-encoded
    audio.

    ## Examples

        iex> data = <<0, 0, 255, 127>>
        iex> input = Codex.Voice.Input.AudioInput.new(data)
        iex> Codex.Voice.Input.AudioInput.to_base64(input)
        "AAD/fw=="
    """
    @spec to_base64(t()) :: String.t()
    def to_base64(%__MODULE__{data: data}) do
      Base.encode64(data)
    end

    @doc """
    Convert audio to WAV file format.

    Returns a tuple of `{filename, wav_data, mime_type}` suitable for
    multipart uploads or file operations.

    ## Examples

        iex> data = <<0, 0, 255, 127>>
        iex> input = Codex.Voice.Input.AudioInput.new(data)
        iex> {filename, _wav_data, mime} = Codex.Voice.Input.AudioInput.to_audio_file(input)
        iex> {filename, mime}
        {"audio.wav", "audio/wav"}
    """
    @spec to_audio_file(t()) :: {String.t(), binary(), String.t()}
    def to_audio_file(%__MODULE__{} = input) do
      wav_data = encode_wav(input)
      {"audio.wav", wav_data, "audio/wav"}
    end

    @spec encode_wav(t()) :: binary()
    defp encode_wav(%__MODULE__{} = input) do
      data_size = byte_size(input.data)
      byte_rate = input.frame_rate * input.channels * input.sample_width
      block_align = input.channels * input.sample_width

      # RIFF header (12 bytes)
      riff_header = <<"RIFF", data_size + 36::little-32, "WAVE">>

      # fmt chunk (24 bytes)
      fmt_chunk = <<
        "fmt ",
        # chunk size
        16::little-32,
        # audio format (PCM)
        1::little-16,
        input.channels::little-16,
        input.frame_rate::little-32,
        byte_rate::little-32,
        block_align::little-16,
        input.sample_width * 8::little-16
      >>

      # data chunk (8 bytes header + data)
      data_chunk = <<"data", data_size::little-32, input.data::binary>>

      riff_header <> fmt_chunk <> data_chunk
    end
  end

  defmodule StreamedAudioInput do
    @moduledoc """
    A streaming audio input that can be appended to.

    Uses an Agent-backed queue for audio chunks. This allows you to push
    audio data to the input while the pipeline consumes it.

    ## Example

        input = StreamedAudioInput.new()

        # Producer task
        Task.async(fn ->
          for chunk <- audio_source do
            StreamedAudioInput.add(input, chunk)
          end
          StreamedAudioInput.close(input)
        end)

        # Consumer
        for chunk <- StreamedAudioInput.stream(input) do
          process(chunk)
        end
    """

    defstruct [:queue]

    @type t :: %__MODULE__{
            queue: pid()
          }

    @doc """
    Create a new streamed audio input.

    Starts an Agent process to manage the audio chunk queue.
    """
    @spec new() :: t()
    def new do
      {:ok, queue} = Agent.start_link(fn -> :queue.new() end)
      %__MODULE__{queue: queue}
    end

    @doc """
    Add an audio chunk to the stream.

    ## Examples

        iex> input = Codex.Voice.Input.StreamedAudioInput.new()
        iex> Codex.Voice.Input.StreamedAudioInput.add(input, <<0, 0>>)
        :ok
    """
    @spec add(t(), binary()) :: :ok
    def add(%__MODULE__{queue: queue}, data) when is_binary(data) do
      Agent.update(queue, fn q -> :queue.in(data, q) end)
      :ok
    end

    @doc """
    Close the stream, signaling no more data will be added.

    After calling close, consumers will receive `:eof` after consuming
    all remaining chunks.
    """
    @spec close(t()) :: :ok
    def close(%__MODULE__{queue: queue}) do
      Agent.update(queue, fn q -> :queue.in(:eof, q) end)
      :ok
    end

    @doc """
    Get the next chunk from the stream.

    Returns:
    - `{:ok, binary}` - The next audio chunk
    - `:eof` - The stream has been closed
    - `:empty` - No data currently available (try again later)
    """
    @spec get(t()) :: {:ok, binary()} | :eof | :empty
    def get(%__MODULE__{queue: queue}) do
      Agent.get_and_update(queue, fn q ->
        case :queue.out(q) do
          {{:value, :eof}, q2} -> {:eof, q2}
          {{:value, data}, q2} -> {{:ok, data}, q2}
          {:empty, q} -> {:empty, q}
        end
      end)
    end

    @doc """
    Stream audio chunks until the stream is closed.

    This returns a `Stream` that yields audio chunks as they become
    available, completing when the stream is closed.

    Note: If the stream is empty and not closed, this will poll with
    a 10ms delay. For high-performance use cases, consider using
    `get/1` directly with your own polling strategy.
    """
    @spec stream(t()) :: Enumerable.t()
    def stream(%__MODULE__{} = input) do
      Stream.resource(
        fn -> input end,
        fn input ->
          case get(input) do
            {:ok, data} ->
              {[data], input}

            :eof ->
              {:halt, input}

            :empty ->
              Process.sleep(10)
              {[], input}
          end
        end,
        fn _ -> :ok end
      )
    end
  end

  # Re-export the default sample rate for external use
  @doc false
  def default_sample_rate, do: @default_sample_rate
end
