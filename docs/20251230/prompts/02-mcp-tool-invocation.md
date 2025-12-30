# Prompt 02: MCP Tool Invocation Implementation

**Target Version:** 0.4.5
**Date:** 2025-12-30
**Depends On:** Prompt 01 (MCP Tool Discovery)

## Objective

Implement MCP tool invocation (`call_tool/4`) with retry logic and approval integration.

## Required Reading

1. **Canonical Implementation:**
   - `codex/codex-rs/core/src/mcp_tool_call.rs` - Tool call events
   - `codex/codex-rs/core/src/tools/handlers/mcp.rs` - MCP handler
   - `openai-agents-python/src/agents/mcp/server.py` - Python call_tool

2. **Elixir SDK:**
   - `lib/codex/mcp/client.ex` - After Prompt 01 updates
   - `lib/codex/tools/hosted_tools.ex` - HostedMcpTool pattern
   - `lib/codex/approvals.ex` - Approval integration
   - `lib/codex/thread/backoff.ex` - Backoff utilities

## Implementation Tasks

### 1. Add `call_tool/4` to `Codex.MCP.Client`

```elixir
@doc """
Invokes a tool on the MCP server.

## Options
  * `:retries` - Number of retry attempts (default: 3)
  * `:backoff` - Backoff function (default: exponential)
  * `:timeout_ms` - Request timeout (default: 60_000)
  * `:approval` - Approval callback or policy
  * `:context` - Tool context map

## Returns
  * `{:ok, result}` on success
  * `{:error, reason}` on failure
"""
@spec call_tool(t(), String.t(), map(), keyword()) :: {:ok, term()} | {:error, term()}
def call_tool(client, tool_name, arguments, opts \\ [])
```

### 2. Implement Retry Logic

```elixir
defp with_retry(fun, opts) do
  retries = Keyword.get(opts, :retries, 3)
  backoff = Keyword.get(opts, :backoff, &exponential_backoff/1)

  Enum.reduce_while(1..retries, nil, fn attempt, _acc ->
    case fun.() do
      {:ok, result} -> {:halt, {:ok, result}}
      {:error, reason} when attempt < retries ->
        Process.sleep(backoff.(attempt))
        {:cont, {:error, reason}}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end)
end

defp exponential_backoff(attempt) do
  base = 200
  max = 10_000
  min(base * :math.pow(2, attempt - 1), max) |> round()
end
```

### 3. Integrate with Approvals

```elixir
defp maybe_approve(tool_name, arguments, context, approval) do
  case approval do
    nil -> :ok
    fun when is_function(fun) -> fun.(tool_name, arguments, context)
    module when is_atom(module) -> module.review_tool(tool_name, arguments, context)
  end
end
```

### 4. Emit Tool Call Events

Emit telemetry events:
- `[:codex, :mcp, :tool_call, :start]`
- `[:codex, :mcp, :tool_call, :success]`
- `[:codex, :mcp, :tool_call, :failure]`

## Test Requirements (TDD)

### Unit Tests (`test/codex/mcp/client_test.exs`)

```elixir
describe "call_tool/4" do
  test "invokes tool and returns result" do
    # Mock transport to return success
    # Call tool
    # Assert result matches
  end

  test "retries on transient failure" do
    # Mock transport to fail then succeed
    # Call with retries: 2
    # Assert success after retry
  end

  test "applies exponential backoff" do
    # Mock transport to fail twice
    # Track timing between calls
    # Assert backoff applied
  end

  test "respects approval callback" do
    # Mock approval to deny
    # Call tool
    # Assert :denied error
  end

  test "times out after timeout_ms" do
    # Mock slow transport
    # Call with timeout_ms: 100
    # Assert :timeout error
  end

  test "emits telemetry events" do
    # Attach telemetry handler
    # Call tool
    # Assert events received
  end
end
```

### Integration Tests

```elixir
@tag :live
describe "MCP tool invocation (live)" do
  test "calls tool on running MCP server" do
    # Requires MCP server
  end
end
```

## Verification Criteria

1. [ ] All tests pass
2. [ ] No warnings
3. [ ] No dialyzer errors
4. [ ] No credo issues
5. [ ] Examples run: `examples/live_mcp_and_sessions.exs`
6. [ ] `examples/run_all.sh` passes

## Update Requirements

### CHANGELOG.md

Add to the existing `## [0.4.5] - 2025-12-30` section:
```markdown
- MCP tool invocation with `Codex.MCP.Client.call_tool/4`
- Exponential backoff retry logic for MCP calls
- Approval integration for MCP tool calls
- Telemetry events for MCP tool invocation
```

### Examples

Update `examples/mcp_tool_discovery.exs` to include tool invocation example.

### README.md

Add call_tool example to MCP section.
