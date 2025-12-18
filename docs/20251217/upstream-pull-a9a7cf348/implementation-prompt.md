# Implementation Agent Prompt: Port Upstream Breaking Changes

You are implementing the P0/P1 changes identified in the upstream pull audit for the Elixir Codex SDK.

---

## Required Reading (Read These First)

### Audit & Analysis Documents (in this repo)

1. `docs/20251217/upstream-pull-a9a7cf348/porting-notes.md` - Original porting analysis
2. `docs/20251217/upstream-pull-a9a7cf348/audit-report.md` - Independent audit verification

### Elixir SDK Source Files to Modify

3. `lib/codex/app_server.ex` - Main app-server module (lines 172-179: `thread_compact/2`)
4. `lib/codex/app_server/mcp.ex` - MCP server listing (line 16: method string)
5. `lib/codex/app_server/connection.ex` - Connection handling (understand request flow)
6. `lib/codex/app_server/notification_adapter.ex` - Notification mapping (understand fallback)

### Elixir SDK Test Files

7. `test/codex/app_server_test.exs` - Existing app-server tests
8. `test/codex/app_server/mcp_test.exs` - Existing MCP tests (if exists, else create)
9. `test/support/` - Test helpers and mocks

### Documentation Files to Update

10. `docs/09-app-server-transport.md` - App-server transport guide
11. `README.md` - Main readme (version badge, features)
12. `CHANGELOG.md` - Changelog
13. `mix.exs` - Version number
14. `examples/README.md` - Examples documentation
15. `examples/run_all.sh` - Example runner script

### Upstream Reference (read-only, in `codex/` subtree)

16. `codex/codex-rs/app-server/README.md` - Upstream protocol docs
17. `codex/codex-rs/app-server-protocol/src/protocol/common.rs` - Method definitions
18. `codex/codex-rs/app-server-protocol/src/protocol/v2.rs` - Type definitions

---

## Context Summary

### What Changed Upstream (5d77d4db6..a9a7cf348)

1. **`thread/compact` API REMOVED** (commit `412dd3795`)
   - Method `"thread/compact"` no longer exists in app-server
   - Server returns `-32601` (method not found) error
   - SDK function `Codex.AppServer.thread_compact/2` is now broken

2. **`mcpServers/list` RENAMED to `mcpServerStatus/list`** (commit `600d01b33`)
   - Old method `"mcpServers/list"` returns `-32601` on new servers
   - New method `"mcpServerStatus/list"` works on new servers
   - Response types renamed: `McpServer` → `McpServerStatus`
   - SDK function `Codex.AppServer.Mcp.list_servers/2` uses old method

3. **`ConfigLayerSource` schema change** (commit `de3fa03e1`)
   - Old: `%{"name" => "user", "source" => "/path/...", "version" => "..."}`
   - New: `%{"name" => %{"type" => "user", "file" => "/path/..."}, "version" => "..."}`
   - SDK passes through raw maps, so code unchanged but docs need update

4. **`SkillScope::Public` added** (commit `4897efcce`)
   - Skills can now have `scope: "Public"` in addition to `"User"` and `"Repo"`
   - Skills require feature flag: `[features].skills = true`

5. **`.codex/` now read-only in sandbox** (commit `bef36f4ae`)
   - Like `.git/`, `.codex/` directories are read-only under workspace-write sandbox

---

## Implementation Tasks (TDD Approach)

### Phase 1: Write Failing Tests First

#### Task 1.1: Test for `thread_compact/2` deprecation

Create/update test in `test/codex/app_server_test.exs`:

```elixir
describe "thread_compact/2" do
  test "returns unsupported error for removed API" do
    # This should return an error without making a network call
    # because the API was removed upstream
    {:ok, conn} = start_mock_connection()

    assert {:error, {:unsupported, message}} = Codex.AppServer.thread_compact(conn, "thr_123")
    assert message =~ "thread/compact"
    assert message =~ "removed"
  end
end
```

#### Task 1.2: Test for `Mcp.list_servers/2` with fallback

Create `test/codex/app_server/mcp_test.exs`:

