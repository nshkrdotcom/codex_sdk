# Complete Codex Documentation Porting Matrix

## Overview

This document maps every documentation file in the upstream codex repository to its “ported” status in `codex_sdk`:
- either **first-class** via the Elixir API, or
- **pass-through** via the upstream `codex` binary (which `codex_sdk` shells out to).

## Documentation Locations

- **Upstream User Docs**: `codex/docs/` (22 files)
- **Upstream Technical Docs**: `codex/codex-rs/docs/` (2 files)
- **Elixir SDK Docs**: `codex_sdk/docs/` (gap analysis, plans)

## Full Porting Matrix

### User Documentation (codex/docs/)

| Document | Topic | Elixir Status | Notes |
|----------|-------|---------------|-------|
| `experimental.md` | Beta disclaimer | N/A | Not applicable to SDK |
| `install.md` | Installation | N/A | Different install (hex) |
| `getting-started.md` | Quick start | ⚠️ Partial | Different interface |
| `agents_md.md` | AGENTS.md discovery | ✅ Supported | Implemented by upstream `codex` core; available via `codex exec` |
| `config.md` | Configuration reference | ⚠️ Partial | SDK exposes a subset; full support via upstream `config.toml` |
| `example-config.md` | Sample config | ⚠️ Partial | Supported via upstream `config.toml`; SDK doesn’t generate it |
| `prompts.md` | Custom prompts | ❌ Not Ported | CLI feature |
| `slash_commands.md` | Slash commands | ❌ Not Ported | CLI feature |
| `sandbox.md` | Sandbox modes | ⚠️ Partial | Via exec binary |
| `platform-sandboxing.md` | Platform details | ⚠️ Partial | Via exec binary |
| `windows_sandbox_security.md` | Windows sandbox | ❌ Not Ported | Platform-specific |
| `exec.md` | Non-interactive mode | ✅ Implemented | Core SDK functionality |
| `advanced.md` | Advanced config | ⚠️ Partial | MCP client exists |
| `authentication.md` | Login/auth | ⚠️ Partial | API key or existing CLI login; SDK doesn’t run login flows |
| `zdr.md` | Zero data retention | ✅ Transparent | Works via API |
| `skills.md` | Skills feature | ⚠️ Partial | Available via upstream `features.skills`; SDK doesn’t surface list/errors |
| `execpolicy.md` | Execution policies | ❌ Not Ported | CLI feature |
| `faq.md` | FAQ | N/A | CLI-specific |
| `license.md` | License | N/A | Same Apache-2.0 |
| `CLA.md` | Contributor agreement | N/A | Not code |
| `contributing.md` | Contribution guide | N/A | Not code |
| `open-source-fund.md` | Funding info | N/A | Not code |

### Technical Documentation (codex-rs/docs/)

| Document | Topic | Elixir Status | Notes |
|----------|-------|---------------|-------|
| `protocol_v1.md` | Core protocol spec | ⚠️ Abstracted | Hidden behind exec |
| `codex_mcp_interface.md` | MCP server interface | N/A | SDK is not a Codex MCP server |

## Feature Coverage Analysis

### Fully Implemented in Elixir

| Feature | Rust Location | Elixir Location |
|---------|--------------|-----------------|
| Exec mode | `exec/` | `lib/codex/exec.ex` |
| Thread/Turn model | `core/` | `lib/codex/thread.ex` |
| Agent runner | `core/` | `lib/codex/agent_runner.ex` |
| Tools system | `core/` | `lib/codex/tools.ex` |
| Approvals | `core/` | `lib/codex/approvals.ex` |
| Guardrails | `core/` | `lib/codex/guardrail.ex` |
| Handoffs | `core/` | `lib/codex/handoff.ex` |
| Events | `protocol/` | `lib/codex/events.ex` |
| Session | `core/` | `lib/codex/session.ex` |
| MCP client | `rmcp-client/` | `lib/codex/mcp/client.ex` |
| Streaming | Various | `lib/codex/stream_*.ex` |
| Telemetry | Various | `lib/codex/telemetry.ex` |

