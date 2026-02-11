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
  @moduledoc false

  alias Codex.Realtime
  alias Codex.Realtime.Config.RunConfig
  alias Codex.Realtime.Config.SessionModelSettings
  alias Codex.Realtime.Config.TurnDetectionConfig
  alias Codex.Realtime.Events

  @output_audio_path "/tmp/codex_realtime_basic.pcm"

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
    IO.puts("=== Basic Realtime Session Example ===\n")

    # Realtime auth accepts Codex.Auth precedence and OPENAI_API_KEY.
    unless fetch_api_key() do
      return_error(
        "no API key found (CODEX_API_KEY, auth.json OPENAI_API_KEY, or OPENAI_API_KEY)"
      )
    else
      with {:ok, audio_pcm_data} <- load_fixture_audio(),
           :ok <- initialize_output_file(),
           {:ok, session} <- start_session() do
        Realtime.subscribe(session, self())

        result =
          try do
            Process.sleep(500)

            case run_text_demo(session) do
              :ok -> run_audio_demo(session, audio_pcm_data)
              {:skip, _} = skip -> skip
            end
          after
            safe_close(session)
          end

        case result do
          {:ok, stats} ->
            show_output_info(stats)
            :ok

          other ->
            other
        end
      else
        {:error, reason} -> maybe_skip_quota(reason)
      end
    end
  end

  defp load_fixture_audio do
    audio_file_path = Path.join([__DIR__, "..", "test", "fixtures", "audio", "voice_sample.wav"])

    case File.read(audio_file_path) do
      {:ok, wav_data} ->
        # Strip WAV header (44 bytes) to get raw PCM
        <<_header::binary-size(44), pcm_data::binary>> = wav_data
        IO.puts("[OK] Loaded audio file: #{byte_size(pcm_data)} bytes of PCM data")
        {:ok, pcm_data}

      {:error, reason} ->
        {:error, {:audio_fixture_read_failed, reason}}
    end
  end

  defp initialize_output_file do
    File.write!(@output_audio_path, "")
    IO.puts("[OK] Output audio will be saved to: #{@output_audio_path}")
    :ok
  end

  defp start_session do
    agent =
      Realtime.agent(
        name: "BasicAssistant",
        instructions: "You are a helpful assistant. Keep responses brief and conversational."
      )

    config = %RunConfig{
      model_settings: %SessionModelSettings{
        voice: "alloy",
        turn_detection: %TurnDetectionConfig{
          type: :semantic_vad,
          eagerness: :medium
        }
      }
    }

    IO.puts("[OK] Created agent: #{agent.name}")
    IO.puts("[OK] Configured session:")
    IO.puts("  Voice: #{config.model_settings.voice}")
    IO.puts("  Turn detection: #{config.model_settings.turn_detection.type}")
    IO.puts("\nStarting session...")

    case Realtime.run(agent, config: config) do
      {:ok, session} ->
        IO.puts("[OK] Session started!")
        {:ok, session}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp run_text_demo(session) do
    IO.puts("\n--- Demo 1: Text input ---")
    IO.puts(">>> Sending: Hello! Can you hear me?")
    Realtime.send_message(session, "Hello! Can you hear me?")

    case handle_events(5_000) do
      %{insufficient_quota?: true} -> {:skip, "insufficient_quota"}
      _stats -> :ok
    end
  end

  defp run_audio_demo(session, audio_pcm_data) do
    IO.puts("\n--- Demo 2: Audio input (voice_sample.wav) ---")
    send_audio(session, audio_pcm_data)

    case handle_events(8_000) do
      %{insufficient_quota?: true} ->
        {:skip, "insufficient_quota"}

      stats ->
        IO.puts("\n[OK] Session complete")
        {:ok, stats}
    end
  end

  defp send_audio(session, audio_data) do
    # 4800 bytes = 100ms at 24kHz, 16-bit mono
    chunk_size = 4_800
    full_chunks = for <<chunk::binary-size(chunk_size) <- audio_data>>, do: chunk
    remaining_size = rem(byte_size(audio_data), chunk_size)

    chunks =
      if remaining_size > 0 do
        last_chunk =
          binary_part(audio_data, byte_size(audio_data) - remaining_size, remaining_size)

        full_chunks ++ [last_chunk]
      else
        full_chunks
      end

    total_chunks = length(chunks)
    IO.puts(">>> Sending #{total_chunks} audio chunks (committing on final chunk)...")

    chunks
    |> Enum.with_index(1)
    |> Enum.each(fn {chunk, idx} ->
      Realtime.send_audio(session, chunk, commit: idx == total_chunks)
      IO.write(".")
      Process.sleep(100)
    end)

    IO.puts(" [done]")
  end

  defp handle_events(timeout) do
    start_time = System.monotonic_time(:millisecond)

    do_handle_events(start_time, timeout, %{
      audio_delta_count: 0,
      audio_bytes: 0,
      error_count: 0,
      event_counts: %{},
      insufficient_quota?: false
    })
  end

  defp do_handle_events(start_time, timeout, stats) do
    if stats.insufficient_quota? do
      stats
    else
      remaining = timeout - (System.monotonic_time(:millisecond) - start_time)

      if remaining <= 0 do
        IO.puts("\n[Timeout] Event handling complete")
        stats
      else
        receive do
          {:session_event, %Events.AgentStartEvent{} = event} ->
            IO.puts("\n[Event] Agent started")
            do_handle_events(start_time, timeout, increment_event(stats, event))

          {:session_event, %Events.AgentEndEvent{} = event} ->
            IO.puts("\n[Event] Agent turn ended")
            do_handle_events(start_time, timeout, increment_event(stats, event))

          {:session_event, %Events.AudioEvent{audio: audio} = event} ->
            updated =
              stats
              |> increment_event(event)
              |> Map.update!(:audio_delta_count, &(&1 + 1))
              |> Map.update!(:audio_bytes, &(&1 + byte_size(audio.data || <<>>)))

            if is_binary(audio.data) and audio.data != <<>> do
              File.write!(@output_audio_path, audio.data, [:append])
            end

            IO.write(".")
            do_handle_events(start_time, timeout, updated)

          {:session_event, %Events.ErrorEvent{error: error} = event} ->
            updated =
              stats
              |> increment_event(event)
              |> Map.update!(:error_count, &(&1 + 1))
              |> Map.put(:insufficient_quota?, insufficient_quota_error?(error))

            if updated.insufficient_quota? do
              IO.puts("\n[Error] insufficient_quota from API")
            else
              IO.puts("\n[Error] #{inspect(error)}")
            end

            do_handle_events(start_time, timeout, updated)

          {:session_event, event} ->
            do_handle_events(start_time, timeout, increment_event(stats, event))
        after
          remaining ->
            IO.puts("\n[Timeout] Event handling complete")
            stats
        end
      end
    end
  end

  defp increment_event(stats, event) do
    name = event.__struct__ |> Module.split() |> List.last()
    counts = Map.update(stats.event_counts, name, 1, &(&1 + 1))
    %{stats | event_counts: counts}
  end

  defp show_output_info(stats) do
    output_size = File.stat!(@output_audio_path).size

    if output_size == 0 do
      IO.puts("""

      [Debug] No output audio was written.
        audio delta events: #{stats.audio_delta_count}
        bytes in audio deltas: #{stats.audio_bytes}
        error events: #{stats.error_count}
        event summary: #{inspect(stats.event_counts)}
      """)
    end

    IO.puts("""

    Audio saved to: #{@output_audio_path}
    Output file size: #{output_size} bytes

    To play the response audio:
      aplay -f S16_LE -r 24000 -c 1 #{@output_audio_path}

    Or convert to WAV:
      sox -t raw -r 24000 -b 16 -c 1 -e signed-integer #{@output_audio_path} /tmp/response.wav
    """)
  end

  defp safe_close(session) do
    Realtime.close(session)
    IO.puts("[OK] Session closed")
  rescue
    _ -> :ok
  end

  defp maybe_skip_quota(reason) do
    if insufficient_quota_error?(reason) do
      {:skip, "insufficient_quota"}
    else
      {:error, reason}
    end
  end

  defp insufficient_quota_error?(error) do
    error
    |> inspect(limit: :infinity)
    |> String.downcase()
    |> String.contains?("insufficient_quota")
  end

  defp return_error(message), do: {:error, message}

  defp fetch_api_key, do: Codex.Auth.direct_api_key()
end

RealtimeBasicExample.main()
