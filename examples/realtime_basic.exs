#!/usr/bin/env mix run

# Basic Realtime Session Example
#
# Demonstrates basic setup and usage of the Realtime API
# with both text and audio input/output.
#
# Uses a real audio file (test/fixtures/audio/voice_sample.wav) for input.
# Saves received audio to /tmp/codex_realtime_basic.pcm
#
# Audio formats:
# - Input:  16-bit PCM, 24kHz, mono (from WAV file)
# - Output: 16-bit PCM, 24kHz, mono (saved to /tmp)
#
# To play the output: aplay -f S16_LE -r 24000 -c 1 /tmp/codex_realtime_basic.pcm
#
# Usage:
#   mix run examples/realtime_basic.exs

defmodule RealtimeBasicExample do
  @moduledoc """
  Example demonstrating basic realtime session setup with real audio.
  """

  alias Codex.Realtime
  alias Codex.Realtime.Config.RunConfig
  alias Codex.Realtime.Config.SessionModelSettings
  alias Codex.Realtime.Config.TurnDetectionConfig
  alias Codex.Realtime.Events

  @output_audio_path "/tmp/codex_realtime_basic.pcm"

  def run do
    IO.puts("=== Basic Realtime Session Example ===\n")

    # Realtime auth follows Codex.Auth precedence.
    unless Codex.Auth.api_key() do
      IO.puts(
        "Error: no API key found (CODEX_API_KEY, auth.json OPENAI_API_KEY, or OPENAI_API_KEY)"
      )

      System.halt(1)
    end

    # Load real audio from test fixture
    audio_file_path = Path.join([__DIR__, "..", "test", "fixtures", "audio", "voice_sample.wav"])

    audio_pcm_data =
      case File.read(audio_file_path) do
        {:ok, wav_data} ->
          # Strip WAV header (44 bytes) to get raw PCM
          <<_header::binary-size(44), pcm_data::binary>> = wav_data
          IO.puts("[OK] Loaded audio file: #{byte_size(pcm_data)} bytes of PCM data")
          pcm_data

        {:error, reason} ->
          IO.puts("[Error] Could not load #{audio_file_path}: #{inspect(reason)}")
          System.halt(1)
      end

    # Initialize output file
    File.write!(@output_audio_path, "")
    IO.puts("[OK] Output audio will be saved to: #{@output_audio_path}")

    # Create a simple realtime agent
    agent =
      Realtime.agent(
        name: "BasicAssistant",
        instructions: "You are a helpful assistant. Keep responses brief and conversational."
      )

    IO.puts("[OK] Created agent: #{agent.name}")

    # Configure session with voice and turn detection settings
    config = %RunConfig{
      model_settings: %SessionModelSettings{
        voice: "alloy",
        turn_detection: %TurnDetectionConfig{
          type: :semantic_vad,
          eagerness: :medium
        }
      }
    }

    IO.puts("[OK] Configured session:")
    IO.puts("  Voice: #{config.model_settings.voice}")
    IO.puts("  Turn detection: #{config.model_settings.turn_detection.type}")

    # Start the session
    IO.puts("\nStarting session...")

    case Realtime.run(agent, config: config) do
      {:ok, session} ->
        IO.puts("[OK] Session started!")

        # Subscribe to receive events
        Realtime.subscribe(session, self())

        # Wait for session setup
        Process.sleep(500)

        # Demo 1: Send a text message first
        IO.puts("\n--- Demo 1: Text input ---")
        IO.puts(">>> Sending: Hello! Can you hear me?")
        Realtime.send_message(session, "Hello! Can you hear me?")

        # Collect events for a few seconds
        handle_events(session, 5000)

        # Demo 2: Send real audio
        IO.puts("\n--- Demo 2: Audio input (voice_sample.wav) ---")
        send_audio(session, audio_pcm_data)

        # Collect response events
        handle_events(session, 8000)

        # Check session status
        IO.puts("\n[OK] Session complete")

        # Close the session
        Realtime.close(session)
        IO.puts("[OK] Session closed")

        # Show output info
        show_output_info()

      {:error, reason} ->
        IO.puts("[Error] Failed to start session: #{inspect(reason)}")
    end
  end

  defp send_audio(session, audio_data) do
    # Send audio in chunks (4800 bytes = 100ms at 24kHz, 16-bit mono)
    chunk_size = 4800
    chunks = for <<chunk::binary-size(chunk_size) <- audio_data>>, do: chunk

    # Handle remaining data
    remaining_size = rem(byte_size(audio_data), chunk_size)

    chunks =
      if remaining_size > 0 do
        last_chunk =
          binary_part(audio_data, byte_size(audio_data) - remaining_size, remaining_size)

        chunks ++ [last_chunk]
      else
        chunks
      end

    IO.puts(">>> Sending #{length(chunks)} audio chunks...")

    for chunk <- chunks do
      Realtime.send_audio(session, chunk)
      IO.write(".")
      Process.sleep(100)
    end

    IO.puts(" [done]")
  end

  defp handle_events(session, timeout) do
    start_time = System.monotonic_time(:millisecond)
    do_handle_events(session, start_time, timeout)
  end

  defp do_handle_events(session, start_time, timeout) do
    remaining = timeout - (System.monotonic_time(:millisecond) - start_time)

    if remaining <= 0 do
      IO.puts("\n[Timeout] Event handling complete")
    else
      receive do
        {:session_event, %Events.AgentStartEvent{}} ->
          IO.puts("\n[Event] Agent started")
          do_handle_events(session, start_time, timeout)

        {:session_event, %Events.AgentEndEvent{}} ->
          IO.puts("\n[Event] Agent turn ended")
          do_handle_events(session, start_time, timeout)

        {:session_event, %Events.AudioEvent{audio: audio}} ->
          # Save audio to output file
          if audio && audio.data do
            File.write!(@output_audio_path, audio.data, [:append])
          end

          IO.write(".")
          do_handle_events(session, start_time, timeout)

        {:session_event, %Events.ErrorEvent{error: error}} ->
          IO.puts("\n[Error] #{inspect(error)}")
          do_handle_events(session, start_time, timeout)

        {:session_event, event} ->
          IO.puts("\n[Event] #{inspect(event.__struct__)}")
          do_handle_events(session, start_time, timeout)
      after
        remaining ->
          IO.puts("\n[Timeout] Event handling complete")
      end
    end
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
end

RealtimeBasicExample.run()
