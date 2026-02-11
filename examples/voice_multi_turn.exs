#!/usr/bin/env mix run

# Multi-Turn Voice Conversation Example
#
# Demonstrates multi-turn voice conversations with streaming input.
# Uses a real audio file (test/fixtures/audio/voice_sample.wav) for input.
# Saves received audio to /tmp/codex_voice_multi_turn.pcm
#
# Audio formats:
# - Input:  16-bit PCM, 24kHz, mono (WAV file, streamed in chunks)
# - Output: 16-bit PCM, 24kHz, mono (saved to /tmp)
#
# To play the output: aplay -f S16_LE -r 24000 -c 1 /tmp/codex_voice_multi_turn.pcm
#
# Usage:
#   mix run examples/voice_multi_turn.exs

defmodule VoiceMultiTurnExample do
  @moduledoc """
  Example demonstrating multi-turn voice conversations with real audio.
  """

  alias Codex.Voice.Config
  alias Codex.Voice.Config.TTSSettings
  alias Codex.Voice.Events.VoiceStreamEventAudio
  alias Codex.Voice.Events.VoiceStreamEventLifecycle
  alias Codex.Voice.Events.VoiceStreamEventError
  alias Codex.Voice.Input.StreamedAudioInput
  alias Codex.Voice.Models.OpenAITTS
  alias Codex.Voice.Pipeline
  alias Codex.Voice.Result
  alias Codex.Voice.SimpleWorkflow

  @output_audio_path "/tmp/codex_voice_multi_turn.pcm"
  @output_wait_timeout_ms 60_000

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
    IO.puts("=== Multi-Turn Voice Example ===\n")

    # Voice auth accepts Codex.Auth precedence and OPENAI_API_KEY.
    unless fetch_api_key() do
      {:error, "no API key found (CODEX_API_KEY, auth.json OPENAI_API_KEY, or OPENAI_API_KEY)"}
    else
      with {:ok, audio_data} <- load_fixture_audio(),
           :ok <- initialize_output_file(),
           :ok <- preflight_tts_quota_check() do
        # Create a conversational workflow
        workflow =
          SimpleWorkflow.new(
            fn text ->
              IO.puts("\n[User said] #{text}")

              response =
                cond do
                  String.contains?(String.downcase(text), "hello") ->
                    "Hello! Nice to meet you. What would you like to talk about?"

                  String.contains?(String.downcase(text), "weather") ->
                    "The weather is looking great today! Is there anything else you'd like to know?"

                  String.contains?(String.downcase(text), "goodbye") ->
                    "Goodbye! It was nice talking with you!"

                  true ->
                    "I heard you say: #{text}. Tell me more!"
                end

              IO.puts("[Response] #{response}")
              [response]
            end,
            greeting: "Hello! I'm ready to have a conversation with you."
          )

        IO.puts("[OK] Created multi-turn workflow")

        # Create pipeline configuration
        config = %Config{
          workflow_name: "MultiTurnDemo",
          tts_settings: %TTSSettings{
            voice: :echo,
            speed: 1.0
          }
        }

        # Create the pipeline
        pipeline =
          Pipeline.new(
            workflow: workflow,
            config: config
          )

        IO.puts("[OK] Pipeline ready for streaming input")
        IO.puts("Starting multi-turn session...\n")

        # Create streaming input
        streamed_input = StreamedAudioInput.new()

        # Start the pipeline with streaming input
        # Pipeline.run always returns {:ok, result} - errors are delivered as events
        {:ok, result} = Pipeline.run(pipeline, streamed_input)

        # Spawn a task to handle the output stream
        output_task =
          Task.async(fn ->
            stream_output(result)
          end)

        # Stream real audio in chunks (simulating multiple turns)
        stream_audio_turns(streamed_input, audio_data)

        output_result =
          case Task.yield(output_task, @output_wait_timeout_ms) ||
                 Task.shutdown(output_task, :brutal_kill) do
            {:ok, stats} ->
              evaluate_stream_result(stats)

            {:exit, reason} ->
              {:error, {:output_stream_exited, reason}}

            nil ->
              {:error, {:output_timeout, @output_wait_timeout_ms}}
          end

        show_output_info()
        output_result
      end
    end
  end

  defp stream_audio_turns(input, audio_data) do
    IO.puts("[Streaming audio in 3 turns...]\n")

    # Split audio into 3 parts for 3 turns
    total_size = byte_size(audio_data)
    chunk_size = div(total_size, 3)

    # Turn 1
    IO.puts("--- Turn 1 ---")
    turn1_data = binary_part(audio_data, 0, chunk_size)
    stream_audio_chunk(input, turn1_data)
    Process.sleep(2000)

    # Turn 2
    IO.puts("\n--- Turn 2 ---")
    turn2_data = binary_part(audio_data, chunk_size, chunk_size)
    stream_audio_chunk(input, turn2_data)
    Process.sleep(2000)

    # Turn 3
    IO.puts("\n--- Turn 3 ---")
    remaining = total_size - 2 * chunk_size
    turn3_data = binary_part(audio_data, 2 * chunk_size, remaining)
    stream_audio_chunk(input, turn3_data)
    Process.sleep(1500)

    # Close the stream
    StreamedAudioInput.close(input)
    IO.puts("\n[Stream closed]")
  end

  defp stream_audio_chunk(input, data) do
    # Send audio in small chunks (4800 bytes = 100ms at 24kHz, 16-bit mono)
    chunk_size = 4800
    chunks = for <<chunk::binary-size(chunk_size) <- data>>, do: chunk

    # Handle any remaining partial chunk
    remaining_size = rem(byte_size(data), chunk_size)

    chunks =
      if remaining_size > 0 do
        last_chunk = binary_part(data, byte_size(data) - remaining_size, remaining_size)
        chunks ++ [last_chunk]
      else
        chunks
      end

    IO.puts("Sending #{length(chunks)} audio chunks...")

    for chunk <- chunks do
      StreamedAudioInput.add(input, chunk)
      IO.write(".")
      Process.sleep(50)
    end

    IO.puts(" [done]")
  end

  defp stream_output(result) do
    stats =
      result
      |> Result.stream()
      |> Enum.reduce(new_stats(), fn event, stats ->
        handle_output_event(event, stats)
      end)

    stats
  end

  defp handle_output_event(%VoiceStreamEventAudio{data: data}, stats)
       when is_binary(data) do
    # Append audio to output file
    File.write!(@output_audio_path, data, [:append])
    IO.write(".")
    %{stats | audio_bytes: stats.audio_bytes + byte_size(data)}
  end

  defp handle_output_event(%VoiceStreamEventAudio{data: nil}, stats) do
    stats
  end

  defp handle_output_event(%VoiceStreamEventLifecycle{event: :turn_started}, stats) do
    IO.puts("\n[Turn #{stats.turns + 1} started]")
    stats
  end

  defp handle_output_event(%VoiceStreamEventLifecycle{event: :turn_ended}, stats) do
    IO.puts("\n[Turn #{stats.turns + 1} completed]")
    %{stats | turns: stats.turns + 1}
  end

  defp handle_output_event(%VoiceStreamEventLifecycle{event: :session_ended}, stats) do
    IO.puts("\n[Session ended]")
    %{stats | session_ended?: true}
  end

  defp handle_output_event(%VoiceStreamEventError{error: error}, stats) do
    IO.puts("\n[Error] #{inspect(error)}")

    %{
      stats
      | error_count: stats.error_count + 1,
        insufficient_quota?: stats.insufficient_quota? or insufficient_quota_error?(error)
    }
  end

  defp handle_output_event(_event, stats) do
    stats
  end

  defp load_fixture_audio do
    audio_file_path = Path.join([__DIR__, "..", "test", "fixtures", "audio", "voice_sample.wav"])

    case File.read(audio_file_path) do
      {:ok, wav_data} ->
        # Strip WAV header (44 bytes) to get raw PCM for streaming
        <<_header::binary-size(44), pcm_data::binary>> = wav_data
        IO.puts("[OK] Loaded audio file: #{byte_size(pcm_data)} bytes of PCM data")
        {:ok, pcm_data}

      {:error, reason} ->
        {:error, {:audio_fixture_read_failed, reason}}
    end
  end

  defp preflight_tts_quota_check do
    model = OpenAITTS.new()
    settings = %TTSSettings{voice: :echo, speed: 1.0}

    try do
      _ = model |> OpenAITTS.run("Preflight quota check.", settings) |> Enum.take(1)
      :ok
    rescue
      error ->
        if insufficient_quota_error?(error) do
          {:skip, "insufficient_quota"}
        else
          {:error, {:tts_preflight_failed, error}}
        end
    end
  end

  defp initialize_output_file do
    File.write!(@output_audio_path, "")
    IO.puts("[OK] Output audio will be saved to: #{@output_audio_path}")
    :ok
  end

  defp new_stats do
    %{
      audio_bytes: 0,
      turns: 0,
      error_count: 0,
      session_ended?: false,
      insufficient_quota?: false
    }
  end

  defp evaluate_stream_result(%{insufficient_quota?: true}) do
    {:skip, "insufficient_quota"}
  end

  defp evaluate_stream_result(%{error_count: errors, session_ended?: false})
       when errors > 0 do
    {:error, :voice_multi_turn_failed}
  end

  defp evaluate_stream_result(%{session_ended?: false}) do
    {:error, :voice_multi_turn_incomplete}
  end

  defp evaluate_stream_result(stats) do
    IO.puts("\n[Session Complete]")
    IO.puts("  Total audio bytes: #{stats.audio_bytes}")
    IO.puts("  Total turns: #{stats.turns}")
    :ok
  end

  defp show_output_info do
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

  defp insufficient_quota_error?(error) do
    normalized =
      error
      |> inspect(limit: :infinity)
      |> String.downcase()

    String.contains?(normalized, "insufficient_quota") or
      String.contains?(normalized, "api_error, 429")
  end

  defp fetch_api_key, do: Codex.Auth.direct_api_key()
end

VoiceMultiTurnExample.main()
