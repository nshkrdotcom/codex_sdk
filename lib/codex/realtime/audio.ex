defmodule Codex.Realtime.Audio do
  @moduledoc """
  Audio format utilities for realtime sessions.

  Supports PCM16 (24kHz), G.711 u-law, and G.711 A-law formats.
  """

  @type atom_format :: :pcm16 | :g711_ulaw | :g711_alaw
  @type string_format :: String.t()
  @type format :: atom_format() | string_format()

  alias Codex.Config.Defaults

  # Format Constants

  @pcm16_sample_rate Defaults.pcm16_sample_rate()
  @pcm16_bytes_per_sample Defaults.pcm16_bytes_per_sample()

  @g711_sample_rate Defaults.g711_sample_rate()
  @g711_bytes_per_sample Defaults.g711_bytes_per_sample()

  @doc """
  Get the sample rate for an audio format.

  ## Examples

      iex> Codex.Realtime.Audio.sample_rate(:pcm16)
      24000

      iex> Codex.Realtime.Audio.sample_rate(:g711_ulaw)
      8000
  """
  @spec sample_rate(format()) :: 8_000 | 24_000
  def sample_rate(:pcm16), do: @pcm16_sample_rate
  def sample_rate(:g711_ulaw), do: @g711_sample_rate
  def sample_rate(:g711_alaw), do: @g711_sample_rate
  def sample_rate("pcm16"), do: @pcm16_sample_rate
  def sample_rate("g711_ulaw"), do: @g711_sample_rate
  def sample_rate("g711_alaw"), do: @g711_sample_rate

  @doc """
  Get bytes per sample for an audio format.

  ## Examples

      iex> Codex.Realtime.Audio.bytes_per_sample(:pcm16)
      2

      iex> Codex.Realtime.Audio.bytes_per_sample(:g711_ulaw)
      1
  """
  @spec bytes_per_sample(format()) :: 1 | 2
  def bytes_per_sample(:pcm16), do: @pcm16_bytes_per_sample
  def bytes_per_sample(:g711_ulaw), do: @g711_bytes_per_sample
  def bytes_per_sample(:g711_alaw), do: @g711_bytes_per_sample
  def bytes_per_sample("pcm16"), do: @pcm16_bytes_per_sample
  def bytes_per_sample("g711_ulaw"), do: @g711_bytes_per_sample
  def bytes_per_sample("g711_alaw"), do: @g711_bytes_per_sample

  @doc """
  Calculate the duration of audio data in milliseconds.

  ## Examples

      iex> audio = :binary.copy(<<0>>, 48_000)  # 1 second of PCM16
      iex> Codex.Realtime.Audio.calculate_audio_length_ms(:pcm16, audio)
      1000.0
  """
  @spec calculate_audio_length_ms(format(), binary()) :: float()
  def calculate_audio_length_ms(_format, <<>>), do: 0.0

  def calculate_audio_length_ms(format, data) when is_binary(data) do
    bytes = byte_size(data)
    rate = sample_rate(format)
    bps = bytes_per_sample(format)

    # samples = bytes / bytes_per_sample
    # seconds = samples / sample_rate
    # milliseconds = seconds * 1000
    bytes / bps / rate * 1000.0
  end

  @doc """
  Encode PCM16 audio bytes to base64.

  ## Examples

      iex> Codex.Realtime.Audio.pcm16_to_base64(<<0, 0, 255, 127>>)
      "AAD/fw=="
  """
  @spec pcm16_to_base64(binary()) :: String.t()
  def pcm16_to_base64(<<>>), do: ""

  def pcm16_to_base64(data) when is_binary(data) do
    Base.encode64(data)
  end

  @doc """
  Decode base64 to PCM16 audio bytes.

  ## Examples

      iex> Codex.Realtime.Audio.base64_to_pcm16("AAD/fw==")
      <<0, 0, 255, 127>>
  """
  @spec base64_to_pcm16(String.t()) :: binary() | {:error, :invalid_base64}
  def base64_to_pcm16(encoded) when is_binary(encoded) do
    case Base.decode64(encoded) do
      {:ok, data} -> data
      :error -> {:error, :invalid_base64}
    end
  end

  @doc """
  Normalize audio format to atom.

  ## Examples

      iex> Codex.Realtime.Audio.normalize_format("pcm16")
      :pcm16

      iex> Codex.Realtime.Audio.normalize_format(:g711_ulaw)
      :g711_ulaw
  """
  @spec normalize_format(format()) :: :pcm16 | :g711_ulaw | :g711_alaw
  def normalize_format(:pcm16), do: :pcm16
  def normalize_format(:g711_ulaw), do: :g711_ulaw
  def normalize_format(:g711_alaw), do: :g711_alaw
  def normalize_format("pcm16"), do: :pcm16
  def normalize_format("g711_ulaw"), do: :g711_ulaw
  def normalize_format("g711_alaw"), do: :g711_alaw
end
