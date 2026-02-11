#!/usr/bin/env mix run

# Realtime Handoffs Example
#
# Demonstrates agent-to-agent handoffs in realtime sessions.
#
# Usage:
#   mix run examples/realtime_handoffs.exs

defmodule RealtimeHandoffsExample do
  @moduledoc false

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
    IO.puts("=== Realtime Handoffs Example ===\n")

    unless fetch_api_key() do
      {:error, "no API key found (CODEX_API_KEY, auth.json OPENAI_API_KEY, or OPENAI_API_KEY)"}
    else
      with {:ok, session} <- start_session() do
        Realtime.subscribe(session, self())

        result =
          try do
            Process.sleep(500)

            IO.puts("\nSending message that should trigger transfer_to_techsupport...")

            Realtime.send_message(
              session,
              "I have a technical problem with my software. Use transfer_to_techsupport."
            )

            handle_events(30_000, %{
              handoff_seen?: false,
              tool_calls: 0,
              insufficient_quota?: false
            })
          after
            safe_close(session)
          end

        case result do
          %{insufficient_quota?: true} ->
            {:skip, "insufficient_quota"}

          %{handoff_seen?: true} ->
            :ok

          %{handoff_seen?: false, tool_calls: tool_calls} ->
            IO.puts("No handoff observed (tool_calls=#{tool_calls}).")
            :ok
        end
      else
        {:error, reason} -> maybe_skip_quota(reason)
      end
    end
  end

  defp start_session do
    tech_support =
      Realtime.agent(
        name: "TechSupport",
        handoff_description: "Handles technical support issues and troubleshooting",
        instructions: """
        You are a technical support specialist. Help users with technical issues.
        Be patient and concise.
        """
      )

    billing_agent =
      Realtime.agent(
        name: "BillingAgent",
        handoff_description: "Handles billing inquiries and account questions",
        instructions: """
        You handle billing and account inquiries.
        Be professional and concise.
        """
      )

    greeter =
      Realtime.agent(
        name: "Greeter",
        instructions: """
        You are a friendly greeter. Welcome users and route to specialists.
        Use transfer_to_techsupport for technical issues.
        Use transfer_to_billingagent for billing issues.
        """,
        handoffs: [tech_support, billing_agent]
      )

    IO.puts("Created agent network:")
    IO.puts("  - #{greeter.name} (entry point)")
    IO.puts("    -> #{tech_support.name}: #{tech_support.handoff_description}")
    IO.puts("    -> #{billing_agent.name}: #{billing_agent.handoff_description}")
    IO.puts("\nStarting realtime session...")

    Realtime.run(greeter)
  end

  defp handle_events(timeout, state) do
    if state.insufficient_quota? do
      state
    else
      receive do
        {:session_event, %Events.HandoffEvent{from_agent: from, to_agent: to}} ->
          IO.puts("\n[Handoff] #{from.name} -> #{to.name}")
          handle_events(timeout, %{state | handoff_seen?: true})

        {:session_event, %Events.ToolStartEvent{tool: tool}} ->
          tool_name = Map.get(tool || %{}, "name") || Map.get(tool || %{}, :name) || inspect(tool)
          IO.puts("\n[Tool Call] #{tool_name}")
          handle_events(timeout, %{state | tool_calls: state.tool_calls + 1})

        {:session_event, %Events.AgentStartEvent{agent: agent}} ->
          IO.puts("\n[Agent] Now speaking with: #{agent.name}")
          handle_events(timeout, state)

        {:session_event, %Events.AgentEndEvent{agent: agent}} ->
          IO.puts("[Agent] #{agent.name} turn ended")
          handle_events(timeout, state)

        {:session_event, %Events.AudioEvent{}} ->
          IO.write(".")
          handle_events(timeout, state)

        {:session_event, %Events.ErrorEvent{error: error}} ->
          if insufficient_quota_error?(error) do
            IO.puts("\n[Error] insufficient_quota from API")
            %{state | insufficient_quota?: true}
          else
            IO.puts("\n[Error] #{inspect(error)}")
            handle_events(timeout, state)
          end

        {:session_event, event} ->
          IO.puts("[Event] #{inspect(event.__struct__)}")
          handle_events(timeout, state)
      after
        timeout ->
          IO.puts("\n[Timeout] Event handling complete")
          state
      end
    end
  end

  defp safe_close(session) do
    IO.puts("\nClosing session...")
    Realtime.close(session)
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

  defp fetch_api_key, do: Codex.Auth.direct_api_key()
end

RealtimeHandoffsExample.main()