```elixir
defmodule Codex.AppServer.McpTest do
  use ExUnit.Case, async: true

  alias Codex.AppServer.Mcp

  describe "list_servers/2" do
    test "uses new method mcpServerStatus/list on new servers" do
      # Mock connection that accepts new method
      {:ok, conn} = start_mock_connection(methods: ["mcpServerStatus/list"])

      assert {:ok, %{"data" => _}} = Mcp.list_servers(conn)
      assert_received {:request, "mcpServerStatus/list", _}
    end

    test "falls back to mcpServers/list on old servers" do
      # Mock connection that rejects new method with -32601
      {:ok, conn} = start_mock_connection(
        methods: ["mcpServers/list"],
        reject: ["mcpServerStatus/list"]
      )

      assert {:ok, %{"data" => _}} = Mcp.list_servers(conn)
      # Should have tried new method first, then fallen back
      assert_received {:request, "mcpServerStatus/list", _}
      assert_received {:request, "mcpServers/list", _}
    end

    test "returns error when both methods fail" do
      {:ok, conn} = start_mock_connection(reject: :all)

      assert {:error, _} = Mcp.list_servers(conn)
    end
  end
end
```

#### Task 1.3: Test for `list_server_statuses/2` new function (optional alias)

```elixir
test "list_server_statuses/2 is an alias for list_servers/2" do
  {:ok, conn} = start_mock_connection(methods: ["mcpServerStatus/list"])

  assert Mcp.list_server_statuses(conn) == Mcp.list_servers(conn)
end
```

### Phase 2: Implement to Make Tests Pass

#### Task 2.1: Update `lib/codex/app_server.ex`

Change `thread_compact/2` (lines 172-179) from:

```elixir
@spec thread_compact(connection(), String.t()) :: :ok | {:error, term()}
def thread_compact(conn, thread_id) when is_pid(conn) and is_binary(thread_id) do
  case Connection.request(conn, "thread/compact", %{"threadId" => thread_id},
         timeout_ms: 30_000
       ) do
    {:ok, _} -> :ok
    {:error, _} = error -> error
  end
end
```

To:

```elixir
@doc """
Returns an unsupported error. The `thread/compact` API was removed in upstream
codex app-server. Context compaction now happens automatically server-side.

## Deprecation Notice

This function is retained for API compatibility but will always return an error.
Remove calls to this function from your code.
"""
@spec thread_compact(connection(), String.t()) :: {:error, {:unsupported, String.t()}}
@deprecated "thread/compact API removed upstream; compaction is now automatic"
def thread_compact(_conn, _thread_id) do
  {:error, {:unsupported, "thread/compact API was removed in upstream codex; context compaction is now automatic server-side"}}
end
```

#### Task 2.2: Update `lib/codex/app_server/mcp.ex`

Change `list_servers/2` (line 16) from:

```elixir
@spec list_servers(connection(), keyword()) :: {:ok, map()} | {:error, term()}
def list_servers(conn, opts \\ []) when is_pid(conn) and is_list(opts) do
  params =
    %{}
    |> Params.put_optional("cursor", Keyword.get(opts, :cursor))
    |> Params.put_optional("limit", Keyword.get(opts, :limit))

  Connection.request(conn, "mcpServers/list", params, timeout_ms: 30_000)
end
```

To:

```elixir
@doc """
Lists configured MCP servers with their tools, resources, and auth status.

Supports cursor-based pagination via `:cursor` and `:limit` options.

## Compatibility

This function tries the new `mcpServerStatus/list` method first. If the server
returns a "method not found" error (older servers), it falls back to the
legacy `mcpServers/list` method automatically.
"""
@spec list_servers(connection(), keyword()) :: {:ok, map()} | {:error, term()}
def list_servers(conn, opts \\ []) when is_pid(conn) and is_list(opts) do
  params =
    %{}
    |> Params.put_optional("cursor", Keyword.get(opts, :cursor))
    |> Params.put_optional("limit", Keyword.get(opts, :limit))

  case Connection.request(conn, "mcpServerStatus/list", params, timeout_ms: 30_000) do
    {:error, %{"code" => -32601}} ->
      # Method not found - fall back to legacy method for older servers
      Connection.request(conn, "mcpServers/list", params, timeout_ms: 30_000)

    {:error, %{code: -32601}} ->
      # Method not found (atom key variant)
      Connection.request(conn, "mcpServers/list", params, timeout_ms: 30_000)

    result ->
      result
  end
end

@doc """
Alias for `list_servers/2`. Returns MCP server status information.
"""
@spec list_server_statuses(connection(), keyword()) :: {:ok, map()} | {:error, term()}
def list_server_statuses(conn, opts \\ []), do: list_servers(conn, opts)
```

