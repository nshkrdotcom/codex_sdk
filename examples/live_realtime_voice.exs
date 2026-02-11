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
#   - API key available via CODEX_API_KEY, auth.json OPENAI_API_KEY, or OPENAI_API_KEY
#
# Usage:
#   mix run examples/live_realtime_voice.exs

defmodule LiveRealtimeVoiceDemo do
  @moduledoc false

  alias Codex.Realtime
  alias Codex.Realtime.Config.RunConfig
  alias Codex.Realtime.Config.SessionModelSettings
  alias Codex.Realtime.Config.TurnDetectionConfig
  alias Codex.Realtime.Events

  @output_audio_path "/tmp/codex_realtime_response.pcm"

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
    IO.puts("=== Live Realtime Voice Demo ===\n")

    unless fetch_api_key() do
      {:error, "no API key found (CODEX_API_KEY, auth.json OPENAI_API_KEY, or OPENAI_API_KEY)"}
    else
      with {:ok, audio_pcm_data} <- load_fixture_audio(),
           :ok <- initialize_output_file(),
           {:ok, session} <- start_session() do
        Realtime.subscribe(session, self())

        result =
          try do
            Process.sleep(500)
            run_demos(session, audio_pcm_data)
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
        name: "VoiceAssistant",
        instructions: """
        You are a helpful voice assistant. Be concise and natural in your responses.
        Speak clearly and at a moderate pace.
        """,
        model: "gpt-4o-realtime-preview"
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
    IO.puts("Starting realtime session with voice=#{config.model_settings.voice}...")

    case Realtime.run(agent, config: config) do
      {:ok, session} ->
        IO.puts("[OK] Session started! Session PID: #{inspect(session)}")
        {:ok, session}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp run_demos(session, audio_pcm_data) do
    stats = new_stats()

    IO.puts("\n--- Demo 1: Text prompt with audio response ---")
    prompt = "Say hello in a friendly way!"
    IO.puts(">>> Sending text: #{prompt}")
    Realtime.send_message(session, prompt)

    with {:ok, stats} <- collect_stage_stats(5_000, stats),
         :ok <- run_audio_stage(session, audio_pcm_data),
         {:ok, stats} <- collect_stage_stats(10_000, stats) do
      IO.puts("\n--- Demo 3: Follow-up text prompt ---")
      prompt2 = "What did I just say to you?"
      IO.puts(">>> Sending text: #{prompt2}")
      Realtime.send_message(session, prompt2)

      collect_stage_stats(5_000, stats)
    end
  end

  defp run_audio_stage(session, audio_pcm_data) do
    IO.puts("\n--- Demo 2: Real audio input (voice_sample.wav) ---")
    IO.puts(">>> Sending audio from file...")
    send_audio_in_chunks(session, audio_pcm_data)
    :ok
  end

  defp send_audio_in_chunks(session, audio_data) do
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
    IO.puts("Sending #{total_chunks} audio chunks (commit on final chunk)...")

    chunks
    |> Enum.with_index(1)
    |> Enum.each(fn {chunk, idx} ->
      Realtime.send_audio(session, chunk, commit: idx == total_chunks)
      IO.write(".")
      Process.sleep(100)
    end)

    IO.puts(" [#{total_chunks} chunks sent]")
  end

  defp collect_stage_stats(timeout_ms, accumulated) do
    stage_stats = handle_events(timeout_ms)
    merged = merge_stats(accumulated, stage_stats)

    case merged.skip_reason do
      reason when is_binary(reason) -> {:skip, reason}
      _ -> {:ok, merged}
    end
  end

  defp new_stats do
    %{
      audio_delta_count: 0,
      audio_bytes: 0,
      error_count: 0,
      event_counts: %{},
      skip_reason: nil
    }
  end

  defp merge_stats(left, right) do
    %{
      audio_delta_count: left.audio_delta_count + right.audio_delta_count,
      audio_bytes: left.audio_bytes + right.audio_bytes,
      error_count: left.error_count + right.error_count,
      event_counts: Map.merge(left.event_counts, right.event_counts, fn _k, a, b -> a + b end),
      skip_reason: left.skip_reason || right.skip_reason
    }
  end

  defp handle_events(timeout) do
    start_time = System.monotonic_time(:millisecond)
    do_handle_events(start_time, timeout, new_stats())
  end

  defp do_handle_events(start_time, timeout, stats) do
    if is_binary(stats.skip_reason) do
      stats
    else
      remaining = timeout - (System.monotonic_time(:millisecond) - start_time)

      if remaining <= 0 do
        IO.puts("\n[Timeout] Event handling complete")
        stats
      else
        receive do
          {:session_event, %Events.AgentStartEvent{agent: agent} = event} ->
            IO.puts("\n[Agent] Session started with: #{agent.name}")
            do_handle_events(start_time, timeout, increment_event(stats, event))

          {:session_event, %Events.AgentEndEvent{} = event} ->
            IO.puts("\n[Agent] Turn ended")
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

          {:session_event, %Events.AudioEndEvent{} = event} ->
            IO.puts("\n[Audio] Audio segment complete")
            do_handle_events(start_time, timeout, increment_event(stats, event))

          {:session_event, %Events.ToolStartEvent{tool: tool} = event} ->
            IO.puts("\n[Tool] Calling: #{inspect(tool)}")
            do_handle_events(start_time, timeout, increment_event(stats, event))

          {:session_event, %Events.ToolEndEvent{tool: tool, output: output} = event} ->
            IO.puts("[Tool] #{inspect(tool)} completed: #{inspect(output)}")
            do_handle_events(start_time, timeout, increment_event(stats, event))

          {:session_event, %Events.HandoffEvent{from_agent: from, to_agent: to} = event} ->
            IO.puts("\n[Handoff] #{from.name} -> #{to.name}")
            do_handle_events(start_time, timeout, increment_event(stats, event))

          {:session_event, %Events.ErrorEvent{error: error} = event} ->
            skip_reason = skip_reason_for_error(error)

            updated =
              stats
              |> increment_event(event)
              |> Map.update!(:error_count, &(&1 + 1))
              |> Map.put(:skip_reason, skip_reason)

            if is_binary(skip_reason) do
              IO.puts("\n[Error] #{skip_reason} from API")
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

    === Demo Complete ===

    Audio saved to: #{@output_audio_path}
    Output file size: #{output_size} bytes

    To play the response audio:
      aplay -f S16_LE -r 24000 -c 1 #{@output_audio_path}

    Or convert to WAV:
      sox -t raw -r 24000 -b 16 -c 1 -e signed-integer #{@output_audio_path} /tmp/response.wav
    """)
  end

  defp safe_close(session) do
    IO.puts("\nClosing session...")
    Realtime.close(session)
  rescue
    _ -> :ok
  end

  defp maybe_skip_quota(reason) do
    case skip_reason_for_error(reason) do
      nil -> {:error, reason}
      skip_reason -> {:skip, skip_reason}
    end
  end

  defp skip_reason_for_error(error) do
    normalized =
      error
      |> inspect(limit: :infinity)
      |> String.downcase()

    cond do
      String.contains?(normalized, "insufficient_quota") ->
        "insufficient_quota"

      String.contains?(normalized, "model_not_found") or
          String.contains?(normalized, "do not have access") ->
        "realtime_model_unavailable"

      true ->
        nil
    end
  end

  defp fetch_api_key, do: Codex.Auth.direct_api_key()
end

LiveRealtimeVoiceDemo.main()
