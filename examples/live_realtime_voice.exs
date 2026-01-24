#!/usr/bin/env mix run

# Live Realtime Voice Demo
#
# This example demonstrates real-time voice interaction using
# the OpenAI Realtime API with actual audio input and output.
#
# Uses a real audio file (test/fixtures/audio/voice_sample.wav) for input.
# Saves received audio to /tmp/codex_realtime_response.pcm
#
# Audio formats:
# - Input:  16-bit PCM, 24kHz, mono (from WAV file)
# - Output: 16-bit PCM, 24kHz, mono (saved to /tmp)
#
# To play the output: aplay -f S16_LE -r 24000 -c 1 /tmp/codex_realtime_response.pcm
#
# Prerequisites:
#   - OPENAI_API_KEY environment variable set
#
# Usage:
#   mix run examples/live_realtime_voice.exs

defmodule LiveRealtimeVoiceDemo do
  @moduledoc """
  Demonstrates live realtime voice interaction with real audio.
  """

  alias Codex.Realtime
  alias Codex.Realtime.Events

  @output_audio_path "/tmp/codex_realtime_response.pcm"

  def run do
    IO.puts("=== Live Realtime Voice Demo ===\n")

    # Check for API key
    unless System.get_env("OPENAI_API_KEY") do
      IO.puts("Error: OPENAI_API_KEY environment variable not set")
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

    # Create a realtime agent
    agent =
      Realtime.agent(
        name: "VoiceAssistant",
        instructions: """
        You are a helpful voice assistant. Be concise and natural in your responses.
        Speak clearly and at a moderate pace.
        """,
        model: "gpt-4o-realtime-preview"
      )

    IO.puts("[OK] Created agent: #{agent.name}")
    IO.puts("Starting realtime session...")

    # Start the session
    case Realtime.run(agent) do
      {:ok, session} ->
        IO.puts("[OK] Session started! Session PID: #{inspect(session)}")

        # Subscribe to events
        Realtime.subscribe(session, self())

        # Wait for session setup
        Process.sleep(500)

        # Demo 1: Send text first to get audio response
        IO.puts("\n--- Demo 1: Text prompt with audio response ---")
        prompt = "Say hello in a friendly way!"
        IO.puts(">>> Sending text: #{prompt}")
        Realtime.send_message(session, prompt)

        # Handle events for a bit
        handle_events(session, 5000)

        # Demo 2: Send real audio input
        IO.puts("\n--- Demo 2: Real audio input (voice_sample.wav) ---")
        IO.puts(">>> Sending audio from file...")
        send_audio_in_chunks(session, audio_pcm_data)

        # Handle events for audio response
        handle_events(session, 10000)

        # Demo 3: Another text prompt
        IO.puts("\n--- Demo 3: Follow-up text prompt ---")
        prompt2 = "What did I just say to you?"
        IO.puts(">>> Sending text: #{prompt2}")
        Realtime.send_message(session, prompt2)

        # Handle final events
        handle_events(session, 5000)

        # Close session
        IO.puts("\nClosing session...")
        Realtime.close(session)

        # Show output statistics
        show_output_info()

      {:error, reason} ->
        IO.puts("[Error] Failed to start session: #{inspect(reason)}")
    end
  end

  defp send_audio_in_chunks(session, audio_data) do
    # Send audio in chunks (4800 bytes = 100ms at 24kHz, 16-bit mono)
    chunk_size = 4800
    chunks = for <<chunk::binary-size(chunk_size) <- audio_data>>, do: chunk

    # Handle any remaining partial chunk
    remaining_size = rem(byte_size(audio_data), chunk_size)

    chunks =
      if remaining_size > 0 do
        last_chunk =
          binary_part(audio_data, byte_size(audio_data) - remaining_size, remaining_size)

        chunks ++ [last_chunk]
      else
        chunks
      end

    IO.puts("Sending #{length(chunks)} audio chunks...")

    for chunk <- chunks do
      Realtime.send_audio(session, chunk)
      IO.write(".")
      Process.sleep(100)
    end

    IO.puts(" [#{length(chunks)} chunks sent]")
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
        # Session events
        {:session_event, %Events.AgentStartEvent{agent: agent}} ->
          IO.puts("\n[Agent] Session started with: #{agent.name}")
          do_handle_events(session, start_time, timeout)

        {:session_event, %Events.AgentEndEvent{}} ->
          IO.puts("\n[Agent] Turn ended")
          do_handle_events(session, start_time, timeout)

        {:session_event, %Events.AudioEvent{audio: audio}} ->
          # Save audio to file
          if audio && audio.data do
            File.write!(@output_audio_path, audio.data, [:append])
          end

          IO.write(".")
          do_handle_events(session, start_time, timeout)

        {:session_event, %Events.AudioEndEvent{}} ->
          IO.puts("\n[Audio] Audio segment complete")
          do_handle_events(session, start_time, timeout)

        {:session_event, %Events.ToolStartEvent{tool: tool}} ->
          IO.puts("\n[Tool] Calling: #{inspect(tool)}")
          do_handle_events(session, start_time, timeout)

        {:session_event, %Events.ToolEndEvent{tool: tool, output: output}} ->
          IO.puts("[Tool] #{inspect(tool)} completed: #{inspect(output)}")
          do_handle_events(session, start_time, timeout)

        {:session_event, %Events.HandoffEvent{from_agent: from, to_agent: to}} ->
          IO.puts("\n[Handoff] #{from.name} -> #{to.name}")
          do_handle_events(session, start_time, timeout)

        {:session_event, %Events.ErrorEvent{error: error}} ->
          IO.puts("\n[Error] #{inspect(error)}")
          do_handle_events(session, start_time, timeout)

        {:session_event, %Events.HistoryAddedEvent{item: item}} ->
          IO.puts("\n[History] Added: #{inspect(item.__struct__)}")
          do_handle_events(session, start_time, timeout)

        {:session_event, event} ->
          IO.puts("\n[Event] #{inspect(event.__struct__)}")
          do_handle_events(session, start_time, timeout)

        other ->
          IO.puts("\n[Unknown] #{inspect(other)}")
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

    === Demo Complete ===

    Audio saved to: #{@output_audio_path}
    Output file size: #{output_size} bytes

    To play the response audio:
      aplay -f S16_LE -r 24000 -c 1 #{@output_audio_path}

    Or convert to WAV:
      sox -t raw -r 24000 -b 16 -c 1 -e signed-integer #{@output_audio_path} /tmp/response.wav
    """)
  end
end

LiveRealtimeVoiceDemo.run()
