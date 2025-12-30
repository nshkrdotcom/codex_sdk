# Codex SDK Gap Analysis: Elixir vs Canonical Codex

**Date:** 2025-12-30
**Current Elixir Version:** 0.4.4
**Target Version:** 0.4.5

## Executive Summary

This document identifies gaps between the canonical `./codex` (Rust/TypeScript) implementation and the Elixir `codex_sdk` port. The analysis excludes `codex-rs` runtime bundling (explicitly out of scope).

---

## 1. Feature Parity Status

### 1.1 Fully Implemented (No Gaps)

| Feature | Elixir Module | Status |
|---------|---------------|--------|
| Basic thread management | `Codex.Thread` | Complete |
| Exec JSONL transport | `Codex.Transport.ExecJsonl` | Complete |
| App-Server transport | `Codex.Transport.AppServer` | Complete |
| Event streaming | `Codex.RunResultStreaming` | Complete |
| Approval hooks | `Codex.Approvals.Hook` | Complete |
| Static approval policies | `Codex.Approvals.StaticPolicy` | Complete |
| Tool registry | `Codex.Tools.Registry` | Complete |
| File staging | `Codex.Files` | Complete |
| Session persistence | `Codex.Session` | Complete |
| Config layer stack | `Codex.Config.LayerStack` | Complete |
| Model settings | `Codex.ModelSettings` | Complete |
| Telemetry integration | `Codex.Telemetry` | Complete |
| Multi-modal inputs | `Codex.AppServer.Params` | Complete |

### 1.2 Partially Implemented (Gaps Exist)

| Feature | Current State | Gap |
|---------|---------------|-----|
| MCP Client | Basic handshake only | Missing tool discovery, call_tool, OAuth flows |
| Tool Guardrails | Basic structure | Missing parallel execution, tripwire semantics |
| Hosted Tools | Structure exists | Missing shell, apply_patch, computer tools |
| Error Handling | Basic types | Missing retry logic, rate limit handling |
| Voice Support | Stub only | Returns `:unsupported_feature` |

### 1.3 Missing Features

| Feature | Priority | Effort |
|---------|----------|--------|
| Full MCP tool discovery | HIGH | Medium |
| MCP call_tool with retries | HIGH | Medium |
| Shell hosted tool | HIGH | Low |
| ApplyPatch hosted tool | HIGH | Low |
| Computer hosted tool | LOW | Medium |
| Web search hosted tool | MEDIUM | Low |
| Image generation hosted tool | LOW | Low |
| Code interpreter hosted tool | LOW | Medium |
| Retry logic with backoff | MEDIUM | Medium |
| Rate limit detection/handling | MEDIUM | Low |
| Full OAuth flow for MCP | LOW | High |

---

## 2. Detailed Gap Analysis

### 2.1 MCP Integration Gaps

**Current State:**
- `Codex.MCP.Client` has basic handshake
- `Codex.AppServer.Mcp` has `list_servers/2`

**Missing:**
1. **Tool Discovery** (`list_tools/2`)
   - Need to call MCP server to enumerate tools
   - Apply allow/block list filtering
   - Cache tool list per session
   - Handle tool name collision (64-char limit with SHA1 suffix)

2. **Tool Invocation** (`call_tool/4`)
   - Execute tool with arguments
   - Retry logic with exponential backoff
   - Timeout handling
   - Approval integration

3. **OAuth Flows**
   - Device code flow
   - Token storage/refresh
   - Per-server auth status

**Reference Files:**
- `codex/codex-rs/core/src/mcp_connection_manager.rs`
- `codex/codex-rs/rmcp-client/src/rmcp_client.rs`
- `openai-agents-python/src/agents/mcp/server.py`

### 2.2 Hosted Tools Gaps

**Current State:**
- `Codex.Tools.HostedTools` module exists but is sparse
- Shell tool structure exists but incomplete

**Missing Implementations:**

1. **ShellTool** (`shell`)
   - Execute shell commands via subprocess
   - Capture stdout/stderr with truncation
   - Exit code handling
   - Approval hooks for command execution
   - Timeout support

2. **ApplyPatchTool** (`apply_patch`)
   - Apply unified diffs to files
   - Base path resolution
   - Approval for file modifications

3. **FileSearchTool** (`file_search`)
   - Vector store integration
   - Filter and ranking options
   - Include search results option

4. **WebSearchTool** (`web_search`)
   - Web search query
   - Result formatting

5. **ImageGenerationTool** (`image_generation`)
   - Prompt-based image generation
   - Size/quality parameters

6. **CodeInterpreterTool** (`code_interpreter`)
   - Sandbox code execution
   - Output capture

7. **ComputerTool** (`computer`)
   - Screen interaction simulation
   - Currently stubbed in canonical

### 2.3 Error Handling Gaps

**Current State:**
- Basic error types in `Codex.Error`
- Transport errors in `Codex.TransportError`

**Missing:**

1. **Retry Logic**
   - No automatic retry on transient failures
   - Need exponential backoff implementation
   - Max retries configuration

2. **Rate Limit Handling**
   - Detection of `rate_limit_exceeded` errors
   - Backoff strategy
   - User notification

3. **Timeout Handling**
   - Stream idle timeout (canonical: 300s default)
   - Per-request timeout configuration
   - Graceful timeout recovery

### 2.4 Tool Guardrail Gaps

**Current State:**
- `Codex.Guardrail` basic structure
- `Codex.ToolGuardrail` for tool-specific guards

**Missing:**

1. **Parallel Execution**
   - `run_in_parallel` flag exists but not implemented
   - Need concurrent guardrail evaluation

