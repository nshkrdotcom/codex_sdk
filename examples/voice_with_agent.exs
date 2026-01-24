#!/usr/bin/env mix run

# Voice with Agent Example
#
# Demonstrates using a Codex Agent with the voice pipeline.
#
# Usage:
#   mix run examples/voice_with_agent.exs

defmodule VoiceWithAgentExample do
  @moduledoc """
  Example demonstrating voice pipelines with Codex Agents.
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

  def run do
    IO.puts("=== Voice with Agent Example ===\n")

    # Check for API key
    unless System.get_env("OPENAI_API_KEY") do
      IO.puts("Error: OPENAI_API_KEY environment variable not set")
      System.halt(1)
    end

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

    IO.puts("Created agent: #{agent.name}")
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

    IO.puts("\nPipeline created")
    IO.puts("  STT Model: #{pipeline.stt_model.model}")
    IO.puts("  TTS Model: #{pipeline.tts_model.model}")

    # Simulate voice input (in real usage, this would be actual recorded audio)
    audio = AudioInput.new(generate_sample_audio())

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

    IO.puts("\n[Pipeline Complete]")
    IO.puts("  Total audio output: #{audio_bytes} bytes")
    IO.puts("  Total turns: #{turns}")
  end

  defp handle_event(%VoiceStreamEventAudio{data: data}, bytes, turns) when is_binary(data) do
    # In a real application, you would play this audio
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

  # Generate sample silence audio (1 second at 24kHz, 16-bit mono)
  defp generate_sample_audio do
    :binary.copy(<<0, 0>>, 24_000)
  end
end

VoiceWithAgentExample.run()