### Phase 3: Run Tests and Fix Issues

```bash
# Run all tests
mix test

# Run specific test files
mix test test/codex/app_server_test.exs
mix test test/codex/app_server/mcp_test.exs

# Run with coverage
mix test --cover

# Check for warnings
mix compile --warnings-as-errors

# Run dialyzer
mix dialyzer
```

**Success Criteria:**
- All tests pass (0 failures)
- No compiler warnings
- No dialyzer errors
- Code formatted (`mix format --check-formatted`)

### Phase 4: Update Documentation

#### Task 4.1: Update `docs/09-app-server-transport.md`

1. Remove "compact" from line 10:
   ```diff
   -Use app-server when you need upstream v2 APIs that are not exposed via exec JSONL (threads list/archive/compact, skills/models/config APIs, server-driven approvals, etc.).
   +Use app-server when you need upstream v2 APIs that are not exposed via exec JSONL (threads list/archive, skills/models/config APIs, server-driven approvals, etc.).
   ```

2. Add deprecation note after the thread management section:
   ```markdown
   ### Removed APIs

   - `thread_compact/2` - Removed upstream; compaction is now automatic server-side
   ```

3. Update skills section (lines 155-157) to add feature flag prerequisite:
   ```markdown
   ## Skills

   Skills require the experimental feature flag to be enabled in your codex config:

   ```toml
   # ~/.codex/config.toml
   [features]
   skills = true
   ```

   Skills can have one of three scopes: `"User"`, `"Repo"`, or `"Public"`.
   ```

4. Add note about `.codex/` sandbox behavior:
   ```markdown
   ## Sandbox Notes

   Under `workspace-write` sandbox mode, both `.git/` and `.codex/` directories
   are automatically marked read-only to prevent privilege escalation.
   ```

#### Task 4.2: Update `README.md`

1. Bump version in badge/header
2. Add note about upstream compatibility in features section

#### Task 4.3: Update `CHANGELOG.md`

Add entry at the top:

```markdown
## [0.4.0] - 2025-12-17

### Breaking Changes

- `Codex.AppServer.thread_compact/2` now returns `{:error, {:unsupported, _}}` - the upstream `thread/compact` API was removed; compaction is now automatic

### Changed

- `Codex.AppServer.Mcp.list_servers/2` now uses `mcpServerStatus/list` method with automatic fallback to legacy `mcpServers/list` for older servers
- Added `Codex.AppServer.Mcp.list_server_statuses/2` as an alias

### Documentation

- Updated app-server transport guide to reflect removed `thread/compact` API
- Added skills feature flag prerequisite documentation
- Added `.codex/` sandbox read-only behavior note
- Updated config layer schema documentation for `ConfigLayerSource` tagged union
```

#### Task 4.4: Update `mix.exs`

Bump version:
```elixir
# From:
@version "0.3.0"

# To:
@version "0.4.0"
```

### Phase 5: Update Examples

#### Task 5.1: Update `examples/README.md`

Add/update examples documentation:

```markdown
## App-Server Examples

### live_app_server_basic.exs

Demonstrates basic app-server connection, thread creation, and turn execution.

### live_app_server_mcp.exs

Demonstrates MCP server listing with the updated `mcpServerStatus/list` API.

```bash
mix run examples/live_app_server_mcp.exs
```

### Compatibility Notes

These examples require a `codex` binary that supports `codex app-server`.
The SDK automatically handles protocol differences between older and newer
server versions where possible.
```

#### Task 5.2: Create/Update `examples/live_app_server_mcp.exs`

