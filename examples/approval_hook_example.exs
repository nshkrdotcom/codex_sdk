#!/usr/bin/env elixir

# Example: Using Custom Approval Hooks
#
# This example demonstrates how to implement custom approval hooks for
# synchronous and asynchronous approval workflows.

defmodule SlackApprovalHook do
  @moduledoc """
  Example approval hook that integrates with Slack (simulated).

  In a real implementation, this would:
  1. Post approval requests to a Slack channel
  2. Wait for button clicks or slash commands
  3. Return the decision
  """

  @behaviour Codex.Approvals.Hook

  @impl true
  def prepare(event, context) do
    # You can augment the context with additional metadata here
    enriched_context = Map.put(context, :slack_channel, "#approvals")
    {:ok, enriched_context}
  end

  @impl true
  def review_tool(event, context, _opts) do
    tool_name = event.tool_name || event[:tool_name]
    arguments = event.arguments || event[:arguments]

    IO.puts("""
    📋 Approval Request
    Tool: #{tool_name}
    Arguments: #{inspect(arguments)}
    Channel: #{context.slack_channel}
    """)

    # For this example, we'll auto-approve after a delay
    ref = make_ref()
    parent = self()

    spawn(fn ->
      Process.sleep(100)
      send(parent, {:slack_approval, ref, :allow})
    end)

    {:async, ref, %{slack_message_ts: "1234567890.123456"}}
  end

  @impl true
  def await(ref, timeout) do
    receive do
      {:slack_approval, ^ref, :allow} ->
        IO.puts("✅ Approved via Slack")
        {:ok, :allow}

      {:slack_approval, ^ref, {:deny, reason}} ->
        IO.puts("❌ Denied via Slack: #{reason}")
        {:ok, {:deny, reason}}
    after
      timeout ->
        IO.puts("⏱️ Approval timeout")
        {:error, :timeout}
    end
  end
end

defmodule ManualApprovalHook do
  @moduledoc """
  Example hook that requires manual terminal input.
  """

  @behaviour Codex.Approvals.Hook

  @impl true
  def prepare(_event, context), do: {:ok, context}

  @impl true
  def review_tool(event, _context, _opts) do
    tool_name = event.tool_name || event[:tool_name]
    arguments = event.arguments || event[:arguments]

    IO.puts("\n🔔 Tool Invocation Request:")
    IO.puts("Tool: #{tool_name}")
    IO.puts("Arguments: #{inspect(arguments, pretty: true)}")
    IO.write("Approve? [y/N]: ")

    case IO.gets("") |> String.trim() |> String.downcase() do
      "y" -> :allow
      "yes" -> :allow
      _ -> {:deny, "manual rejection"}
    end
  end
end

defmodule AutoApproveWithLogging do
  @moduledoc """
  Example hook that auto-approves but logs to an audit trail.
  """

  @behaviour Codex.Approvals.Hook

  @impl true
  def prepare(_event, context), do: {:ok, context}

  @impl true
  def review_tool(event, context, _opts) do
    # Log to audit trail (in real app, this would write to DB or file)
    tool_name = event.tool_name || event[:tool_name]
    thread_id = context.thread && context.thread.thread_id

    IO.puts("[AUDIT] Thread #{thread_id}: Tool #{tool_name} approved at #{DateTime.utc_now()}")

    :allow
  end
end

# Example usage with telemetry
:telemetry.attach_many(
  "approval-telemetry",
  [
    [:codex, :approval, :requested],
    [:codex, :approval, :approved],
    [:codex, :approval, :denied],
    [:codex, :approval, :timeout]
  ],
  fn event_name, measurements, metadata, _config ->
    event_type = event_name |> List.last() |> to_string() |> String.upcase()

    IO.puts("""
    [TELEMETRY] #{event_type}
      Tool: #{metadata[:tool]}
      Time: #{measurements[:duration] || measurements[:system_time]}
      #{if metadata[:reason], do: "Reason: #{metadata[:reason]}", else: ""}
    """)
  end,
  nil
)

IO.puts("""
╔════════════════════════════════════════════════════════╗
║  Codex SDK - Approval Hook Examples                    ║
╚════════════════════════════════════════════════════════╝

This example demonstrates three types of approval hooks:

1. SlackApprovalHook - Async approval via Slack (simulated)
2. ManualApprovalHook - Interactive terminal approval
3. AutoApproveWithLogging - Auto-approve with audit logging

To use these hooks in your code:

  {:ok, thread_opts} = Codex.Thread.Options.new(%{
    approval_hook: SlackApprovalHook,
    approval_timeout_ms: 30_000
  })

Or with the legacy approval_policy (StaticPolicy):

  {:ok, thread_opts} = Codex.Thread.Options.new(%{
    approval_policy: Codex.Approvals.StaticPolicy.allow()
  })

Telemetry Events:
  • [:codex, :approval, :requested] - when approval is requested
  • [:codex, :approval, :approved] - when approved
  • [:codex, :approval, :denied] - when denied
  • [:codex, :approval, :timeout] - when async approval times out

""")
