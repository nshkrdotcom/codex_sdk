#!/usr/bin/env mix run

# Voice Pipeline Example
#
# Demonstrates the non-realtime voice pipeline for STT -> Workflow -> TTS.
#
# Usage:
#   mix run examples/voice_pipeline.exs

defmodule VoicePipelineExample do
  @moduledoc """
  Example demonstrating the voice pipeline.
  """

  alias Codex.Voice.Config
  alias Codex.Voice.Config.TTSSettings
  alias Codex.Voice.Events.VoiceStreamEventAudio
  alias Codex.Voice.Events.VoiceStreamEventLifecycle
  alias Codex.Voice.Events.VoiceStreamEventError
  alias Codex.Voice.Input.AudioInput
  alias Codex.Voice.Pipeline
  alias Codex.Voice.Result
  alias Codex.Voice.SimpleWorkflow

  def run do
    IO.puts("=== Voice Pipeline Example ===\n")

    # Check for API key
    unless System.get_env("OPENAI_API_KEY") do
      IO.puts("Error: OPENAI_API_KEY environment variable not set")
      System.halt(1)
    end

    # Create a simple workflow that echoes input
    workflow =
      SimpleWorkflow.new(
        fn text ->
          IO.puts("[Transcribed] #{text}")
          ["You said: #{text}. How can I help you with that?"]
        end,
        greeting: "Hello! I'm ready to listen."
      )

    IO.puts("Created workflow with greeting: #{workflow.greeting}")

    # Create pipeline configuration
    config = %Config{
      workflow_name: "VoicePipelineDemo",
      tts_settings: %TTSSettings{
        voice: :nova,
        speed: 1.0
      }
    }

    # Create the pipeline
    pipeline =
      Pipeline.new(
        workflow: workflow,
        config: config
      )

    IO.puts("Pipeline created")
    IO.puts("  STT Model: #{pipeline.stt_model.model}")
    IO.puts("  TTS Model: #{pipeline.tts_model.model}")
    IO.puts("  TTS Voice: #{config.tts_settings.voice}")

    # Generate sample audio (silence for demo purposes)
    # In real usage, this would be actual recorded audio bytes
    audio_data = generate_sample_audio()

    audio =
      AudioInput.new(audio_data,
        frame_rate: 24_000,
        sample_width: 2,
        channels: 1
      )

    IO.puts("\nProcessing audio input (#{byte_size(audio_data)} bytes)...")

    # Pipeline.run always returns {:ok, result} - errors are delivered as events
    {:ok, result} = Pipeline.run(pipeline, audio)

    IO.puts("Pipeline started, streaming results...")
    stream_results(result)
  end

  defp stream_results(result) do
    total_audio_bytes =
      result
      |> Result.stream()
      |> Enum.reduce(0, fn event, acc ->
        handle_event(event, acc)
      end)

    IO.puts("\nPipeline completed!")
    IO.puts("Total audio output: #{total_audio_bytes} bytes")
  end

  defp handle_event(%VoiceStreamEventAudio{data: data}, acc) when is_binary(data) do
    IO.write("[Audio] Received #{byte_size(data)} bytes\n")
    acc + byte_size(data)
  end

  defp handle_event(%VoiceStreamEventAudio{data: nil}, acc) do
    IO.puts("[Audio] End of audio segment")
    acc
  end

  defp handle_event(%VoiceStreamEventLifecycle{event: event}, acc) do
    IO.puts("[Lifecycle] #{event}")
    acc
  end

  defp handle_event(%VoiceStreamEventError{error: error}, acc) do
    IO.puts("[Error] #{inspect(error)}")
    acc
  end

  defp handle_event(_event, acc), do: acc

  # Generate sample silence audio for demo purposes
  # 1 second of silence at 24kHz, 16-bit mono
  defp generate_sample_audio do
    :binary.copy(<<0, 0>>, 24_000)
  end
end

VoicePipelineExample.run()
