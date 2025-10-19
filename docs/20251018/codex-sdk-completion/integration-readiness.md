# Integration & Release Readiness Plan

This guide outlines the remaining operational work to integrate the Elixir Codex SDK into production environments and release it as a Hex package.

## Dependency Management Tasks
- Add `vendor/codex` git submodule with sparse checkout of `codex-rs`.
- Implement `Mix.Tasks.Codex.Install` to build/download codex binaries.
- Store version pins in `config/native.exs` and expose via `Codex.Native.version/0`.
- Document build prerequisites (Rust toolchain, optional prebuilt download).

## Configuration & Auth
- Finalize environment variable contract (`CODEX_API_KEY`, `CODEX_BASE_URL`, `CODEX_PATH`).
- Implement runtime validation and helpful error messages for missing creds.
- Provide README section describing Hex package configuration and OTP release integration.

## Release Packaging
- Split native binaries into optional Hex package (`codex_sdk_native`) or attach to GitHub releases.
- Update `mix.exs` `package[:files]` list once module scaffolding complete.
- Automate changelog generation linked to milestone completion.

## Documentation Deliverables
- Update `README.md` with comprehensive getting started examples (blocking, streaming, tools).
- Generate HexDocs with module docs for newly added namespaces (`Codex.Tools`, `Codex.Files`, etc.).
- Maintain parity checklist (`docs/python-parity-checklist.md`) through release sign-off.

## Operational Readiness
- Provide sample supervision tree for integrating Codex SDK into host applications.
- Document telemetry events and recommended dashboards.
- Supply sandbox/approval policy examples for security review.

## Release Checklist (Pre-1.0)
1. All milestones M0–M5 marked complete with passing tests.
2. Contract suite green across Python + Elixir comparisons.
3. CI matrix (Linux/macOS) fully passing with coverage, credo, dialyzer.
4. HexDocs published and README updated.
5. Codex binary version pin documented; release artifacts signed.

## Post-Release Follow-Up
- Monitor telemetry from early adopters; gather feedback on API ergonomics.
- Track upstream Python/Rust changes; schedule parity audits quarterly.
- Plan 1.1 milestone for Chaos/Performance helpers integration (optional).
