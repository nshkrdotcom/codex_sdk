#!/usr/bin/env mix run

# Voice with Agent Example
#
# Demonstrates using a Codex Agent with the voice pipeline.
# Uses a real audio file (test/fixtures/audio/voice_sample.wav) for input.
# Saves received audio to /tmp/codex_voice_agent.pcm
#
# Audio formats:
# - Input:  16-bit PCM, 24kHz, mono (WAV file)
# - Output: 16-bit PCM, 24kHz, mono (saved to /tmp)
#
# To play the output: aplay -f S16_LE -r 24000 -c 1 /tmp/codex_voice_agent.pcm
#
# Usage:
#   mix run examples/voice_with_agent.exs

defmodule VoiceWithAgentExample do
  @moduledoc """
  Example demonstrating voice pipelines with Codex Agents using real audio.
  """

  alias Codex.Agent
  alias Codex.Voice.AgentWorkflow
  alias Codex.Voice.Config
  alias Codex.Voice.Config.TTSSettings
  alias Codex.Voice.Events.VoiceStreamEventAudio
  alias Codex.Voice.Events.VoiceStreamEventLifecycle
  alias Codex.Voice.Events.VoiceStreamEventError
  alias Codex.Voice.Input.AudioInput
  alias Codex.Voice.Pipeline
  alias Codex.Voice.Result

  @output_audio_path "/tmp/codex_voice_agent.pcm"

  def run do
    IO.puts("=== Voice with Agent Example ===\n")

    # Voice auth accepts Codex.Auth precedence and OPENAI_API_KEY.
    unless fetch_api_key() do
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

    # Create an agent with instructions
    {:ok, agent} =
      Agent.new(
        name: "CustomerServiceAgent",
        model: "gpt-4o",
        instructions: """
        You are a customer service agent for an e-commerce company.
        Help customers with their orders. Be friendly and professional.
        Keep responses concise since this is a voice interaction.
        """
      )

    IO.puts("[OK] Created agent: #{agent.name}")
    IO.puts("  Model: #{agent.model}")

    # Create workflow from agent with context
    context = %{
      customer_id: "CUST-12345",
      session_start: DateTime.utc_now()
    }

    workflow = AgentWorkflow.new(agent, context: context)

    IO.puts("\nWorkflow context:")
    IO.puts("  customer_id: #{context.customer_id}")
    IO.puts("  session_start: #{context.session_start}")

    # Create pipeline configuration
    config = %Config{
      workflow_name: "CustomerServiceDemo",
      tts_settings: %TTSSettings{
        voice: :nova,
        speed: 1.0
      }
    }

    # Create pipeline
    pipeline =
      Pipeline.new(
        workflow: workflow,
        config: config
      )

    IO.puts("\n[OK] Pipeline created")
    IO.puts("  STT Model: #{pipeline.stt_model.model}")
    IO.puts("  TTS Model: #{pipeline.tts_model.model}")

    # Create audio input from WAV file
    audio = AudioInput.new(audio_data)

    IO.puts("\nRunning voice pipeline...")

    # Pipeline.run always returns {:ok, result} - errors are delivered as events
    {:ok, result} = Pipeline.run(pipeline, audio)

    process_results(result)
  end

  defp process_results(result) do
    {audio_bytes, turns} =
      result
      |> Result.stream()
      |> Enum.reduce({0, 0}, fn event, {bytes, turns} ->
        handle_event(event, bytes, turns)
      end)

    IO.puts("\n[OK] Pipeline Complete")
    IO.puts("  Total audio output: #{audio_bytes} bytes")
    IO.puts("  Total turns: #{turns}")

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

  defp handle_event(%VoiceStreamEventAudio{data: data}, bytes, turns) when is_binary(data) do
    # Append audio to output file
    File.write!(@output_audio_path, data, [:append])
    IO.write(".")
    {bytes + byte_size(data), turns}
  end

  defp handle_event(%VoiceStreamEventAudio{data: nil}, bytes, turns) do
    {bytes, turns}
  end

  defp handle_event(%VoiceStreamEventLifecycle{event: :turn_started}, bytes, turns) do
    IO.puts("\n[Turn started]")
    {bytes, turns}
  end

  defp handle_event(%VoiceStreamEventLifecycle{event: :turn_ended}, bytes, turns) do
    IO.puts("\n[Turn ended]")
    {bytes, turns + 1}
  end

  defp handle_event(%VoiceStreamEventLifecycle{event: :session_ended}, bytes, turns) do
    IO.puts("\n[Session ended]")
    {bytes, turns}
  end

  defp handle_event(%VoiceStreamEventError{error: error}, bytes, turns) do
    IO.puts("\n[Error] #{inspect(error)}")
    {bytes, turns}
  end

  defp handle_event(_event, bytes, turns) do
    {bytes, turns}
  end

  defp fetch_api_key, do: Codex.Auth.direct_api_key()
end

VoiceWithAgentExample.run()
