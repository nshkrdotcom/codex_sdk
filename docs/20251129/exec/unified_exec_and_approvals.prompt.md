# Prompt: Align unified exec and approvals with upstream (TDD)

Required reading:
- docs/20251129/exec/unified_exec_and_approvals.md
- docs/observability-runbook.md (exec telemetry expectations)
- lib/codex/exec.ex, lib/codex/approvals.ex, lib/codex/telemetry.ex (exec handling, approvals, signals)
- test/codex/exec_test.exs, test/codex/approvals_test.exs, test/codex/telemetry_test.exs

Context to carry:
- Exec now supports per-process env injection and cancellation tokens.
- Pruning/early-exit may reorder or trim streamed output.
- Safe commands in workspace-write can bypass approval; user shell timeout is longer.

Instructions (TDD):
1) Study the docs to pin the expected behavior (env, cancellation, pruning, approval bypass).
2) Add failing tests covering env injection, cancellation token propagation, safe-command bypass, and timeout messaging.
3) Implement exec option structs and approval gating to satisfy tests; avoid breaking legacy paths.
4) Ensure telemetry/logging reflects pruning/early-exit scenarios.
5) Re-run targeted tests then `mix test`; keep changes scoped to SDK exec/approval layers.
