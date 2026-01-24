#!/usr/bin/env mix run

# Basic Realtime Example
#
# Demonstrates the simplest realtime session setup.
#
# Usage:
#   mix run examples/realtime_basic.exs

defmodule BasicRealtimeExample do
  @moduledoc """
  Basic example demonstrating realtime session setup.
  """

  alias Codex.Realtime
  alias Codex.Realtime.Config.RunConfig
  alias Codex.Realtime.Config.SessionModelSettings
  alias Codex.Realtime.Config.TurnDetectionConfig
  alias Codex.Realtime.Events

  def run do
    IO.puts("=== Basic Realtime Example ===\n")

    # Check for API key
    unless System.get_env("OPENAI_API_KEY") do
      IO.puts("Error: OPENAI_API_KEY environment variable not set")
      System.halt(1)
    end

    # Create a simple agent
    agent =
      Realtime.agent(
        name: "SimpleAssistant",
        instructions: "You are a helpful assistant. Keep responses brief."
      )

    # Configure session options with model settings
    # Note: Supported voices are: alloy, ash, ballad, coral, echo, sage, shimmer, verse, marin, cedar
    config = %RunConfig{
      model_settings: %SessionModelSettings{
        voice: "alloy",
        turn_detection: %TurnDetectionConfig{
          type: :semantic_vad,
          eagerness: :medium
        }
      }
    }

    IO.puts("Creating realtime session...")
    IO.puts("  Agent: #{agent.name}")
    IO.puts("  Model: #{agent.model}")
    IO.puts("  Voice: #{config.model_settings.voice}")
    IO.puts("  Turn detection: #{config.model_settings.turn_detection.type}")

    case Realtime.run(agent, config: config) do
      {:ok, session} ->
        IO.puts("\nSession created successfully!")
        IO.puts("Session PID: #{inspect(session)}")

        # Subscribe to receive events
        Realtime.subscribe(session, self())

        # In a real application, you would:
        # 1. Capture audio from microphone
        # 2. Send audio to session: Realtime.send_audio(session, audio_bytes)
        # 3. Handle received audio events
        # 4. Play received audio through speakers

        # For demo, send a text message instead
        IO.puts("\nSending text message...")
        Realtime.send_message(session, "Hello! Can you briefly introduce yourself?")

        # Handle events for a short time
        handle_events(session, 10_000)

        # Close the session
        IO.puts("\nClosing session...")
        Realtime.close(session)
        IO.puts("Session closed.")

      {:error, reason} ->
        IO.puts("Failed to create session: #{inspect(reason)}")
    end
  end

  defp handle_events(session, timeout) do
    start_time = System.monotonic_time(:millisecond)

    receive do
      {:session_event, %Events.AgentStartEvent{}} ->
        IO.puts("[Event] Agent started")
        remaining = timeout - (System.monotonic_time(:millisecond) - start_time)

        if remaining > 0 do
          handle_events(session, remaining)
        end

      {:session_event, %Events.AgentEndEvent{}} ->
        IO.puts("[Event] Agent turn ended")
        remaining = timeout - (System.monotonic_time(:millisecond) - start_time)

        if remaining > 0 do
          handle_events(session, remaining)
        end

      {:session_event, %Events.AudioEvent{}} ->
        IO.write(".")
        remaining = timeout - (System.monotonic_time(:millisecond) - start_time)

        if remaining > 0 do
          handle_events(session, remaining)
        end

      {:session_event, %Events.ErrorEvent{error: error}} ->
        IO.puts("\n[Error] #{inspect(error)}")

      {:session_event, event} ->
        IO.puts("[Event] #{inspect(event.__struct__)}")
        remaining = timeout - (System.monotonic_time(:millisecond) - start_time)

        if remaining > 0 do
          handle_events(session, remaining)
        end
    after
      timeout ->
        IO.puts("\n[Timeout] Event handling complete")
    end
  end
end

BasicRealtimeExample.run()
