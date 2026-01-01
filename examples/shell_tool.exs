# Example: Shell Tool Usage
# Run: mix run examples/shell_tool.exs
#
# Demonstrates the fully-featured Shell hosted tool with:
# - Default executor using erlexec
# - Custom executor for testing/mocking
# - Approval integration
# - Timeout handling
# - Output truncation

Mix.Task.run("app.start")

alias Codex.Tools
alias Codex.Tools.ShellTool

IO.puts("""
=== Shell Tool Example ===

This example demonstrates the Shell hosted tool capabilities.
""")

# Reset tools for clean state
Tools.reset!()

# -----------------------------------------------------------------------------
# 1. Basic shell execution with default executor
# -----------------------------------------------------------------------------
IO.puts("\n1. Basic shell execution (default executor)")
IO.puts("-" |> String.duplicate(50))

{:ok, _handle} = Tools.register(ShellTool)

{:ok, result} = Tools.invoke("shell", %{"command" => ["echo", "Hello from shell!"]}, %{})
IO.puts("Command: echo Hello from shell!")
IO.puts("Output: #{String.trim(result["output"])}")
IO.puts("Exit code: #{result["exit_code"]}")
IO.puts("Success: #{result["success"]}")

Tools.reset!()

# -----------------------------------------------------------------------------
# 2. Capturing exit codes
# -----------------------------------------------------------------------------
IO.puts("\n2. Capturing non-zero exit codes")
IO.puts("-" |> String.duplicate(50))

{:ok, _} = Tools.register(ShellTool)

{:ok, result} = Tools.invoke("shell", %{"command" => ["sh", "-c", "exit 42"]}, %{})
IO.puts("Command: sh -c \"exit 42\"")
IO.puts("Exit code: #{result["exit_code"]}")
IO.puts("Success: #{result["success"]}")

Tools.reset!()

# -----------------------------------------------------------------------------
# 3. Working directory support
# -----------------------------------------------------------------------------
IO.puts("\n3. Working directory support")
IO.puts("-" |> String.duplicate(50))

{:ok, _} = Tools.register(ShellTool)

{:ok, result} = Tools.invoke("shell", %{"command" => ["pwd"], "workdir" => "/tmp"}, %{})
IO.puts("Command: pwd (workdir: /tmp)")
IO.puts("Output: #{String.trim(result["output"])}")

Tools.reset!()

# -----------------------------------------------------------------------------
# 4. Output truncation
# -----------------------------------------------------------------------------
IO.puts("\n4. Output truncation")
IO.puts("-" |> String.duplicate(50))

{:ok, _} = Tools.register(ShellTool, max_output_bytes: 50)

{:ok, result} = Tools.invoke("shell", %{"command" => ["sh", "-c", "yes | head -n 100"]}, %{})
IO.puts("Command: sh -c \"yes | head -n 100\" (max 50 bytes)")
IO.puts("Output length: #{byte_size(result["output"])} bytes")
IO.puts("Truncated: #{String.ends_with?(result["output"], "... (truncated)")}")

Tools.reset!()

# -----------------------------------------------------------------------------
# 5. Approval callback integration
# -----------------------------------------------------------------------------
IO.puts("\n5. Approval callback integration")
IO.puts("-" |> String.duplicate(50))

approval = fn cmd, _ctx ->
  if String.contains?(cmd, "rm") do
    {:deny, "rm commands are not allowed"}
  else
    :ok
  end
end

{:ok, _} = Tools.register(ShellTool, approval: approval)

# Safe command - should succeed
{:ok, result} = Tools.invoke("shell", %{"command" => ["echo", "safe"]}, %{})
IO.puts("Command: echo safe")
IO.puts("Result: #{String.trim(result["output"])}")

# Dangerous command - should be denied
case Tools.invoke("shell", %{"command" => ["rm", "/some/file"]}, %{}) do
  {:error, {:approval_denied, reason}} ->
    IO.puts("\nCommand: rm /some/file")
    IO.puts("Denied: #{inspect(reason)}")

  {:ok, _} ->
    IO.puts("Unexpected: command was allowed")
end

Tools.reset!()

# -----------------------------------------------------------------------------
# 6. Custom executor for testing
# -----------------------------------------------------------------------------
IO.puts("\n6. Custom executor for testing/mocking")
IO.puts("-" |> String.duplicate(50))

mock_executor = fn %{"command" => cmd}, _ctx, _meta ->
  formatted = if is_list(cmd), do: Enum.join(cmd, " "), else: cmd
  IO.puts("  [Mock executor called with: #{formatted}]")
  {:ok, %{"output" => "Mocked output for: #{formatted}", "exit_code" => 0}}
end

{:ok, _} = Tools.register(ShellTool, executor: mock_executor)

{:ok, result} = Tools.invoke("shell", %{"command" => ["echo", "any-command"]}, %{})
IO.puts("Output: #{result["output"]}")

Tools.reset!()

# -----------------------------------------------------------------------------
# 7. Timeout handling
# -----------------------------------------------------------------------------
IO.puts("\n7. Timeout handling")
IO.puts("-" |> String.duplicate(50))

{:ok, _} = Tools.register(ShellTool, timeout_ms: 100)

case Tools.invoke("shell", %{"command" => ["sleep", "5"]}, %{}) do
  {:error, :timeout} ->
    IO.puts("Command: sleep 5 (timeout: 100ms)")
    IO.puts("Result: Timed out as expected!")

  {:ok, _} ->
    IO.puts("Unexpected: command completed (should have timed out)")
end

Tools.reset!()

# -----------------------------------------------------------------------------
# 8. Combining options
# -----------------------------------------------------------------------------
IO.puts("\n8. Combining multiple options")
IO.puts("-" |> String.duplicate(50))

approval = fn cmd, ctx ->
  IO.puts("  [Approval check for: #{cmd}, user: #{ctx[:user] || "unknown"}]")
  :ok
end

{:ok, _} =
  Tools.register(ShellTool,
    approval: approval,
    timeout_ms: 5000,
    max_output_bytes: 100,
    cwd: "/tmp"
  )

{:ok, result} =
  Tools.invoke(
    "shell",
    %{"command" => ["echo", "Combined options test"]},
    %{user: "admin"}
  )

IO.puts("Output: #{String.trim(result["output"])}")
IO.puts("Success: #{result["success"]}")

Tools.reset!()

# -----------------------------------------------------------------------------
# 9. Direct invocation without registry
# -----------------------------------------------------------------------------
IO.puts("\n9. Direct invocation (without registry)")
IO.puts("-" |> String.duplicate(50))

executor = fn _args, _ctx, _meta ->
  {:ok, %{"output" => "Direct call works!", "exit_code" => 0}}
end

context = %{metadata: %{executor: executor}}
args = %{"command" => ["echo", "test"]}

{:ok, result} = ShellTool.invoke(args, context)
IO.puts("Output: #{result["output"]}")

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
IO.puts("\n" <> String.duplicate("=", 50))
IO.puts("Shell Tool Example Complete!")

IO.puts("""

Features demonstrated:
- Basic command execution with default erlexec executor
- Exit code capture and success flag
- Working directory (workdir) support
- Output truncation for large outputs
- Approval callback integration (allow/deny)
- Custom executor for testing/mocking
- Timeout handling for long-running commands
- Combined options usage
- Direct invocation without registry

See lib/codex/tools/shell_tool.ex for full documentation.
""")