2. **Tripwire Semantics**
   - `{:tripwire, message}` result type defined
   - Tripwire escalation not fully implemented

3. **Tool Input/Output Guardrails**
   - Pre-invocation validation
   - Post-invocation validation
   - Integration with approval chain

### 2.5 Streaming Gaps

**Current State:**
- `Codex.RunResultStreaming` fully implements event streaming
- Delta events supported

**Missing:**

1. **Backpressure Signaling**
   - No explicit flow control to producer
   - Consumer pacing only

2. **Connection Recovery**
   - No automatic reconnection on stream breaks
   - Would require transport-level retry

### 2.6 CLI Feature Forwarding Gaps

**Current State:**
- Most CLI flags forwarded via `Codex.Exec`

**Missing/Incomplete:**

1. **Review Mode**
   - `review --uncommitted` partially supported
   - `review --base branch` needs verification
   - `review --commit sha` needs verification

2. **Resume Enhancements**
   - Resume with new prompt
   - Session ID resolution

---

## 3. Event Type Gaps

### 3.1 Missing Event Types

| Event | Status | Notes |
|-------|--------|-------|
| `McpToolCallProgress` | Defined but unused | Need MCP integration |
| `TerminalInteraction` | Not implemented | Real-time stdin writes |
| `McpServerOauthLoginCompleted` | Not implemented | OAuth flow |
| `AccountRateLimitsUpdated` | Partially | Need rate limit tracking |

### 3.2 Delta Event Handling

| Delta Type | Status |
|------------|--------|
| `CommandOutputDelta` | Defined, handled |
| `FileChangeOutputDelta` | Defined, handled |
| `ReasoningDelta` | Defined, handled |
| `ReasoningSummaryDelta` | Defined, handled |
| `ReasoningSummaryPartAdded` | Defined, needs testing |

---

## 4. Configuration Gaps

### 4.1 Missing Config Options

| Option | Location | Status |
|--------|----------|--------|
| `stream_max_retries` | Provider config | Not exposed |
| `stream_idle_timeout` | Provider config | Not exposed |
| `retry_429` | Provider config | Not exposed |
| `retry_5xx` | Provider config | Not exposed |

### 4.2 Environment Variables

| Variable | Status |
|----------|--------|
| `CODEX_HOME` | Supported |
| `CODEX_PATH` | Supported |
| `CODEX_API_KEY` | Supported |
| `CODEX_MODEL` | Supported |
| `CODEX_OTLP_*` | Supported |
| Stream retry env vars | Not implemented |

---

## 5. Test Coverage Gaps

### 5.1 Missing Test Categories

1. **MCP Integration Tests**
   - Tool discovery tests
   - Tool invocation tests
   - OAuth flow tests

2. **Hosted Tool Tests**
   - Shell tool execution tests
   - ApplyPatch tool tests
   - File search tests

3. **Error Recovery Tests**
   - Retry logic tests
   - Rate limit handling tests
   - Timeout recovery tests

4. **Property-Based Tests**
   - Event parsing properties
   - Config validation properties

### 5.2 Live Test Gaps

| Test | Status |
|------|--------|
| MCP server integration | Missing |
| Multi-modal input (images) | Needs expansion |
| Concurrent thread execution | Needs expansion |

---

## 6. Documentation Gaps

### 6.1 Missing Documentation

1. **MCP Integration Guide**
   - Server configuration
   - Tool discovery
   - OAuth setup

2. **Hosted Tools Guide**
   - Shell tool usage
   - ApplyPatch patterns
   - Custom tool creation

3. **Error Handling Guide**
   - Retry strategies
   - Rate limit handling
   - Timeout configuration

### 6.2 Examples Gaps

| Example | Status |
|---------|--------|
| MCP tool discovery | Missing |
| Custom hosted tool | Missing |
| Retry with backoff | Missing |
| Rate limit handling | Missing |

---

## 7. Implementation Priority

### Phase 1: Critical (0.4.5)

1. **MCP Tool Discovery** - Enable tool listing from MCP servers
2. **MCP Tool Invocation** - Enable calling MCP tools
3. **Shell Hosted Tool** - Execute shell commands
4. **ApplyPatch Hosted Tool** - Apply file patches
5. **Retry Logic** - Add exponential backoff

### Phase 2: Important (0.4.6)

1. **Rate Limit Handling** - Detect and handle rate limits
2. **FileSearch Hosted Tool** - Vector search
3. **WebSearch Hosted Tool** - Web search
4. **Tool Guardrail Parallel Execution** - Concurrent validation
5. **OAuth Flows** - Full MCP OAuth support

### Phase 3: Nice-to-Have (0.5.0)

1. **ImageGeneration Hosted Tool** - Image creation
2. **CodeInterpreter Hosted Tool** - Sandbox execution
3. **ComputerTool** - Screen interaction
4. **Stream Backpressure** - Flow control
5. **Voice Support** - Audio I/O

---

## 8. Recommended Prompt Sequence

Based on this analysis, the following prompts should be executed sequentially:

1. `01-mcp-tool-discovery.md` - MCP list_tools implementation
2. `02-mcp-tool-invocation.md` - MCP call_tool implementation
3. `03-shell-hosted-tool.md` - Shell tool implementation
4. `04-apply-patch-tool.md` - ApplyPatch tool implementation
5. `05-retry-and-backoff.md` - Retry logic implementation
6. `06-rate-limit-handling.md` - Rate limit detection
7. `07-file-search-tool.md` - FileSearch tool implementation
8. `08-web-search-tool.md` - WebSearch tool implementation

Each prompt specifies TDD approach, required reading, and verification criteria.
