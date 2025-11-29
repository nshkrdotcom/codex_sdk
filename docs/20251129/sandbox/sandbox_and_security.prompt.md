# Prompt: Update sandbox and security behavior (TDD)

Required reading:
- docs/20251129/sandbox/sandbox_and_security.md
- docs/design/sandbox-approvals.md
- lib/codex/approvals.ex, lib/codex/telemetry.ex, lib/codex/tools/registry.ex (sandbox-aware flows)
- test/codex/approvals_test.exs, test/codex/tools_test.exs

Context to carry:
- Windows sandbox treats `<workspace_root>/.git` as read-only; world-writable scans are refined.
- Approval bypass for policy-approved commands; warning strings adjusted.
- PowerShell `apply_patch` parsing fix; sandbox assessment regression addressed.

Instructions (TDD):
1) Read the docs to capture expected platform-specific behaviors and strings.
2) Add failing tests for Windows read-only `.git` detection, deduped world-writable warnings, and approval bypass logic.
3) Adjust sandbox/approval handling and message normalization to satisfy tests; keep non-Windows paths unchanged.
4) Verify any PowerShell/apply_patch parsing in registry/tooling stays compatible.
5) Run targeted tests then `mix test`; avoid CI-only workflows.
