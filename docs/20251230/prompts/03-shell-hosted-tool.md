# Prompt 03: Shell Hosted Tool Implementation

**Target Version:** 0.4.5
**Date:** 2025-12-30
**Depends On:** None (standalone)

## Objective

Implement a fully-featured Shell hosted tool for executing shell commands with approval, timeout, and output truncation.

## Required Reading

1. **Canonical Implementation:**
   - `codex/codex-rs/core/src/tools/handlers/shell.rs` - Shell handler
   - `codex/shell-tool-mcp/` - MCP shell tool reference
   - `codex/codex-rs/exec/src/cli.rs` - Command execution patterns

2. **Elixir SDK:**
   - `lib/codex/tools/hosted_tools.ex` - Current structure
   - `lib/codex/tool.ex` - Tool behavior
   - `lib/codex/exec.ex` - Subprocess execution patterns
   - `lib/codex/approvals.ex` - Approval integration

3. **Python Reference:**
   - `openai-agents-python/src/agents/tool.py` - Tool patterns

## Implementation Tasks

### 1. Implement `Codex.Tools.ShellTool`

Create `lib/codex/tools/shell_tool.ex`:

```elixir
defmodule Codex.Tools.ShellTool do
  @moduledoc """
  Hosted tool for executing shell commands.

  ## Options
    * `:executor` - Custom executor function (default: System.cmd)
    * `:approval` - Approval callback or policy
    * `:max_output_bytes` - Maximum output size (default: 10_000)
    * `:timeout_ms` - Command timeout (default: 60_000)
    * `:cwd` - Working directory
    * `:env` - Environment variables
  """

  @behaviour Codex.Tool

  @impl true
  def metadata do
    %{
      name: "shell",
      description: "Execute shell commands",
      schema: %{
        "type" => "object",
        "properties" => %{
          "command" => %{
            "type" => "string",
            "description" => "The shell command to execute"
          },
          "cwd" => %{
            "type" => "string",
            "description" => "Working directory (optional)"
          },
          "timeout_ms" => %{
            "type" => "integer",
            "description" => "Timeout in milliseconds (optional)"
          }
        },
        "required" => ["command"],
        "additionalProperties" => false
      }
    }
  end

  @impl true
  def invoke(args, context) do
    command = Map.fetch!(args, "command")
    cwd = Map.get(args, "cwd", context[:cwd])
    timeout_ms = Map.get(args, "timeout_ms", context[:timeout_ms] || 60_000)

    with :ok <- maybe_approve(command, context),
         {:ok, output, exit_code} <- execute(command, cwd, timeout_ms, context) do
      {:ok, format_result(output, exit_code)}
    end
  end

  defp maybe_approve(command, context) do
    case context[:approval] do
      nil -> :ok
      fun when is_function(fun, 2) -> fun.(command, context)
      fun when is_function(fun, 3) -> fun.(command, context, metadata())
      module -> module.review_tool(command, context)
    end
  end

  defp execute(command, cwd, timeout_ms, context) do
    executor = context[:executor] || &default_executor/3
    executor.(command, cwd, timeout_ms)
  end

  defp default_executor(command, cwd, timeout_ms) do
    opts = [
      cd: cwd,
      stderr_to_stdout: true,
      timeout: timeout_ms
    ]

    case :exec.run(~c"sh -c '#{command}'", opts) do
      {:ok, [{:stdout, output}]} -> {:ok, to_string(output), 0}
      {:ok, [{:exit_status, code}]} -> {:ok, "", code}
      {:ok, [{:stdout, output}, {:exit_status, code}]} -> {:ok, to_string(output), code}
      {:error, reason} -> {:error, reason}
    end
  end

  defp format_result(output, exit_code) do
    max_bytes = 10_000
    truncated = if byte_size(output) > max_bytes do
      String.slice(output, 0, max_bytes) <> "\n... (truncated)"
    else
      output
    end

    %{
      "output" => truncated,
      "exit_code" => exit_code,
      "success" => exit_code == 0
    }
  end
end
```

### 2. Register in `Codex.Tools.HostedTools`

Update `lib/codex/tools/hosted_tools.ex`:

```elixir
def shell(opts \\ []) do
  %{
    module: Codex.Tools.ShellTool,
    name: "shell",
    opts: opts
  }
end

def all do
  [shell(), apply_patch(), file_search(), web_search()]
end
```

