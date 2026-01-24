defmodule Codex.Voice.Model do
  @moduledoc """
  Behaviours for speech-to-text and text-to-speech models.

  This module defines the behaviours (interfaces) that voice models must implement.
  It provides a consistent API for transcribing audio (STT) and generating speech (TTS).

  ## STT Models

  Speech-to-text models convert audio input into text. They support both:
  - Single-shot transcription via `transcribe/5`
  - Streaming transcription sessions via `create_session/4`

  ## TTS Models

  Text-to-speech models convert text into audio. They return a stream of
  audio bytes in PCM format.

  ## Model Providers

  Model providers are factories that create STT and TTS models by name.
  The `OpenAIProvider` is the default implementation.

  ## Example

      # Using the OpenAI provider
      provider = Codex.Voice.Models.OpenAIProvider.new()
      stt_model = Codex.Voice.Models.OpenAIProvider.get_stt_model(provider, nil)
      tts_model = Codex.Voice.Models.OpenAIProvider.get_tts_model(provider, nil)

      # Transcribe audio
      {:ok, text} = Codex.Voice.Models.OpenAISTT.transcribe(
        stt_model, audio_input, stt_settings, true, false
      )

      # Generate speech
      audio_stream = Codex.Voice.Models.OpenAITTS.run(tts_model, "Hello!", tts_settings)
  """

  alias Codex.Voice.Config.STTSettings
  alias Codex.Voice.Input.StreamedAudioInput

  defmodule StreamedTranscriptionSession do
    @moduledoc """
    Behaviour for streaming transcription sessions.

    A streaming transcription session receives audio input continuously
    and produces text transcriptions for each detected turn in the conversation.
    """

    @doc """
    Returns a stream of text transcriptions.

    Each element in the stream represents a complete turn in the conversation.
    The stream completes when `close/1` is called on the session.
    """
    @callback transcribe_turns(session :: pid()) :: Enumerable.t()

    @doc """
    Closes the transcription session and releases resources.
    """
    @callback close(session :: pid()) :: :ok
  end

  defmodule STTModel do
    @moduledoc """
    Behaviour for speech-to-text models.

    STT models convert audio input into text transcriptions. They support
    both single-shot transcription and streaming transcription sessions.

    Note: The behaviour callbacks use module-level functions. Implementations
    should use struct-based models where the struct is passed as the first
    parameter to instance methods like `transcribe/5`.
    """

    @doc """
    Returns the name of the STT model.
    """
    @callback model_name() :: String.t()

    @doc """
    Creates a streaming transcription session.

    The session receives audio input via the `StreamedAudioInput` and
    produces text transcriptions for each detected turn.

    ## Parameters

    - `input` - The streamed audio input
    - `settings` - STT settings
    - `trace_include_sensitive_data` - Whether to include text in traces
    - `trace_include_sensitive_audio_data` - Whether to include audio in traces

    ## Returns

    - `{:ok, session_pid}` - The session process
    - `{:error, reason}` - If session creation fails
    """
    @callback create_session(
                input :: StreamedAudioInput.t(),
                settings :: STTSettings.t(),
                trace_include_sensitive_data :: boolean(),
                trace_include_sensitive_audio_data :: boolean()
              ) :: {:ok, pid()} | {:error, term()}
  end

  defmodule TTSModel do
    @moduledoc """
    Behaviour for text-to-speech models.

    TTS models convert text into audio. The audio is returned as a stream
    of bytes in PCM format for efficient memory usage with large outputs.

    Note: The behaviour callbacks use module-level functions. Implementations
    should use struct-based models where the struct is passed as the first
    parameter to instance methods like `run/3`.
    """

    @doc """
    Returns the name of the TTS model.
    """
    @callback model_name() :: String.t()
  end

  defmodule ModelProvider do
    @moduledoc """
    Behaviour for voice model providers.

    Model providers are factories that create STT and TTS model instances
    by name. They handle client initialization and configuration.
    """

    @doc """
    Get a speech-to-text model by name.

    If `name` is nil, returns the default STT model.
    """
    @callback get_stt_model(name :: String.t() | nil) :: struct()

    @doc """
    Get a text-to-speech model by name.

    If `name` is nil, returns the default TTS model.
    """
    @callback get_tts_model(name :: String.t() | nil) :: struct()
  end
end
