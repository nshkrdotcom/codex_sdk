#!/usr/bin/env elixir

# Example: Sandbox warning normalization + policy-approved bypass
#
# This script demonstrates how sandbox warnings are deduplicated/normalized
# (especially on Windows) and how tool calls flagged as pre-approved by policy
# skip approval hooks. It also supports an optional live Codex run; auth will
# use CODEX_API_KEY (or auth.json OPENAI_API_KEY) when set, otherwise your Codex CLI login.

Mix.Task.run("app.start")

defmodule SandboxDemoTool do
  use Codex.Tool, name: "sandbox_demo", description: "Echo args while surfacing sandbox warnings"

  @impl true
  def invoke(args, context) do
    IO.puts("Context warnings seen by tool: #{inspect(context[:sandbox_warnings])}")
    {:ok, %{"echo" => Map.get(args, "echo", "ok")}}
  end
end

defmodule SandboxWarningsAndApprovalBypass do
  def main do
    handler_id = "sandbox-warnings-demo-#{System.unique_integer([:positive])}"

    register_tool()

    :ok =
      :telemetry.attach(
        handler_id,
        [:codex, :tool, :start],
        &__MODULE__.telemetry_handler/4,
        nil
      )

    local_demo()
    live_demo()

    :telemetry.detach(handler_id)
  end

  def telemetry_handler(_event, _measurements, metadata, _config) do
    IO.puts("Telemetry warnings: #{inspect(metadata[:sandbox_warnings])}")
  end

  defp register_tool do
    case Codex.Tools.register(SandboxDemoTool, name: "sandbox_demo") do
      {:ok, _handle} -> :ok
      {:error, {:already_registered, _}} -> :ok
      other -> raise "failed to register tool: #{inspect(other)}"
    end
  end

  defp local_demo do
    warnings = [
      "World-writable directory: C:\\\\Temp",
      "World-writable directory: C:/Temp",
      "Read-only git dir: C:\\\\workspace\\\\.git",
      "/var/tmp is world-writable"
    ]

    IO.puts("\n-- invoking tool with mixed-path sandbox warnings (local demo) --")

    {:ok, _} =
      Codex.Tools.invoke("sandbox_demo", %{"echo" => "hello"}, %{
        thread_id: "demo",
        sandbox_warnings: warnings
      })

    IO.puts("\n-- approval bypass when policy already approved the command (local demo) --")
    policy = Codex.Approvals.StaticPolicy.deny(reason: "would normally block")

    event = %Codex.Events.ToolCallRequested{
      thread_id: "demo",
      turn_id: "t-1",
      call_id: "call-approved",
      tool_name: "sandbox_demo",
      arguments: %{},
      requires_approval: true,
      approved_by_policy: true
    }

    IO.inspect(Codex.Approvals.review_tool(policy, event, %{}), label: "approval result")
  end

  defp live_demo do
    IO.puts("\n-- optional live Codex run (CLI auth or API key) --")

    with {:ok, codex_opts} <- Codex.Options.new(%{}),
         {:ok, _path} <- Codex.Options.codex_path(codex_opts),
         {:ok, thread_opts} <- Codex.Thread.Options.new(%{sandbox: :strict}),
         thread <- Codex.Thread.build(codex_opts, thread_opts),
         {:ok, result} <-
           Codex.Thread.run(
             thread,
             "Say hello and mention if any sandbox warnings were reported."
           ) do
      IO.inspect(result.final_response, label: "live response")

      live_warnings =
        result.events
        |> Enum.filter(&match?(%Codex.Events.ToolCallRequested{}, &1))
        |> Enum.flat_map(fn ev ->
          (ev.sandbox_warnings || ev[:sandbox_warnings] || []) |> List.wrap()
        end)
        |> Enum.uniq()

      IO.puts("Live sandbox warnings: #{inspect(live_warnings)}")
    else
      {:error, reason} ->
        IO.puts("Live run failed: #{inspect(reason)}")
        IO.puts("Ensure the `codex` CLI is installed and authenticated (`codex auth login`).")
    end
  end
end

SandboxWarningsAndApprovalBypass.main()
