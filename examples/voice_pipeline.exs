#!/usr/bin/env mix run

# Voice Pipeline Example
#
# Demonstrates the non-realtime voice pipeline for STT -> Workflow -> TTS.
# Uses a real audio file (test/fixtures/audio/voice_sample.wav) for input.
# Saves received audio to /tmp/codex_voice_response.pcm
#
# Audio formats:
# - Input:  16-bit PCM, 24kHz, mono (WAV file)
# - Output: 16-bit PCM, 24kHz, mono (saved to /tmp)
#
# To play the output: aplay -f S16_LE -r 24000 -c 1 /tmp/codex_voice_response.pcm
#
# Usage:
#   mix run examples/voice_pipeline.exs

defmodule VoicePipelineExample do
  @moduledoc """
  Example demonstrating the voice pipeline with real audio.
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

  @output_audio_path "/tmp/codex_voice_response.pcm"

  def run do
    IO.puts("=== Voice Pipeline Example ===\n")

    # Voice auth follows Codex.Auth precedence.
    unless Codex.Auth.api_key() do
      IO.puts(
        "Error: no API key found (CODEX_API_KEY, auth.json OPENAI_API_KEY, or OPENAI_API_KEY)"
      )

      System.halt(1)
    end

    # Load real audio from test fixture
    audio_file_path = Path.join([__DIR__, "..", "test", "fixtures", "audio", "voice_sample.wav"])

    audio_data =
      case File.read(audio_file_path) do
        {:ok, wav_data} ->
          IO.puts("[OK] Loaded audio file: #{byte_size(wav_data)} bytes")
          wav_data

        {:error, reason} ->
          IO.puts("[Error] Could not load #{audio_file_path}: #{inspect(reason)}")
          System.halt(1)
      end

    # Initialize output file
    File.write!(@output_audio_path, "")
    IO.puts("[OK] Output audio will be saved to: #{@output_audio_path}")

    # Create a simple workflow that echoes input
    workflow =
      SimpleWorkflow.new(
        fn text ->
          IO.puts("\n[Transcribed] #{text}")
          ["You said: #{text}. How can I help you with that?"]
        end,
        greeting: "Hello! I'm ready to listen."
      )

    IO.puts("[OK] Created workflow with greeting: #{workflow.greeting}")

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

    IO.puts("[OK] Pipeline created")
    IO.puts("  STT Model: #{pipeline.stt_model.model}")
    IO.puts("  TTS Model: #{pipeline.tts_model.model}")
    IO.puts("  TTS Voice: #{config.tts_settings.voice}")

    # Create audio input from WAV file
    # Note: AudioInput accepts WAV data directly - it will be sent as WAV to OpenAI
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

    IO.puts("\n[OK] Pipeline completed!")
    IO.puts("Total audio output: #{total_audio_bytes} bytes")

    # Show output file info and playback instructions
    output_size = File.stat!(@output_audio_path).size

    IO.puts("""

    Audio saved to: #{@output_audio_path}
    Output file size: #{output_size} bytes

    To play the response audio:
      aplay -f S16_LE -r 24000 -c 1 #{@output_audio_path}

    Or convert to WAV:
      sox -t raw -r 24000 -b 16 -c 1 -e signed-integer #{@output_audio_path} /tmp/response.wav
    """)
  end

  defp handle_event(%VoiceStreamEventAudio{data: data}, acc) when is_binary(data) do
    # Append audio to output file
    File.write!(@output_audio_path, data, [:append])
    IO.write(".")
    acc + byte_size(data)
  end

  defp handle_event(%VoiceStreamEventAudio{data: nil}, acc) do
    IO.puts("\n[Audio] End of audio segment")
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
end

VoicePipelineExample.run()
