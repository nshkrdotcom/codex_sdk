#!/usr/bin/env mix run

# Realtime with Tools Example
#
# Demonstrates realtime sessions with custom tool definitions.
#
# Note: The realtime API expects tool definitions in a specific format.
# This example shows how to set up tools for realtime agents.
#
# Usage:
#   mix run examples/realtime_tools.exs

defmodule RealtimeToolsExample do
  @moduledoc """
  Example demonstrating realtime agents with tools.

  This example demonstrates how tools work in the realtime context,
  though note that custom function tools require special handling
  for the realtime API's expected format.
  """

  alias Codex.Realtime
  alias Codex.Realtime.Events

  def run do
    IO.puts("=== Realtime Tools Example ===\n")

    # Realtime auth follows Codex.Auth precedence.
    unless Codex.Auth.api_key() do
      IO.puts(
        "Error: no API key found (CODEX_API_KEY, auth.json OPENAI_API_KEY, or OPENAI_API_KEY)"
      )

      System.halt(1)
    end

    # Create agent without custom tools for now
    # The realtime API has specific requirements for tool definitions
    agent =
      Realtime.agent(
        name: "AssistantWithTools",
        instructions: """
        You are a helpful assistant. You can help users with various tasks.
        When asked about weather or time, explain that you would normally use
        tools to get that information, but for this demo we're showing the
        basic realtime interaction.
        """
      )

    IO.puts("Agent created: #{agent.name}")
    IO.puts("Note: Custom function tools require specific format for realtime API")

    IO.puts("\nStarting realtime session...")

    case Realtime.run(agent) do
      {:ok, session} ->
        IO.puts("Session started!")
        Realtime.subscribe(session, self())

        # Send a message
        IO.puts("\nSending message: What's the weather like?")
        Realtime.send_message(session, "What's the weather like?")

        # Handle events
        handle_events(session, 15_000)

        IO.puts("\nClosing session...")
        Realtime.close(session)

      {:error, reason} ->
        IO.puts("Failed: #{inspect(reason)}")
    end

    # Now demonstrate the tool definition format
    IO.puts("\n" <> String.duplicate("-", 50))
    IO.puts("Tool Definition Format for Realtime API:")
    IO.puts(String.duplicate("-", 50))

    tool_definition = %{
      "type" => "function",
      "name" => "get_weather",
      "description" => "Get the current weather for a location",
      "parameters" => %{
        "type" => "object",
        "properties" => %{
          "location" => %{
            "type" => "string",
            "description" => "City name"
          },
          "unit" => %{
            "type" => "string",
            "enum" => ["celsius", "fahrenheit"]
          }
        },
        "required" => ["location"]
      }
    }

    IO.puts("\nExample tool definition:")
    IO.inspect(tool_definition, pretty: true, limit: :infinity)

    IO.puts("\nTo use tools with realtime, configure them in SessionModelSettings.tools")
  end

  defp handle_events(session, timeout) do
    start_time = System.monotonic_time(:millisecond)

    receive do
      {:session_event, %Events.ToolStartEvent{tool: tool, arguments: args}} ->
        IO.puts("\n[Tool Call] #{inspect(tool)}")
        IO.puts("  Arguments: #{args}")
        remaining = timeout - (System.monotonic_time(:millisecond) - start_time)
        if remaining > 0, do: handle_events(session, remaining)

      {:session_event, %Events.ToolEndEvent{tool: tool, output: output}} ->
        IO.puts("[Tool Result] #{inspect(tool)} => #{inspect(output)}")
        remaining = timeout - (System.monotonic_time(:millisecond) - start_time)
        if remaining > 0, do: handle_events(session, remaining)

      {:session_event, %Events.AgentStartEvent{agent: agent}} ->
        IO.puts("[Agent] Started: #{agent.name}")
        remaining = timeout - (System.monotonic_time(:millisecond) - start_time)
        if remaining > 0, do: handle_events(session, remaining)

      {:session_event, %Events.AgentEndEvent{}} ->
        IO.puts("[Agent] Turn ended")
        # Stop processing after agent ends
        :ok

      {:session_event, %Events.AudioEvent{}} ->
        IO.write(".")
        remaining = timeout - (System.monotonic_time(:millisecond) - start_time)
        if remaining > 0, do: handle_events(session, remaining)

      {:session_event, %Events.ErrorEvent{error: error}} ->
        IO.puts("\n[Error] #{inspect(error)}")

      {:session_event, _event} ->
        remaining = timeout - (System.monotonic_time(:millisecond) - start_time)
        if remaining > 0, do: handle_events(session, remaining)
    after
      timeout ->
        IO.puts("\n[Timeout] Event handling complete")
    end
  end
end

RealtimeToolsExample.run()
