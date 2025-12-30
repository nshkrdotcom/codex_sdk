# Prompt 01: MCP Tool Discovery Implementation

**Target Version:** 0.4.5
**Date:** 2025-12-30

## Objective

Implement MCP tool discovery (`list_tools/2`) in the Elixir Codex SDK to achieve feature parity with the canonical implementation.

## Required Reading

Before implementing, read and understand these files:

1. **Canonical Implementation:**
   - `codex/codex-rs/core/src/mcp_connection_manager.rs` - Tool discovery logic
   - `codex/codex-rs/rmcp-client/src/rmcp_client.rs` - RmcpClient.list_tools()
   - `openai-agents-python/src/agents/mcp/server.py` - Python reference

2. **Elixir SDK (Current State):**
   - `lib/codex/mcp/client.ex` - Current MCP client (handshake only)
   - `lib/codex/app_server/mcp.ex` - App-server MCP integration
   - `lib/codex/tools/registry.ex` - Tool registry patterns

3. **Documentation:**
   - `docs/20251202/adrs/adr-006-mcp-integration.md` - ADR for MCP
   - `codex/codex-rs/docs/codex_mcp_interface.md` - MCP interface spec

## Implementation Tasks

### 1. Extend `Codex.MCP.Client`

Add `list_tools/2` function:

```elixir
@doc """
Lists tools available from the MCP server.

## Options
  * `:cache?` - Whether to use cached results (default: true)
  * `:allow` - List of tool names to allow (allow-list filter)
  * `:deny` - List of tool names to deny (block-list filter)
  * `:filter` - Custom filter function `(tool -> boolean)`

## Returns
  * `{:ok, tools, updated_client}` on success
  * `{:error, reason}` on failure
"""
@spec list_tools(t(), keyword()) :: {:ok, [tool_info()], t()} | {:error, term()}
def list_tools(client, opts \\ [])
```

### 2. Implement Tool Name Handling

Handle tool name collisions (64-char limit):
- Truncate names > 64 chars
- Add SHA1 hash suffix for disambiguation
- Format: `mcp__<server>__<tool>`

### 3. Implement Tool Filtering

Apply two-tier filtering:
1. Allow-list (if provided, only these tools exposed)
2. Block-list (removed after allow-list)

### 4. Implement Caching

Cache tool list per session:
- Store in client state
- Invalidate on explicit request
- TTL-based expiration (optional)

## Test Requirements (TDD)

Write tests BEFORE implementation:

### Unit Tests (`test/codex/mcp/client_test.exs`)

```elixir
describe "list_tools/2" do
  test "returns tools from MCP server" do
    # Setup mock transport
    # Call list_tools
    # Assert tools returned
  end

  test "applies allow-list filter" do
    # Setup with multiple tools
    # Call with allow: ["tool_a"]
    # Assert only tool_a returned
  end

  test "applies deny-list filter" do
    # Setup with multiple tools
    # Call with deny: ["tool_b"]
    # Assert tool_b not in results
  end

  test "caches results by default" do
    # Call list_tools twice
    # Assert transport called once
  end

  test "bypasses cache when cache?: false" do
    # Call list_tools with cache?: false
    # Assert transport called each time
  end

  test "handles tool name truncation" do
    # Tool with name > 64 chars
    # Assert truncated with hash suffix
  end
end
```

### Integration Tests (`test/integration/mcp_test.exs`)

```elixir
@tag :live
describe "MCP tool discovery (live)" do
  test "discovers tools from running MCP server" do
    # Requires MCP server running
    # Skip if not available
  end
end
```

## Verification Criteria

Before completing, verify:

1. [ ] All new tests pass: `mix test test/codex/mcp/client_test.exs`
2. [ ] No warnings: `mix compile --warnings-as-errors`
3. [ ] No dialyzer errors: `mix dialyzer`
4. [ ] No credo issues: `mix credo --strict`
5. [ ] Examples updated: `examples/live_mcp_and_sessions.exs`
6. [ ] `examples/run_all.sh` passes

## Update Requirements

### README.md

Add to MCP section:
```markdown
### Tool Discovery

```elixir
{:ok, client} = Codex.MCP.Client.handshake({transport, state}, opts)
{:ok, tools, client} = Codex.MCP.Client.list_tools(client,
  allow: ["read_file", "write_file"],
  deny: ["dangerous_tool"]
)
```
```

### CHANGELOG.md

Add to the existing `## [0.4.5] - 2025-12-30` section:
```markdown
- MCP tool discovery with `Codex.MCP.Client.list_tools/2`
- Tool name collision handling with SHA1 suffix
- Allow/deny list filtering for MCP tools
- Tool caching with configurable TTL
```

### Examples

Create/update `examples/mcp_tool_discovery.exs`:
```elixir
# Example: MCP Tool Discovery
# Run: elixir examples/mcp_tool_discovery.exs

# ... example code
```
