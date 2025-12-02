# ADR-013: Testing Strategy for Python Parity

Status: Proposed

Context
- Python suite covers runner loops, guardrails, tool behaviors, MCP, sessions, streaming errors, tracing, handoffs, structured outputs, and hosted tools (see `tests/*` inventory). Elixir tests focus on codex exec, attachments, auto-run, and basic tools.

Decision
- Establish parity test matrix mirroring Python categories: runner/loop, guardrails, function tools/structured outputs, hosted tools (shell/apply_patch/computer/search), MCP (filters/retries/tracing), sessions/resume, streaming/cancel, tracing/usage, approvals/safety.
- Port or reimplement fixtures (fake models, simple sessions, MCP helpers, shell/editor mocks) in Elixir test support; add codex-specific fixtures where needed.
- Track parity progress with coverage tags and CI gating once core suites pass.

Consequences
- Benefits: confidence in parity claims; clear migration progress tracking.
- Risks: test volume and runtime increase; some tests may need codex stubs/mocks if binary lacks features.
- Actions: draft parity test plan per category; implement fixtures; wire CI jobs; align with docs in `docs/20251202/python-parity/*` and migration plan.
