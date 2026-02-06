defmodule Codex.Voice.Result do
  @moduledoc """
  Streamed audio result from a voice pipeline.

  This module provides the output type for voice pipelines. Results are streamed
  as events that can be consumed incrementally, allowing for real-time audio
  playback while the pipeline is still processing.

  ## Usage

      {:ok, result} = Pipeline.run(pipeline, audio_input)

      result
      |> Result.stream()
      |> Enum.each(fn event ->
        case event do
          %VoiceStreamEventAudio{data: data} ->
            play_audio(data)

          %VoiceStreamEventLifecycle{event: :turn_ended} ->
            IO.puts("Turn completed")

          %VoiceStreamEventLifecycle{event: :session_ended} ->
            IO.puts("Session ended")

          %VoiceStreamEventError{error: error} ->
            Logger.error("Error: \#{inspect(error)}")
        end
      end)

  ## Architecture

  The result uses an Agent-backed queue to buffer events between the pipeline
  producer and the consumer. The pipeline runs in a Task and pushes events
  to the queue, while `stream/1` consumes them.
  """

  alias Codex.StreamQueue
  alias Codex.Voice.Config
  alias Codex.Voice.Config.TTSSettings
  alias Codex.Voice.Events

  defstruct [:tts_model, :tts_settings, :config, :queue, :task, total_output_text: ""]

  @type t :: %__MODULE__{
          tts_model: struct(),
          tts_settings: TTSSettings.t(),
          config: Config.t(),
          queue: pid(),
          task: term() | nil,
          total_output_text: String.t()
        }

  @doc """
  Create a new streamed result.

  ## Parameters

  - `tts_model` - The TTS model to use for converting text to audio
  - `tts_settings` - Settings for the TTS model
  - `config` - Voice pipeline configuration

  ## Examples

      tts_model = OpenAITTS.new()
      tts_settings = TTSSettings.new(voice: :nova)
      config = Config.new()

      result = Result.new(tts_model, tts_settings, config)
  """
  @spec new(struct(), TTSSettings.t(), Config.t()) :: t()
  def new(tts_model, tts_settings, config) do
    {:ok, queue} = StreamQueue.start_link()

    %__MODULE__{
      tts_model: tts_model,
      tts_settings: tts_settings || %TTSSettings{},
      config: config || %Config{},
      queue: queue,
      total_output_text: ""
    }
  end

  @doc """
  Stream events from the result.

  Returns a `Stream` that yields `VoiceStreamEvent` structs as they become
  available. The stream completes when the pipeline signals completion with
  a `session_ended` lifecycle event.

  Note: If the queue is empty and the pipeline is still producing, this will
  poll with a 10ms delay. For high-performance use cases, consider using
  a different consumption strategy.

  ## Examples

      result
      |> Result.stream()
      |> Enum.each(&handle_event/1)
  """
  @spec stream(t()) :: Enumerable.t()
  def stream(%__MODULE__{queue: queue}), do: StreamQueue.stream(queue)

  # Internal functions for pipeline

  @doc false
  @spec set_task(t(), term()) :: t()
  def set_task(%__MODULE__{} = result, task) do
    %{result | task: task}
  end

  @doc false
  @spec add_text(t(), String.t()) :: t()
  def add_text(%__MODULE__{} = result, text) when is_binary(text) and byte_size(text) > 0 do
    # Convert text to audio and queue events
    audio_stream =
      result.tts_model.__struct__.run(result.tts_model, text, result.tts_settings)

    Enum.each(audio_stream, fn chunk ->
      event = Events.audio(chunk)
      StreamQueue.push(result.queue, event)
    end)

    # Track total output text
    %{result | total_output_text: result.total_output_text <> text}
  end

  def add_text(%__MODULE__{} = result, _text), do: result

  @doc false
  @spec turn_started(t()) :: :ok
  def turn_started(%__MODULE__{queue: queue}) do
    event = Events.lifecycle(:turn_started)
    StreamQueue.push(queue, event)
  end

  @doc false
  @spec turn_done(t()) :: :ok
  def turn_done(%__MODULE__{queue: queue}) do
    event = Events.lifecycle(:turn_ended)
    StreamQueue.push(queue, event)
  end

  @doc false
  @spec done(t()) :: :ok
  def done(%__MODULE__{queue: queue}) do
    event = Events.lifecycle(:session_ended)
    StreamQueue.push(queue, event)
    StreamQueue.close(queue)
  end

  @doc false
  @spec add_error(t(), term()) :: :ok
  def add_error(%__MODULE__{queue: queue}, error) do
    event = Events.error(wrap_error(error))
    StreamQueue.push(queue, event)
    StreamQueue.close(queue)
  end

  @spec wrap_error(term()) :: Exception.t()
  defp wrap_error(%{__exception__: true} = exception), do: exception

  defp wrap_error({:error, reason}), do: %RuntimeError{message: inspect(reason)}
  defp wrap_error(reason), do: %RuntimeError{message: inspect(reason)}
end
