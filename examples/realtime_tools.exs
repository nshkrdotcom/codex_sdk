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

  def main do
    case run() do
      :ok ->
        :ok

      {:skip, reason} ->
        IO.puts("SKIPPED: #{reason}")

      {:error, reason} ->
        IO.puts("Failed: #{inspect(reason)}")
        System.halt(1)
    end
  end

  def run do
    IO.puts("=== Realtime Tools Example ===\n")

    # Realtime auth follows Codex.Auth precedence.
    unless fetch_api_key() do
      {:error, "no API key found (CODEX_API_KEY, auth.json OPENAI_API_KEY, or OPENAI_API_KEY)"}
    else
      # Create agent without custom tools for now.
      # The realtime API has specific requirements for tool definitions.
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

      realtime_result =
        case Realtime.run(agent) do
          {:ok, session} ->
            IO.puts("Session started!")
            Realtime.subscribe(session, self())

            IO.puts("\nSending message: What's the weather like?")
            Realtime.send_message(session, "What's the weather like?")

            stats = handle_events(15_000, %{skip_reason: nil})

            IO.puts("\nClosing session...")
            Realtime.close(session)

            case stats.skip_reason do
              reason when is_binary(reason) -> {:skip, reason}
              _ -> :ok
            end

          {:error, reason} ->
            maybe_skip_quota(reason)
        end

      print_tool_definition()
      realtime_result
    end
  end

  defp handle_events(timeout, stats) do
    started_at = System.monotonic_time(:millisecond)
    do_handle_events(timeout, started_at, stats)
  end

  defp do_handle_events(timeout, started_at, stats) do
    if is_binary(stats.skip_reason) do
      stats
    else
      remaining = timeout - (System.monotonic_time(:millisecond) - started_at)

      if remaining <= 0 do
        IO.puts("\n[Timeout] Event handling complete")
        stats
      else
        receive do
          {:session_event, %Events.ToolStartEvent{tool: tool, arguments: args}} ->
            IO.puts("\n[Tool Call] #{inspect(tool)}")
            IO.puts("  Arguments: #{args}")
            do_handle_events(timeout, started_at, stats)

          {:session_event, %Events.ToolEndEvent{tool: tool, output: output}} ->
            IO.puts("[Tool Result] #{inspect(tool)} => #{inspect(output)}")
            do_handle_events(timeout, started_at, stats)

          {:session_event, %Events.AgentStartEvent{agent: agent}} ->
            IO.puts("[Agent] Started: #{agent.name}")
            do_handle_events(timeout, started_at, stats)

          {:session_event, %Events.AgentEndEvent{}} ->
            IO.puts("[Agent] Turn ended")
            stats

          {:session_event, %Events.AudioEvent{}} ->
            IO.write(".")
            do_handle_events(timeout, started_at, stats)

          {:session_event, %Events.ErrorEvent{error: error}} ->
            case skip_reason_for_error(error) do
              reason when is_binary(reason) ->
                IO.puts("\n[Error] #{reason} from API")
                %{stats | skip_reason: reason}

              _ ->
                IO.puts("\n[Error] #{inspect(error)}")
                do_handle_events(timeout, started_at, stats)
            end

          {:session_event, _event} ->
            do_handle_events(timeout, started_at, stats)
        after
          remaining ->
            IO.puts("\n[Timeout] Event handling complete")
            stats
        end
      end
    end
  end

  defp print_tool_definition do
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

RealtimeToolsExample.main()
