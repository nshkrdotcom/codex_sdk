defmodule Codex.Voice.Config.TTSSettings do
  @moduledoc """
  Settings for text-to-speech models.

  ## Fields

  - `:voice` - The voice to use for TTS. If not provided, the model's default is used.
  - `:buffer_size` - Minimal size of audio chunks being streamed out (default: 120)
  - `:instructions` - Instructions for the TTS model to follow
  - `:speed` - Playback speed between 0.25 and 4.0 (optional)
  """

  alias Codex.Config.Defaults

  @typedoc """
  Available TTS voice options.
  """
  @type voice :: :alloy | :ash | :coral | :echo | :fable | :onyx | :nova | :sage | :shimmer

  @default_instructions Defaults.tts_default_instructions()
  @default_buffer_size Defaults.tts_buffer_size()

  defstruct [
    :voice,
    :speed,
    buffer_size: @default_buffer_size,
    instructions: @default_instructions
  ]

  @type t :: %__MODULE__{
          voice: voice() | nil,
          buffer_size: non_neg_integer(),
          instructions: String.t(),
          speed: float() | nil
        }

  @doc """
  Create new TTS settings with the given options.

  ## Options

  - `:voice` - The voice to use (`:alloy`, `:ash`, `:coral`, `:echo`, `:fable`, `:onyx`, `:nova`, `:sage`, `:shimmer`)
  - `:buffer_size` - Minimal audio chunk size (default: 120)
  - `:instructions` - Instructions for the model
  - `:speed` - Playback speed between 0.25 and 4.0

  ## Examples

      iex> settings = Codex.Voice.Config.TTSSettings.new(voice: :nova, speed: 1.2)
      iex> settings.voice
      :nova
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      voice: Keyword.get(opts, :voice),
      buffer_size: Keyword.get(opts, :buffer_size, @default_buffer_size),
      instructions: Keyword.get(opts, :instructions, @default_instructions),
      speed: Keyword.get(opts, :speed)
    }
  end
end