### Partially Implemented

| Feature | What Works | What's Missing |
|---------|-----------|----------------|
| Sandbox | Via exec binary | Direct API control |
| Config | Elixir options | TOML parsing |
| Auth | API key + existing CLI login | SDK does not run ChatGPT OAuth flow |
| Protocol | Event subset | Full Op/Event set |

### Not Implemented

| Feature | Blocked By | Priority |
|---------|-----------|----------|
| Skills list API (`Op::ListSkills` / `skills/list`) | Transport (core/app-server) | Medium |
| Slash commands | CLI-only | N/A |
| Custom prompts | CLI-only | N/A |
| Execution policies | CLI-only | Low |
| Windows sandbox | Platform-specific | Low |

## Configuration Comparison

### Implemented Config Options

| Rust Config | Elixir Equivalent |
|-------------|------------------|
| `model` | `Codex.Options.model` |
| `model_reasoning_effort` | `Codex.Options.reasoning_effort` |
| `approval_policy` | `Codex.Thread.Options.ask_for_approval` |
| `sandbox_mode` | `Codex.Thread.Options.sandbox` |
| `mcp_servers` | `Codex.MCP.Client` config |

### Not Implemented Config Options

| Rust Config | Reason |
|-------------|--------|
| `profile` | CLI feature |
| `shell_environment_policy` | Handled by exec |
| `project_doc_*` | Supported via upstream `config.toml` (not exposed as Elixir opts) |
| `file_opener` | TUI feature |
| `tui.*` | TUI feature |
| `otel.*` | Different telemetry |

## Protocol Event Coverage

### Events Exposed via Exec JSONL

| Event | Elixir Type |
|-------|-------------|
| `thread.started` | `Codex.Events.ThreadStarted` |
| `turn.started` | `Codex.Events.TurnStarted` |
| `turn.completed` | `Codex.Events.TurnCompleted` |
| `turn.failed` | `Codex.Events.TurnFailed` |
| `item.started` | - (handled internally) |
| `item.updated` | `Codex.Events.ItemAgentMessageDelta` |
| `item.completed` | `Codex.Events.ItemCompleted` |
| `error` | `Codex.Error` |

### Events NOT Exposed via Exec JSONL

| Event | Would Require |
|-------|--------------|
| `SessionConfigured` | Core protocol |
| `ListSkillsResponse` | Core protocol |
| `ExecApprovalRequest` | Core protocol |
| `PatchApprovalRequest` | Core protocol |
| `TurnCompaction` | Core protocol |

## Documentation Gaps to Address

### Should Create for Elixir SDK

1. **Quick Start Guide** - Elixir-specific getting started
2. **Configuration Reference** - Elixir options documentation
3. **API Reference** - Module documentation (ExDoc)
4. **Event Types Reference** - Map to Rust events
5. **Example Usage** - Elixir examples (already have some)

### Not Needed for Elixir SDK

1. Installation via cargo/brew (use hex)
2. TUI-specific documentation
3. Slash commands documentation
4. Windows sandbox security internals (CLI-only)
5. MCP server interface (server-only)

## Recommendations

### High Priority Documentation

1. **Port exec.md concepts** - Elixir SDK's primary interface
2. **Create options reference** - Document Codex.Options, Codex.Thread.Options, Codex.Exec.Options
3. **Document event mapping** - How Rust events map to Elixir

### Medium Priority

1. **MCP integration guide** - Using MCP servers from Elixir
2. **Approvals/Guardrails guide** - SDK-specific patterns
3. **Streaming guide** - How to use run_streamed

### Low Priority

1. **Skills documentation** - When/if implemented
2. **Protocol deep dive** - For contributors only

## Summary Statistics

| Category | Count | Status |
|----------|-------|--------|
| Total upstream docs | 24 | - |
| Not applicable to SDK | 8 | N/A |
| Fully covered | 3 | ✅ |
| Partially covered | 9 | ⚠️ |
| Not ported | 4 | ❌ |
