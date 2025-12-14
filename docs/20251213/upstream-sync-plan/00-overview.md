# Upstream Sync Plan - December 2025

## Overview

This document set provides a comprehensive plan for synchronizing the Elixir codex_sdk port with the latest upstream changes from two official OpenAI projects:

1. **openai-agents-python** - The OpenAI Agents Python SDK (v0.6.2 → v0.6.3)
2. **codex** - The OpenAI Codex CLI (codex-rs)

## Upstream Versions Analyzed

### openai-agents-python
- **Previous Commit (baseline)**: `0d2d771` (not tagged; precedes `v0.6.2`)
- **Current Commit**: `71fa12c` (post-`v0.6.3`; example-only change)
- **Tags Within Range**: `v0.6.2` (`9fcc68f`), `v0.6.3` (`8e1fd7a`)
- **OpenAI SDK Dependency**: Bumped to `openai==2.9.0` (`5f2e83e`)

### codex (codex-rs)
- **Previous Commit**: `6eeaf46ac`
- **Current Commit**: `a2c86e5d8`
- **Key Tags**: rust-v0.73.0-alpha.1

## Document Index

| Document | Description |
|----------|-------------|
| [01-agents-python-changes.md](./01-agents-python-changes.md) | Detailed analysis of Python SDK changes |
| [02-codex-rs-changes.md](./02-codex-rs-changes.md) | Detailed analysis of Codex CLI changes |
| [03-elixir-port-gaps.md](./03-elixir-port-gaps.md) | Gap analysis vs current Elixir implementation |
| [04-porting-requirements.md](./04-porting-requirements.md) | Prioritized porting requirements |
| [05-implementation-plan.md](./05-implementation-plan.md) | Step-by-step implementation plan |
| [06-agent-implementation-prompt.md](./06-agent-implementation-prompt.md) | TDD prompt for implementing this plan |

## Summary of Key Changes

### High-Priority Changes (Actionable Now)

#### From agents-python:
1. **Response Chaining** (`auto_previous_response_id`) - Enables server-side `previous_response_id` mode starting on the first internal call (`a9d95b4`) (full parity is backend-dependent)

#### From codex-rs:
1. **OTEL Telemetry Export** - OpenTelemetry exporter support (disabled by default) (`ad7b9d63c`)

### Medium-Priority Changes (Transport-Dependent / Consider Porting)

1. **Skills** - Skill discovery + runtime “## Skills” injection; explicit SKILL.md injection (`b36ecb6c3`, `60479a967`)
2. **Remote Models (ModelsManager)** - `/models` discovery with TTL + ETag cache (`00cc00ead`, `222a49157`, `53a486f7e`)
3. **Config Loader + Config Service** - Layered config loading with sha256 versions and RPC-style edits (`92098d36e`)
4. Review mode + unified exec event refactors (SDK exposure depends on transport) (`4b78e2ab0`, `0ad54982a`)
5. AbsolutePathBuf sandbox config (only relevant if the SDK exposes writable roots) (`642b7566d`)

### Low-Priority / Blocked / Non-Applicable

1. Logprobs preservation (chat completions) (`df020d1`) — blocked unless backend surfaces logprobs
2. Usage normalization (`509ddda`) — N/A for current Elixir usage shape
3. Apply-patch context (`9f96338`) — only relevant if the SDK exposes host patch hooks
4. Shell snapshotting (`7836aedda`, `29381ba5c`) — backend-internal / typically docs-only
5. Documentation translations (ja, ko, zh)
6. TUI snapshot test updates
7. Platform-specific signing (macOS, Windows)
8. Internal refactors without SDK-facing changes

## Current Elixir Port Status

- **Version**: 0.2.3
- **Elixir Source Files**: 46 (`lib/*.ex` and `lib/codex/*.ex`)
- **Key Features**: Thread lifecycle, streaming, tools, approvals, guardrails, sessions

## Porting Approach

The recommended approach is to:
1. Decide the codex integration surface (exec JSONL vs core/app-server protocol)
2. Port actionable agents-python changes (e.g., `auto_previous_response_id` API) and document backend limits
3. Align observability docs (codex-rs OTEL via `config.toml` vs Elixir-side OTLP export)
4. If adopting protocol/app-server, implement models/skills/config/review features in phases with tests

## Timeline Estimate

This document provides implementation requirements without timeline estimates. Each feature can be implemented independently, allowing flexible scheduling based on team priorities.
