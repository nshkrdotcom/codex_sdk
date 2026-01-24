#!/usr/bin/env mix run

# Multi-Turn Voice Conversation Example
#
# Demonstrates multi-turn voice conversations with streaming input.
#
# Usage:
#   mix run examples/voice_multi_turn.exs

defmodule VoiceMultiTurnExample do
  @moduledoc """
  Example demonstrating multi-turn voice conversations.
  """

  alias Codex.Voice.Config
  alias Codex.Voice.Config.TTSSettings
  alias Codex.Voice.Events.VoiceStreamEventAudio
  alias Codex.Voice.Events.VoiceStreamEventLifecycle
  alias Codex.Voice.Events.VoiceStreamEventError
  alias Codex.Voice.Input.StreamedAudioInput
  alias Codex.Voice.Pipeline
  alias Codex.Voice.Result
  alias Codex.Voice.SimpleWorkflow

  def run do
    IO.puts("=== Multi-Turn Voice Example ===\n")

    # Check for API key
    unless System.get_env("OPENAI_API_KEY") do
      IO.puts("Error: OPENAI_API_KEY environment variable not set")
      System.halt(1)
    end

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

    IO.puts("Created multi-turn workflow")

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

    IO.puts("Pipeline ready for streaming input")
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

    # Simulate sending audio chunks
    simulate_conversation(streamed_input)

    # Wait for output to complete
    Task.await(output_task, :infinity)
  end

  defp simulate_conversation(input) do
    IO.puts("[Simulating conversation...]\n")

    # Simulate first turn - greeting
    IO.puts("--- Turn 1 ---")
    send_audio_chunk(input, "Hello, how are you?")
    Process.sleep(1_500)

    # Simulate second turn - weather question
    IO.puts("\n--- Turn 2 ---")
    send_audio_chunk(input, "What's the weather like today?")
    Process.sleep(1_500)

    # Simulate third turn - goodbye
    IO.puts("\n--- Turn 3 ---")
    send_audio_chunk(input, "Thank you, goodbye!")
    Process.sleep(1_000)

    # Close the stream
    StreamedAudioInput.close(input)
    IO.puts("\n[Stream closed]")
  end

  defp send_audio_chunk(input, _simulated_text) do
    # In real usage, this would be actual audio data from a microphone
    # For demo, we're simulating with placeholder silence
    # 100ms of audio at 24kHz, 16-bit mono
    audio_chunk = :binary.copy(<<0, 0>>, 4_800)
    StreamedAudioInput.add(input, audio_chunk)
  end

  defp stream_output(result) do
    {audio_bytes, turns} =
      result
      |> Result.stream()
      |> Enum.reduce({0, 0}, fn event, {bytes, turns} ->
        handle_output_event(event, bytes, turns)
      end)

    IO.puts("\n[Session Complete]")
    IO.puts("  Total audio bytes: #{audio_bytes}")
    IO.puts("  Total turns: #{turns}")
  end

  defp handle_output_event(%VoiceStreamEventAudio{data: data}, bytes, turns)
       when is_binary(data) do
    IO.write(".")
    {bytes + byte_size(data), turns}
  end

  defp handle_output_event(%VoiceStreamEventAudio{data: nil}, bytes, turns) do
    {bytes, turns}
  end

  defp handle_output_event(%VoiceStreamEventLifecycle{event: :turn_started}, bytes, turns) do
    IO.puts("\n[Turn #{turns + 1} started]")
    {bytes, turns}
  end

  defp handle_output_event(%VoiceStreamEventLifecycle{event: :turn_ended}, bytes, turns) do
    IO.puts("\n[Turn #{turns + 1} completed]")
    {bytes, turns + 1}
  end

  defp handle_output_event(%VoiceStreamEventLifecycle{event: :session_ended}, bytes, turns) do
    IO.puts("\n[Session ended]")
    {bytes, turns}
  end

  defp handle_output_event(%VoiceStreamEventError{error: error}, bytes, turns) do
    IO.puts("\n[Error] #{inspect(error)}")
    {bytes, turns}
  end

  defp handle_output_event(_event, bytes, turns) do
    {bytes, turns}
  end
end

VoiceMultiTurnExample.run()
