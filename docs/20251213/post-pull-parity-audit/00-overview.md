# Upstream Parity Audit (Post Pull) — 2025-12-13

This directory documents what changed in the two upstream projects we vendor for reference
(`openai-agents-python/` and `codex/`) and what is *actually applicable* to this Elixir SDK.

It is intentionally transport-aware: most upstream changes land in components that are **not**
reachable through the SDK’s current integration path.

## What “upstream parity” means for this repo

This SDK wraps the upstream **Codex CLI** by running:

- `codex exec --experimental-json` (JSONL events on stdout)

This is the only supported transport today. It is **not** the app-server protocol, and it does
not expose most protocol/app-server-only features.

## Why the upstream diffs are huge but our changelog is small

You pulled:

- `openai-agents-python` `0d2d771..71fa12c` — ~112 files changed, but the vast majority are
  translated docs (`docs/ja`, `docs/ko`, `docs/zh`). Runtime changes are concentrated in a
  handful of `src/agents/*` modules.
- `codex` `6eeaf46ac..a2c86e5d8` — ~1189 files changed, dominated by TUI2, sandboxing, Windows
  support, app-server protocol, and internal refactors. Only a small slice affects `codex exec`
  JSON output (our transport) or CLI flags we can pass.

Our changelog is scoped to *user-facing* behavior in the Elixir SDK (API options, docs, examples,
and compatibility). Most upstream code churn does not translate into SDK changes until it becomes
observable via `codex exec --experimental-json` or we adopt a new transport.

## Transport reality check: exec JSONL schema

The canonical schema for `codex exec --experimental-json` is defined upstream at:

- `codex/codex-rs/exec/src/exec_events.rs`

Key points:

- `thread.started` only guarantees `thread_id`.
- `turn.started` contains no IDs.
- `turn.completed` contains only `usage` (no final response, no response_id).
- Per-turn content is delivered as `item.*` events with an `item` payload like:
  - `{"id":"item_0","type":"reasoning","text":"…"}`
  - `{"id":"item_1","type":"agent_message","text":"…"}`

This matters because “agents-python parity” features like `auto_previous_response_id` require a
backend `response_id` signal that **exec JSONL does not currently emit**.

## What’s already implemented in Elixir (high signal)

As of SDK `0.2.4`:

- `Codex.RunConfig` accepts `auto_previous_response_id` and validates it.
- The runner tracks the most recent backend `response_id` **when present** and can chain it as
  `previous_response_id` between internal turns when `auto_previous_response_id` is enabled.
- A small, opt-in `:live` ExUnit suite exists for sanity checks against a real `codex` binary.

## What this directory contains

- `01-agents-python-delta.md`: code-level deltas in `openai-agents-python` and applicability.
- `02-codex-rs-delta.md`: deltas in `codex` with an exec-transport lens.
- `03-sdk-gap-matrix.md`: feature-by-feature status (done/partial/missing/not-applicable).
- `04-execution-plan.md`: a TDD-first roadmap to close the remaining applicable gaps.