### 3. Add to Tool Registry Auto-Registration

Update tool registration to include shell tool when available.

## Test Requirements (TDD)

### Unit Tests (`test/codex/tools/shell_tool_test.exs`)

```elixir
defmodule Codex.Tools.ShellToolTest do
  use ExUnit.Case, async: true

  describe "metadata/0" do
    test "returns valid tool metadata" do
      meta = Codex.Tools.ShellTool.metadata()
      assert meta.name == "shell"
      assert meta.schema["required"] == ["command"]
    end
  end

  describe "invoke/2" do
    test "executes simple command" do
      args = %{"command" => "echo hello"}
      {:ok, result} = Codex.Tools.ShellTool.invoke(args, %{})
      assert result["output"] =~ "hello"
      assert result["exit_code"] == 0
    end

    test "captures exit code" do
      args = %{"command" => "exit 42"}
      {:ok, result} = Codex.Tools.ShellTool.invoke(args, %{})
      assert result["exit_code"] == 42
      assert result["success"] == false
    end

    test "truncates large output" do
      args = %{"command" => "yes | head -n 10000"}
      {:ok, result} = Codex.Tools.ShellTool.invoke(args, %{})
      assert String.ends_with?(result["output"], "... (truncated)")
    end

    test "respects custom cwd" do
      args = %{"command" => "pwd", "cwd" => "/tmp"}
      {:ok, result} = Codex.Tools.ShellTool.invoke(args, %{})
      assert result["output"] =~ "/tmp"
    end

    test "times out on slow command" do
      args = %{"command" => "sleep 10", "timeout_ms" => 100}
      assert {:error, :timeout} = Codex.Tools.ShellTool.invoke(args, %{})
    end

    test "respects approval callback" do
      args = %{"command" => "rm -rf /"}
      context = %{approval: fn _cmd, _ctx -> {:deny, "dangerous"} end}
      assert {:deny, "dangerous"} = Codex.Tools.ShellTool.invoke(args, context)
    end

    test "uses custom executor" do
      executor = fn cmd, _cwd, _timeout ->
        {:ok, "mocked: #{cmd}", 0}
      end
      args = %{"command" => "test"}
      context = %{executor: executor}
      {:ok, result} = Codex.Tools.ShellTool.invoke(args, context)
      assert result["output"] == "mocked: test"
    end
  end
end
```

### Integration Tests

```elixir
@tag :live
describe "Shell tool (live)" do
  test "executes real commands" do
    Codex.Tools.register(Codex.Tools.ShellTool)
    {:ok, result} = Codex.Tools.invoke("shell", %{"command" => "uname -a"}, %{})
    assert result["success"]
  end
end
```

## Verification Criteria

1. [ ] All tests pass: `mix test test/codex/tools/shell_tool_test.exs`
2. [ ] No warnings
3. [ ] No dialyzer errors
4. [ ] No credo issues
5. [ ] Example works: create `examples/shell_tool.exs`
6. [ ] `examples/run_all.sh` passes

## Update Requirements

### CHANGELOG.md

Add to the existing `## [0.4.5] - 2025-12-30` section:
```markdown
- Shell hosted tool with `Codex.Tools.ShellTool`
- Command timeout and output truncation
- Approval integration for shell commands
- Custom executor support for testing
```

### Examples

Create `examples/shell_tool.exs`:
```elixir
# Example: Shell Tool Usage
# Run: elixir examples/shell_tool.exs

Mix.install([{:codex_sdk, path: "."}])

# Register shell tool
{:ok, _} = Codex.Tools.register(Codex.Tools.ShellTool)

# Execute a simple command
{:ok, result} = Codex.Tools.invoke("shell", %{"command" => "ls -la"}, %{})
IO.puts("Output: #{result["output"]}")
IO.puts("Exit code: #{result["exit_code"]}")

# With approval
approval = fn cmd, _ctx ->
  if String.contains?(cmd, "rm"), do: {:deny, "rm not allowed"}, else: :ok
end

{:ok, result} = Codex.Tools.invoke("shell", %{"command" => "echo safe"}, %{approval: approval})
IO.puts("Safe command: #{result["output"]}")

# Denied command
{:deny, reason} = Codex.Tools.invoke("shell", %{"command" => "rm file"}, %{approval: approval})
IO.puts("Denied: #{reason}")
```

### README.md

Add shell tool section under Hosted Tools.
