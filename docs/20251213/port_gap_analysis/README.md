# Port Gap Analysis - December 13, 2025

## Overview

This analysis compares the Elixir `codex_sdk` against its two source codebases:
- **codex/** - TypeScript SDK for Codex CLI
- **openai-agents-python/** - Python SDK for OpenAI Agents

## Documents

| Document | Description |
|----------|-------------|
| [UNPORTED_FEATURES.md](./UNPORTED_FEATURES.md) | Executive summary of gaps and priority rankings |
| [FEATURE_INVENTORY.md](./FEATURE_INVENTORY.md) | Complete feature-by-feature comparison matrix |
| [IMPLEMENTATION_RECOMMENDATIONS.md](./IMPLEMENTATION_RECOMMENDATIONS.md) | Code examples for implementing missing features |

## Key Findings

### Feature Parity: revised downward

The original estimate (~85–90%) overstated parity, primarily due to several Codex CLI (TypeScript SDK)
options and env/flag behaviors that were present in the Elixir structs but were not wired into the
spawned `codex exec` process at the time of the first draft.

**Revised assessment**:
- **High parity for the core “agent loop”** (streaming, tool dispatch, guardrails, handoffs, session
  callbacks, telemetry hooks).
- **High parity with the TypeScript SDK’s CLI option surface** for the commonly used knobs
  (sandbox/cd/add-dir/skip-git/web-search/approval policy/network access + base URL).
- **No parity for Python realtime/voice** (explicitly stubbed).

### Fully Ported Features

- Core agent/thread system
- Tool system with FunctionTool macro
- Guardrails (input, output, tool-specific)
- Handoffs between agents
- MCP client support
- Streaming execution
- Telemetry via OpenTelemetry
- File attachments and search
- Structured output
- Approval workflows (SDK-level tool approvals)
- Session behavior (SDK-level, with in-memory implementation)

### Notable Gaps

| Gap | Priority | Source |
|-----|----------|--------|
| Realtime audio | HIGH (if needed) | Python |
| Voice pipeline (STT/TTS) | HIGH (if needed) | Python |
| Persistent session backends | MEDIUM | Python |
| Lifecycle hooks behavior | MEDIUM | Python |
| Image input ergonomics (typed “local_image” input) | LOW | TypeScript |

### Intentionally Not Ported

- **Shell Tool MCP Server** - Elixir relies on codex binary; standalone MCP server not needed
- **LiteLLM multi-provider** - Codex binary handles model routing
- **Docstring parsing** - Elixir uses explicit schema definition (more type-safe)

## Recommendations

### Immediate (This Sprint)

1. Document Codex CLI continuation semantics (`thread_id` + `resume`), not Python-style response chaining fields
2. Add lifecycle hooks wiring (Elixir fields exist; callbacks are not invoked today)
3. Consider a typed “local image” input for ergonomics (Elixir already supports attachments → `--image`)

### Short-Term (Next Release)

1. Add persistent session backend (ETS or DETS)
2. Define and wire lifecycle hook callbacks (Elixir has `agent.hooks` / `run_config.hooks` fields but they are not invoked today)
3. Clarify/extend hosted tool behavior (wrappers exist; missing pieces are concrete implementations like diff application, computer automation, etc.)

### Medium-Term (Future)

1. Implement realtime/voice if use cases require
2. Add Redis/Ecto session adapters
3. Add ApplyPatch tool for file editing

## Conclusion

The Elixir SDK is **production-ready for text-based workflows** when you treat it as:
- a robust streaming/auto-run orchestrator around the `codex` CLI, plus
- a Python-Agents-inspired tool/guardrail/handoff/session layer.

The main functional gaps are (1) realtime/voice and (2) incomplete forwarding of Codex CLI configuration knobs.

---

## Review Notes

- Date: 2025-12-14
- Summary: Corrected overstated parity, clarified wiring gaps, then implemented Codex CLI forwarding (sandbox/cd/add-dir/skip-git/web-search + base URL env + approval-policy config) to close the largest TypeScript-SDK surface mismatch.
- Confidence: High (validated against `codex exec --help`, `codex --help`, and the local subprocess invocation path in `lib/codex/exec.ex`).
