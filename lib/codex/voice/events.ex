defmodule Codex.Voice.Events do
  @moduledoc """
  Voice stream event types for the voice pipeline.

  These events are emitted by the `VoicePipeline` during voice processing:

  - `VoiceStreamEventAudio` - Audio data from the pipeline
  - `VoiceStreamEventLifecycle` - Lifecycle events (turn started/ended, session ended)
  - `VoiceStreamEventError` - Error events

  ## Example

      for event <- VoicePipeline.stream(input) do
        case event do
          %VoiceStreamEventAudio{data: data} ->
            play_audio(data)

          %VoiceStreamEventLifecycle{event: :turn_ended} ->
            IO.puts("Turn ended")

          %VoiceStreamEventError{error: error} ->
            Logger.error("Voice error: \#{inspect(error)}")
        end
      end
  """

  defmodule VoiceStreamEventAudio do
    @moduledoc """
    Audio data event from the voice pipeline.

    The `data` field contains PCM audio bytes, or `nil` to signal the end
    of an audio segment.
    """

    defstruct [:data, type: :voice_stream_event_audio]

    @type t :: %__MODULE__{
            type: :voice_stream_event_audio,
            data: binary() | nil
          }
  end

  defmodule VoiceStreamEventLifecycle do
    @moduledoc """
    Lifecycle event from the voice pipeline.

    Events include:
    - `:turn_started` - A new turn (user speech segment) has started
    - `:turn_ended` - The current turn has ended
    - `:session_ended` - The entire session has ended
    """

    defstruct [:event, type: :voice_stream_event_lifecycle]

    @type lifecycle_event :: :turn_started | :turn_ended | :session_ended

    @type t :: %__MODULE__{
            type: :voice_stream_event_lifecycle,
            event: lifecycle_event()
          }
  end

  defmodule VoiceStreamEventError do
    @moduledoc """
    Error event from the voice pipeline.

    Contains the exception that occurred during processing.
    """

    defstruct [:error, type: :voice_stream_event_error]

    @type t :: %__MODULE__{
            type: :voice_stream_event_error,
            error: Exception.t()
          }
  end

  @typedoc """
  A voice stream event from the pipeline.
  """
  @type t :: VoiceStreamEventAudio.t() | VoiceStreamEventLifecycle.t() | VoiceStreamEventError.t()

  @doc """
  Create an audio event.

  ## Examples

      iex> event = Codex.Voice.Events.audio(<<1, 2, 3>>)
      iex> event.type
      :voice_stream_event_audio
      iex> event.data
      <<1, 2, 3>>
  """
  @spec audio(binary() | nil) :: VoiceStreamEventAudio.t()
  def audio(data), do: %VoiceStreamEventAudio{data: data}

  @doc """
  Create a lifecycle event.

  ## Examples

      iex> event = Codex.Voice.Events.lifecycle(:turn_ended)
      iex> event.type
      :voice_stream_event_lifecycle
      iex> event.event
      :turn_ended
  """
  @spec lifecycle(VoiceStreamEventLifecycle.lifecycle_event()) :: VoiceStreamEventLifecycle.t()
  def lifecycle(event) when event in [:turn_started, :turn_ended, :session_ended] do
    %VoiceStreamEventLifecycle{event: event}
  end

  @doc """
  Create an error event.

  ## Examples

      iex> error = %RuntimeError{message: "test"}
      iex> event = Codex.Voice.Events.error(error)
      iex> event.type
      :voice_stream_event_error
  """
  @spec error(Exception.t()) :: VoiceStreamEventError.t()
  def error(exception), do: %VoiceStreamEventError{error: exception}
end
