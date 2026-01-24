defmodule Codex.Voice.Config do
  @moduledoc """
  Configuration for voice pipelines.

  This module defines the configuration structures for text-to-speech (TTS)
  and speech-to-text (STT) models, as well as the overall pipeline configuration.

  ## Example

      config = %Codex.Voice.Config{
        workflow_name: "Customer Support Voice Agent",
        tts_settings: %Codex.Voice.Config.TTSSettings{
          voice: :nova,
          speed: 1.0
        },
        stt_settings: %Codex.Voice.Config.STTSettings{
          language: "en"
        }
      }

  ## Voices

  OpenAI provides the following TTS voices:
  - `:alloy` - Neutral and balanced
  - `:ash` - Warm and conversational
  - `:coral` - Clear and articulate
  - `:echo` - Soft and thoughtful
  - `:fable` - Expressive and dramatic
  - `:onyx` - Deep and authoritative
  - `:nova` - Friendly and upbeat
  - `:sage` - Calm and measured
  - `:shimmer` - Bright and energetic
  """

  alias __MODULE__.{STTSettings, TTSSettings}

  @typedoc """
  Available TTS voice options.
  """
  @type voice :: :alloy | :ash | :coral | :echo | :fable | :onyx | :nova | :sage | :shimmer

  defstruct [
    :model_provider,
    :workflow_name,
    :group_id,
    :trace_metadata,
    :stt_settings,
    :tts_settings,
    tracing_disabled: false,
    trace_include_sensitive_data: true,
    trace_include_sensitive_audio_data: false
  ]

  @type t :: %__MODULE__{
          model_provider: module() | nil,
          tracing_disabled: boolean(),
          trace_include_sensitive_data: boolean(),
          trace_include_sensitive_audio_data: boolean(),
          workflow_name: String.t() | nil,
          group_id: String.t() | nil,
          trace_metadata: map() | nil,
          stt_settings: STTSettings.t() | nil,
          tts_settings: TTSSettings.t() | nil
        }

  @doc """
  Create a new voice pipeline configuration.

  ## Options

  - `:model_provider` - The voice model provider module to use
  - `:tracing_disabled` - Whether to disable tracing (default: false)
  - `:trace_include_sensitive_data` - Include sensitive data in traces (default: true)
  - `:trace_include_sensitive_audio_data` - Include audio data in traces (default: false)
  - `:workflow_name` - Name for tracing purposes
  - `:group_id` - Grouping ID to link traces from the same conversation
  - `:trace_metadata` - Additional metadata to include with traces
  - `:stt_settings` - STT settings struct or keyword list
  - `:tts_settings` - TTS settings struct or keyword list

  ## Examples

      iex> config = Codex.Voice.Config.new(workflow_name: "Support Agent")
      iex> config.workflow_name
      "Support Agent"
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    stt_settings =
      case Keyword.get(opts, :stt_settings, %STTSettings{}) do
        %STTSettings{} = settings -> settings
        keyword when is_list(keyword) -> STTSettings.new(keyword)
      end

    tts_settings =
      case Keyword.get(opts, :tts_settings, %TTSSettings{}) do
        %TTSSettings{} = settings -> settings
        keyword when is_list(keyword) -> TTSSettings.new(keyword)
      end

    %__MODULE__{
      model_provider: Keyword.get(opts, :model_provider),
      tracing_disabled: Keyword.get(opts, :tracing_disabled, false),
      trace_include_sensitive_data: Keyword.get(opts, :trace_include_sensitive_data, true),
      trace_include_sensitive_audio_data:
        Keyword.get(opts, :trace_include_sensitive_audio_data, false),
      workflow_name: Keyword.get(opts, :workflow_name),
      group_id: Keyword.get(opts, :group_id),
      trace_metadata: Keyword.get(opts, :trace_metadata),
      stt_settings: stt_settings,
      tts_settings: tts_settings
    }
  end
end
