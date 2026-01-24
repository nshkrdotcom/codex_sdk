defmodule Codex.Voice do
  @moduledoc """
  Voice pipeline for speech-to-speech AI interactions.

  This module provides a non-realtime voice pipeline that orchestrates:
  1. Speech-to-text (STT) - Transcribe audio input
  2. Workflow processing - Generate text responses
  3. Text-to-speech (TTS) - Synthesize audio output

  ## Quick Start

      # Create a workflow
      workflow = Codex.Voice.SimpleWorkflow.new(fn text ->
        ["You said: \#{text}"]
      end)

      # Create pipeline
      pipeline = Codex.Voice.Pipeline.new(workflow: workflow)

      # Run with audio input
      audio = Codex.Voice.Input.AudioInput.new(audio_bytes)
      {:ok, result} = Codex.Voice.Pipeline.run(pipeline, audio)

      # Stream output events
      result
      |> Codex.Voice.Result.stream()
      |> Enum.each(fn event ->
        case event.type do
          :voice_stream_event_audio -> play(event.data)
          :voice_stream_event_lifecycle -> handle(event.event)
          :voice_stream_event_error -> log(event.error)
        end
      end)

  ## Components

  - `Codex.Voice.Pipeline` - Main pipeline orchestrator
  - `Codex.Voice.Workflow` - Workflow behaviour
  - `Codex.Voice.SimpleWorkflow` - Function-based workflow
  - `Codex.Voice.AgentWorkflow` - Agent-based workflow
  - `Codex.Voice.Input` - Audio input types
  - `Codex.Voice.Result` - Streamed result

  ## Convenience Functions

  This module provides convenience functions to create and run voice pipelines
  without needing to import submodules directly:

      # Run a complete pipeline in one call
      {:ok, result} = Codex.Voice.run(audio,
        workflow: my_workflow,
        config: %Codex.Voice.Config{
          tts_settings: %{voice: :nova}
        }
      )

      # Create audio inputs
      audio = Codex.Voice.audio_input(binary_data)
      streamed = Codex.Voice.streamed_input()
  """

  alias Codex.Voice.Config
  alias Codex.Voice.Input.AudioInput
  alias Codex.Voice.Input.StreamedAudioInput
  alias Codex.Voice.Pipeline
  alias Codex.Voice.Result
  alias Codex.Voice.SimpleWorkflow

  @doc """
  Create and run a voice pipeline.

  This is a convenience function that creates a pipeline and runs it in one
  step. For more control, use `Codex.Voice.Pipeline` directly.

  ## Options

  - `:workflow` - The workflow to use (required)
  - `:stt_model` - STT model name or instance
  - `:tts_model` - TTS model name or instance
  - `:config` - Pipeline configuration

  ## Returns

  - `{:ok, result}` - A `Result` struct that can be streamed for events

  ## Example

      workflow = Codex.Voice.SimpleWorkflow.new(fn text ->
        ["You said: \#{text}"]
      end)

      {:ok, result} = Codex.Voice.run(audio,
        workflow: workflow,
        config: %Codex.Voice.Config{
          tts_settings: %Codex.Voice.Config.TTSSettings{voice: :nova}
        }
      )

      # Stream output events
      for event <- Codex.Voice.Result.stream(result) do
        IO.inspect(event)
      end
  """
  @spec run(AudioInput.t() | StreamedAudioInput.t(), keyword()) :: {:ok, Result.t()}
  def run(audio, opts) do
    pipeline = Pipeline.new(opts)
    Pipeline.run(pipeline, audio)
  end

  @doc """
  Create an audio input from binary data.

  ## Options

  - `:frame_rate` - Sample rate in Hz (default: 24000)
  - `:sample_width` - Bytes per sample (default: 2)
  - `:channels` - Number of audio channels (default: 1)

  ## Example

      audio = Codex.Voice.audio_input(File.read!("recording.pcm"))
  """
  @spec audio_input(binary(), keyword()) :: AudioInput.t()
  def audio_input(data, opts \\ []) do
    AudioInput.new(data, opts)
  end

  @doc """
  Create a streamed audio input.

  Use this for multi-turn conversations where you want to push audio
  chunks incrementally.

  ## Example

      input = Codex.Voice.streamed_input()

      # Push chunks from another process
      spawn(fn ->
        for chunk <- audio_source do
          Codex.Voice.Input.StreamedAudioInput.add(input, chunk)
        end
        Codex.Voice.Input.StreamedAudioInput.close(input)
      end)

      # Run the pipeline
      {:ok, result} = Codex.Voice.run(input, workflow: my_workflow)
  """
  @spec streamed_input() :: StreamedAudioInput.t()
  def streamed_input do
    StreamedAudioInput.new()
  end

  @doc """
  Create a simple workflow from a function.

  The function should take a transcription string and return an enumerable
  of response text chunks.

  ## Options

  - `:greeting` - Optional greeting to send when the workflow starts

  ## Example

      workflow = Codex.Voice.simple_workflow(fn text ->
        ["You said: \#{text}"]
      end, greeting: "Hello! How can I help?")
  """
  @spec simple_workflow((String.t() -> Enumerable.t()), keyword()) :: SimpleWorkflow.t()
  def simple_workflow(handler, opts \\ []) do
    SimpleWorkflow.new(handler, opts)
  end

  @doc """
  Create a new pipeline configuration.

  ## Options

  - `:workflow_name` - Name for tracing
  - `:stt_settings` - STT configuration
  - `:tts_settings` - TTS configuration
  - `:model_provider` - Custom model provider module
  - `:trace_include_sensitive_data` - Include sensitive data in traces
  - `:trace_include_sensitive_audio_data` - Include audio data in traces

  ## Example

      config = Codex.Voice.config(
        workflow_name: "Customer Support",
        tts_settings: Codex.Voice.Config.TTSSettings.new(voice: :nova)
      )
  """
  @spec config(keyword()) :: Config.t()
  def config(opts \\ []) do
    Config.new(opts)
  end
end
