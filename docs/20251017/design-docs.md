# Remaining Work Design Notes (2025-10-17)

## 1. Release Hardening

- **Semantic Versioning Prep**
  - Draft `CHANGELOG.md` entry summarising milestones M1–M5.
  - Bump `VERSION` file and `mix.exs` metadata prior to Hex publish.
  - Verify `mix hex.publish --dry-run` succeeds on macOS and Linux.
- **Packaging Audit**
  - Ensure `mix release` bundle vendors required native assets (none presently, but confirm erlexec build artifacts are excluded).
  - Double-check `mix.exs` `files:` list includes `docs/20251017/` for source releases.

## 2. Extended Testing Matrix

- **Cross-Platform Smoke Tests**
  - Run `mix codex.verify` on macOS (arm64) and Linux (x86_64).
  - Exercise `mix run examples/live_cli_demo.exs` on each platform to confirm CLI auth heuristics.
- **Long-Running Sessions**
  - Execute auto-run loops against fixtures with >3 continuations.
  - Stream 30+ event payloads to validate memory profile under erlexec-managed ports.
- **Regression Harness**
  - Wire `mix codex.parity` into nightly automation (GitHub Actions).
  - Store parity output artefacts for manual inspection.

## 3. Documentation Polish

- Refresh README badge versions post-release.
- Embed the live CLI flow inside `docs/06-examples.md` with prerequisites.
- Convert milestone completion tables into the project wiki for external sharing.

## 4. Observability & Ops

- Instrument `Codex.Exec` with optional timing metadata (execution start/stop) feeding into `Codex.Telemetry`.
- Draft runbook describing how to tail erlexec-managed processes and rotate `_build/codex_files` staging directories.
- Evaluate exporting telemetry to OTLP collector; document configuration knobs.
- Detailed design: `docs/20251017/observability-timing.md`

## 5. Future Enhancements (Backlog)

- **Configurable Sandbox Hooks** – see `docs/20251017/sandbox-hooks.md`
- **Tool Execution Metrics** – see `docs/20251017/tool-metrics.md`
- **Attachment Lifecycle Manager** – see `docs/20251017/attachment-lifecycle.md`

### Acceptance Gate

- All items above flagged complete in `docs/python-parity-checklist.md`.
- `mix codex.verify` green across targeted platforms.
- Release tag signed & pushed (`git tag -s v0.1.0 && git push origin v0.1.0`).
