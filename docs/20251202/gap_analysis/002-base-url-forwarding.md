# ADR 002: Honor base_url when spawning codex exec

- Status: Proposed
- Date: 2025-12-02

## Context
- The upstream SDK sets `OPENAI_BASE_URL` when a custom base URL is provided (codex/sdk/typescript/src/exec.ts:109-128).
- Elixir exposes `base_url` on `Codex.Options` (lib/codex/options.ex:11-54) but `Codex.Exec.build_env/1` only forwards API keys and the originator override (lib/codex/exec.ex:271-281). No environment variable reflects the configured base URL.

## Problem
- Elixir callers cannot target alternative API hosts even though the option exists. This breaks parity with Python/TypeScript behavior and makes the `base_url` field effectively dead code.

## Decision
- Propagate `Codex.Options.base_url` into the child process environment (e.g., `OPENAI_BASE_URL`) mirroring the upstream SDK.
- Add guardrails so custom env overrides still merge cleanly with the derived base URL.

## Actions
- Extend env construction tests to assert base URL propagation and to catch regressions.
- Update public docs to clarify how to point the SDK at non-default Codex endpoints.
