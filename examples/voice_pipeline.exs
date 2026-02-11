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

  def main do
    case run() do
      :ok ->
        :ok

      {:skip, reason} ->
        IO.puts("SKIPPED: #{reason}")

      {:error, reason} ->
        IO.puts("[Error] #{inspect(reason)}")
        System.halt(1)
    end
  end

  def run do
    IO.puts("=== Voice Pipeline Example ===\n")

    # Voice auth accepts Codex.Auth precedence and OPENAI_API_KEY.
    unless fetch_api_key() do
      {:error, "no API key found (CODEX_API_KEY, auth.json OPENAI_API_KEY, or OPENAI_API_KEY)"}
    else
      with {:ok, audio_data} <- load_fixture_audio(),
           :ok <- initialize_output_file() do
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
    end
  end

  defp stream_results(result) do
    stats =
      result
      |> Result.stream()
      |> Enum.reduce(
        %{audio_bytes: 0, error_count: 0, session_ended?: false, insufficient_quota?: false},
        fn event, acc ->
          handle_event(event, acc)
        end
      )

    if stats.insufficient_quota? do
      {:skip, "insufficient_quota"}
    else
      if stats.error_count > 0 and not stats.session_ended? do
        {:error, :voice_pipeline_failed}
      else
        IO.puts("\n[OK] Pipeline completed!")
        IO.puts("Total audio output: #{stats.audio_bytes} bytes")

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

        :ok
      end
    end
  end

  defp load_fixture_audio do
    audio_file_path = Path.join([__DIR__, "..", "test", "fixtures", "audio", "voice_sample.wav"])

    case File.read(audio_file_path) do
      {:ok, wav_data} ->
        IO.puts("[OK] Loaded audio file: #{byte_size(wav_data)} bytes")
        {:ok, wav_data}

      {:error, reason} ->
        {:error, {:audio_fixture_read_failed, reason}}
    end
  end

  defp initialize_output_file do
    File.write!(@output_audio_path, "")
    IO.puts("[OK] Output audio will be saved to: #{@output_audio_path}")
    :ok
  end

  defp handle_event(%VoiceStreamEventAudio{data: data}, stats) when is_binary(data) do
    # Append audio to output file
    File.write!(@output_audio_path, data, [:append])
    IO.write(".")
    %{stats | audio_bytes: stats.audio_bytes + byte_size(data)}
  end

  defp handle_event(%VoiceStreamEventAudio{data: nil}, stats) do
    IO.puts("\n[Audio] End of audio segment")
    stats
  end

  defp handle_event(%VoiceStreamEventLifecycle{event: :session_ended}, stats) do
    IO.puts("[Lifecycle] session_ended")
    %{stats | session_ended?: true}
  end

  defp handle_event(%VoiceStreamEventLifecycle{event: event}, stats) do
    IO.puts("[Lifecycle] #{event}")
    stats
  end

  defp handle_event(%VoiceStreamEventError{error: error}, stats) do
    IO.puts("[Error] #{inspect(error)}")

    %{
      stats
      | error_count: stats.error_count + 1,
        insufficient_quota?: stats.insufficient_quota? or insufficient_quota_error?(error)
    }
  end

  defp handle_event(_event, stats), do: stats

  defp insufficient_quota_error?(error) do
    error
    |> inspect(limit: :infinity)
    |> String.downcase()
    |> String.contains?("insufficient_quota")
  end

  defp fetch_api_key, do: Codex.Auth.direct_api_key()
end

VoicePipelineExample.main()