```elixir
#!/usr/bin/env elixir

# Live App-Server MCP Example
# Demonstrates listing MCP servers via the app-server transport.
#
# Usage:
#   mix run examples/live_app_server_mcp.exs
#
# Prerequisites:
#   - CODEX_API_KEY or OPENAI_API_KEY environment variable
#   - codex CLI with app-server support

Mix.install([{:codex, path: "."}])

alias Codex.AppServer
alias Codex.AppServer.Mcp

{:ok, codex_opts} = Codex.Options.new(%{api_key: System.get_env("CODEX_API_KEY") || System.get_env("OPENAI_API_KEY")})

IO.puts("Connecting to codex app-server...")
{:ok, conn} = AppServer.connect(codex_opts, client_name: "mcp_example")

IO.puts("Listing MCP servers...")
case Mcp.list_servers(conn) do
  {:ok, %{"data" => servers}} ->
    IO.puts("Found #{length(servers)} MCP server(s):\n")
    for server <- servers do
      IO.puts("  - #{server["name"]}")
      IO.puts("    Tools: #{map_size(server["tools"] || %{})}")
      IO.puts("    Resources: #{length(server["resources"] || [])}")
      IO.puts("    Auth required: #{server["requiresAuth"]}")
      IO.puts("")
    end

  {:ok, response} ->
    IO.puts("Response: #{inspect(response)}")

  {:error, reason} ->
    IO.puts("Error: #{inspect(reason)}")
end

IO.puts("Disconnecting...")
:ok = AppServer.disconnect(conn)
IO.puts("Done.")
```

#### Task 5.3: Update `examples/run_all.sh`

```bash
#!/bin/bash
set -e

echo "=== Running all Codex SDK examples ==="
echo ""

# Check for API key
if [ -z "$CODEX_API_KEY" ] && [ -z "$OPENAI_API_KEY" ]; then
  echo "Warning: No CODEX_API_KEY or OPENAI_API_KEY set"
  echo "Some examples may fail without authentication"
  echo ""
fi

# Basic examples (no codex binary required)
echo "--- Basic Examples ---"
mix run examples/basic_usage.exs 2>/dev/null || echo "basic_usage.exs: skipped or failed"

# Live examples (require codex binary)
echo ""
echo "--- Live App-Server Examples ---"
echo "These require 'codex app-server' to be available"
echo ""

if command -v codex &> /dev/null; then
  mix run examples/live_app_server_basic.exs 2>/dev/null || echo "live_app_server_basic.exs: failed"
  mix run examples/live_app_server_streaming.exs "Reply with exactly: ok" 2>/dev/null || echo "live_app_server_streaming.exs: failed"
  mix run examples/live_app_server_mcp.exs 2>/dev/null || echo "live_app_server_mcp.exs: failed"
  # Note: approvals example requires interactive input
  echo "live_app_server_approvals.exs: skipped (requires interactive input)"
else
  echo "codex binary not found - skipping live examples"
fi

echo ""
echo "=== Examples complete ==="
```

---

## Success Criteria Checklist

Before considering the task complete, verify ALL of the following:

### Code Quality

- [ ] `mix compile --warnings-as-errors` passes with zero warnings
- [ ] `mix format --check-formatted` passes
- [ ] `mix dialyzer` passes with no errors
- [ ] `mix credo --strict` passes (if credo is configured)

### Tests

- [ ] `mix test` passes with 0 failures
- [ ] New tests added for `thread_compact/2` deprecation behavior
- [ ] New tests added for `Mcp.list_servers/2` fallback behavior
- [ ] Test coverage maintained or improved

### Documentation

- [ ] `docs/09-app-server-transport.md` updated
- [ ] `README.md` version bumped
- [ ] `CHANGELOG.md` entry added for 2025-12-17
- [ ] `mix.exs` version bumped to 0.4.0

### Examples

- [ ] `examples/README.md` updated
- [ ] `examples/live_app_server_mcp.exs` created/updated
- [ ] `examples/run_all.sh` updated
- [ ] All examples in `examples/` directory run without errors (where applicable)

### Final Verification

```bash
# Full verification sequence
mix deps.get
mix compile --warnings-as-errors
mix format --check-formatted
mix test
mix dialyzer

# Run examples (requires codex binary)
chmod +x examples/run_all.sh
./examples/run_all.sh
```

---

## Notes for Agent

1. **Read all required files first** before making any changes
2. **Write tests first** (TDD) - ensure they fail before implementing
3. **Make minimal changes** - don't refactor unrelated code
4. **Preserve backwards compatibility** where possible (fallback for MCP)
5. **Document breaking changes** clearly in CHANGELOG
6. **Run full verification** before marking complete
7. **Do not modify** anything in the `codex/` subtree (vendored upstream)

If you encounter issues with existing tests or code, document them but focus on the changes specified in this prompt. Do not expand scope without explicit approval.
