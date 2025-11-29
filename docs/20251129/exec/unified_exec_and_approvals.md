# Unified exec and approvals changes relevant to the Elixir SDK

What changed upstream:
- Unified exec supports injecting custom environment variables per process.
- A basic pruning strategy and cancellation token were added to trim long-running exec sessions.
- Plan tool defaults remain on in exec; safe commands can bypass approval in workspace-write scenarios.
- Timeout for user shell commands increased (1 hour) and command error messaging was clarified.

SDK impact:
- If the SDK forwards exec calls, surface optional env injection and propagate cancellation tokens.
- Ensure approval gating logic mirrors upstream: safe commands should not request approval when policy allows.
- Pruning or early-exit behavior may change ordering of streamed output; tighten tests that assume full output.

Action items:
- Add fields for `env` and `cancellation_token` (or equivalent) to exec call structs/options.
- Revisit approval path handling to align with the “safe command bypass” behavior.
- Run integration tests that stream exec output to confirm pruning does not break consumers.
