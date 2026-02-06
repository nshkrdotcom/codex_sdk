#!/usr/bin/env mix run

# Realtime Handoffs Example
#
# Demonstrates agent-to-agent handoffs in realtime sessions.
#
# Usage:
#   mix run examples/realtime_handoffs.exs

defmodule RealtimeHandoffsExample do
  @moduledoc """
  Example demonstrating agent handoffs in realtime sessions.
  """

  alias Codex.Realtime
  alias Codex.Realtime.Events

  def run do
    IO.puts("=== Realtime Handoffs Example ===\n")

    # Realtime auth follows Codex.Auth precedence.
    unless Codex.Auth.api_key() do
      IO.puts(
        "Error: no API key found (CODEX_API_KEY, auth.json OPENAI_API_KEY, or OPENAI_API_KEY)"
      )

      System.halt(1)
    end

    # Create specialized agents
    tech_support =
      Realtime.agent(
        name: "TechSupport",
        handoff_description: "Handles technical support issues and troubleshooting",
        instructions: """
        You are a technical support specialist. Help users with technical issues.
        Be patient and thorough in your explanations.
        Keep responses concise for voice interaction.
        """
      )

    billing_agent =
      Realtime.agent(
        name: "BillingAgent",
        handoff_description: "Handles billing inquiries and account questions",
        instructions: """
        You handle billing and account inquiries.
        Be professional and helpful with financial matters.
        Keep responses concise for voice interaction.
        """
      )

    # Create the greeter agent with handoffs
    greeter =
      Realtime.agent(
        name: "Greeter",
        instructions: """
        You are a friendly greeter. Welcome users and ask what they need help with.
        If they need technical support, hand off to the TechSupport agent.
        If they need billing help, hand off to the BillingAgent.
        Be brief and friendly.
        """,
        handoffs: [tech_support, billing_agent]
      )

    IO.puts("Created agent network:")
    IO.puts("  - #{greeter.name} (entry point)")
    IO.puts("    -> #{tech_support.name}: #{tech_support.handoff_description}")
    IO.puts("    -> #{billing_agent.name}: #{billing_agent.handoff_description}")

    IO.puts("\nStarting realtime session...")

    case Realtime.run(greeter) do
      {:ok, session} ->
        IO.puts("Session started with #{greeter.name}")
        Realtime.subscribe(session, self())

        # Send a message that should trigger a handoff
        IO.puts("\nSending message: I have a technical problem with my software")
        Realtime.send_message(session, "I have a technical problem with my software")

        # Handle events
        handle_events(session, 30_000)

        IO.puts("\nClosing session...")
        Realtime.close(session)

      {:error, reason} ->
        IO.puts("Failed: #{inspect(reason)}")
    end
  end

  defp handle_events(session, timeout) do
    start_time = System.monotonic_time(:millisecond)

    receive do
      {:session_event, %Events.HandoffEvent{from_agent: from, to_agent: to}} ->
        IO.puts("\n[Handoff] #{from.name} -> #{to.name}")
        remaining = timeout - (System.monotonic_time(:millisecond) - start_time)
        if remaining > 0, do: handle_events(session, remaining)

      {:session_event, %Events.AgentStartEvent{agent: agent}} ->
        IO.puts("\n[Agent] Now speaking with: #{agent.name}")
        remaining = timeout - (System.monotonic_time(:millisecond) - start_time)
        if remaining > 0, do: handle_events(session, remaining)

      {:session_event, %Events.AgentEndEvent{agent: agent}} ->
        IO.puts("[Agent] #{agent.name} turn ended")
        remaining = timeout - (System.monotonic_time(:millisecond) - start_time)
        if remaining > 0, do: handle_events(session, remaining)

      {:session_event, %Events.AudioEvent{}} ->
        IO.write(".")
        remaining = timeout - (System.monotonic_time(:millisecond) - start_time)
        if remaining > 0, do: handle_events(session, remaining)

      {:session_event, %Events.HistoryAddedEvent{}} ->
        remaining = timeout - (System.monotonic_time(:millisecond) - start_time)
        if remaining > 0, do: handle_events(session, remaining)

      {:session_event, %Events.ErrorEvent{error: error}} ->
        IO.puts("\n[Error] #{inspect(error)}")

      {:session_event, event} ->
        IO.puts("[Event] #{inspect(event.__struct__)}")
        remaining = timeout - (System.monotonic_time(:millisecond) - start_time)
        if remaining > 0, do: handle_events(session, remaining)
    after
      timeout ->
        IO.puts("\n[Timeout] Event handling complete")
    end
  end
end

RealtimeHandoffsExample.run()
