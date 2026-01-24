#!/usr/bin/env mix run

# Live Realtime Voice Demo
#
# This example demonstrates real-time voice interaction using
# the OpenAI Realtime API.
#
# Prerequisites:
#   - OPENAI_API_KEY environment variable set
#   - Audio input device available (for live demo)
#
# Usage:
#   mix run examples/live_realtime_voice.exs

defmodule LiveRealtimeVoiceDemo do
  @moduledoc """
  Demonstrates live realtime voice interaction.
  """

  alias Codex.Realtime
  alias Codex.Realtime.Events

  def run do
    IO.puts("=== Live Realtime Voice Demo ===\n")

    # Check for API key
    unless System.get_env("OPENAI_API_KEY") do
      IO.puts("Error: OPENAI_API_KEY environment variable not set")
      System.halt(1)
    end

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

    IO.puts("Starting realtime session...")

    # Start the session
    case Realtime.run(agent) do
      {:ok, session} ->
        IO.puts("Session started! Session PID: #{inspect(session)}")

        # Subscribe to events
        Realtime.subscribe(session, self())

        # Start the event loop
        event_loop(session)

      {:error, reason} ->
        IO.puts("Failed to start session: #{inspect(reason)}")
    end
  end

  defp event_loop(session) do
    receive do
      # Session events
      {:session_event, %Events.AgentStartEvent{agent: agent}} ->
        IO.puts("\n[Agent] Session started with: #{agent.name}")
        event_loop(session)

      {:session_event, %Events.AgentEndEvent{}} ->
        IO.puts("\n[Agent] Session ended")
        :ok

      {:session_event, %Events.AudioEvent{}} ->
        # Audio received - in a real app, play this
        IO.write(".")
        event_loop(session)

      {:session_event, %Events.AudioEndEvent{}} ->
        IO.puts("\n[Audio] Audio segment complete")
        event_loop(session)

      {:session_event, %Events.ToolStartEvent{tool: tool}} ->
        IO.puts("\n[Tool] Calling: #{inspect(tool)}")
        event_loop(session)

      {:session_event, %Events.ToolEndEvent{tool: tool, output: output}} ->
        IO.puts("[Tool] #{inspect(tool)} completed: #{inspect(output)}")
        event_loop(session)

      {:session_event, %Events.HandoffEvent{from_agent: from, to_agent: to}} ->
        IO.puts("\n[Handoff] #{from.name} -> #{to.name}")
        event_loop(session)

      {:session_event, %Events.ErrorEvent{error: error}} ->
        IO.puts("\n[Error] #{inspect(error)}")
        event_loop(session)

      {:session_event, %Events.HistoryAddedEvent{item: item}} ->
        IO.puts("\n[History] Added: #{inspect(item.__struct__)}")
        event_loop(session)

      {:session_event, event} ->
        IO.puts("\n[Event] #{inspect(event.__struct__)}")
        event_loop(session)

      other ->
        IO.puts("\n[Unknown] #{inspect(other)}")
        event_loop(session)
    after
      60_000 ->
        IO.puts("\n[Timeout] No activity for 60 seconds, ending session")
        Realtime.close(session)
    end
  end
end

LiveRealtimeVoiceDemo.run()
