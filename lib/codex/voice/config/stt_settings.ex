defmodule Codex.Voice.Config.STTSettings do
  @moduledoc """
  Settings for speech-to-text models.

  ## Fields

  - `:prompt` - Instructions for the model to follow
  - `:language` - The language of the audio input (e.g., "en", "es", "fr")
  - `:temperature` - Sampling temperature for the model
  - `:turn_detection` - Turn detection settings for streamed audio input
  """

  defstruct [:prompt, :language, :temperature, :turn_detection]

  @type t :: %__MODULE__{
          prompt: String.t() | nil,
          language: String.t() | nil,
          temperature: float() | nil,
          turn_detection: map() | nil
        }

  @doc """
  Create new STT settings with the given options.

  ## Options

  - `:prompt` - Instructions for the model
  - `:language` - Language code (e.g., "en")
  - `:temperature` - Sampling temperature
  - `:turn_detection` - Turn detection configuration

  ## Examples

      iex> settings = Codex.Voice.Config.STTSettings.new(language: "en")
      iex> settings.language
      "en"
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      prompt: Keyword.get(opts, :prompt),
      language: Keyword.get(opts, :language),
      temperature: Keyword.get(opts, :temperature),
      turn_detection: Keyword.get(opts, :turn_detection)
    }
  end
end
