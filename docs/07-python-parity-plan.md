# Python Feature Parity Plan

## Context & Research
- Requirement: deliver a 100% feature-parity Elixir port of the Python Codex SDK (openai-agents-python), which itself shells out to `codex-rs`.
- Local audit: the repo already mirrors TypeScript SDK semantics (streaming vs buffered turns, structured outputs, resume support) and ships with comprehensive TDD documentation (`docs/03-implementation-plan.md`, `docs/04-testing-strategy.md`) plus an OTP-centric architecture guide (`docs/02-architecture.md`).
- Gap: the Python client source is not vendored here; we must study its public repo (modules like `codex.client`, `codex.threads`, `codex.tools`, auto-run orchestration) to capture feature surface: session persistence, command approvals, attachments, tool/mcp support, structured responses, sandbox controls, telemetry hooks, error domains.
- Evidence inside `codex/` confirms `codex-rs` is the canonical Rust engine. Both CLI and TypeScript SDK consume it as a subprocess via JSONL event streams; parity requires replicating the Python abstractions atop the same protocol.

## Dependency Management Recommendation
1. **Submodule the Rust Engine**  
   - Add `openai/codex` as a git submodule, but use sparse checkout to pull only `codex-rs/**` (Rust workspace) plus `codex-rs/scripts` for release tooling.  
   - Rationale: keeps us aligned with upstream Rust changes without inheriting Python/TypeScript-specific glue, preserves a clean update path (`git submodule update --remote`), and avoids vendoring redundant SDKs.
2. **Thin Mix Wrapper**  
   - Create a `native/codex_rs` mix namespace responsible for compiling / downloading the binary. Prefer building from source via `cargo build --release` gated behind `MIX_ENV=dev` to keep CI deterministic. Cache artifacts under `_build/codex_rs`.  
   - Provide `mix codex.install` that: ensures Rust toolchain (`rustup`, `cargo`) exists, runs the sparse submodule build, and writes platform-specific binaries into `priv/codex/`.
3. **Optional Prebuilt Fallback**  
   - Mirror the Python client’s wheel strategy: allow `MIX_ENV=prod` to download signed release zips from upstream if local Rust toolchain is unavailable. Keep this behind an opt-in flag to avoid default network calls.
4. **Isolation Guarantees**  
   - Treat the submodule as read-only; any patches live under `patches/codex-rs/*.patch` applied during build so we can rebase cleanly.  
   - Expose version pin in `config/native.exs` so we can coordinate updates across Python/TypeScript ports.

## Feature Parity Inventory
| Python Capability | Elixir Workstream | Notes |
|-------------------|-------------------|-------|
| Thread lifecycle (`start_thread`, `resume_thread`) | Align existing `Codex` / `Codex.Thread` structs with Python semantics (thread metadata, continuation tokens). | Verify Python exposes mutable thread options mid-session. |
| Turn execution (`run`, `run_streamed`, auto-run) | Expand `Codex.Thread` API to support auto-run (loop until success), piping tool calls back. | Requires event-driven state machine mirroring Python’s `RealtimeTurn`. |
| Event model (items: agent_message, reasoning, tool, file diffs) | Finish typed structs + conversions; ensure JSON enums match Python contract. | Reuse JSONL schema from TypeScript docs. |
| Tool / MCP integration | Implement tool registration layer mirroring Python’s decorators; wrap Rust MCP protocol (already exposed in `codex-rs`). | Needs Elixir behaviours + supervision for external servers. |
| Attachments & file uploads | Provide APIs for ephemeral file staging before invoking turns; align with Python `client.files`. | Likely orchestrated via `codex-rs` file API endpoints. |
| Sandbox & approvals | Surface sandbox modes / approval callbacks for command execution; expose hooks to accept/refuse. | Requires intercepting `command_execution` items and optionally halting turn. |
| Structured output | Already partially covered; confirm schema validation & error reporting match Python. | Add contract tests referencing Python examples. |
| Telemetry / logging | Mirror Python logging hooks (callbacks/events) using `:telemetry` events. | Define canonical telemetry namespaces. |
| Error taxonomy | Match Python exceptions (e.g., `CodexError`, `TurnFailed`, `AuthError`). | Map Rust exit codes -> Elixir exceptions. |

## TDD Roadmap
### Milestone 0 – Discovery (1 sprint)
- Write characterization tests by observing Python SDK (fixtures capturing JSONL transcripts for each feature).
- Build comparison harness: run Python client in CI to emit golden event logs; store under `integration/fixtures/python/*.jsonl`.

### Milestone 1 – Core Parity (2 sprints)
- Implement finalized struct definitions (Threads, Turns, Items, Usage) with doctests verifying JSON serialization.
- Red/green for blocking turn flow using recorded transcripts; replicate auto-setting `thread_id`, `final_response`, token usage.
- Add streaming API returning Elixir `Stream` that matches Python async generator behavior; verify via property tests comparing event ordering.

### Milestone 2 – Tooling & Sandbox (2 sprints)
- Introduce tool registry behaviour with Mox-driven tests: register mock tool, ensure invocation lifecycle matches Python callback signature.
- Implement approval middleware: tests simulate command events requiring approval; ensure denial aborts turn with matching error.
- Add working directory and sandbox flag handling, reusing CLI flags; integration tests spawn a fake `codex-rs` executable.

### Milestone 3 – Attachments & Structured Output (1 sprint)
- Build file upload staging service (uses `~/.codex/artifacts` like Python). Tests cover cleanup, multiple attachments, and large file handling.
- Expand structured output tests to include schema failure cases mirrored from Python unit tests.

### Milestone 4 – Observability & Ergonomics (1 sprint)
- Emit `:telemetry` events for lifecycle milestones; use capture fixtures to assert parity with Python logging expectations.
- Finalize error modules; cross-check error messages and codes using golden logs from Python runs.
- Document API and migrate examples to ensure parity (docs + doctests).

### Milestone 5 – Regression Safety Net (ongoing)
- Add contract tests that run both Python and Elixir clients against mock codex-rs binary, diffing event streams.
- Integrate coverage gate via `mix coveralls` ≥ Python suite coverage baseline; ensure CI matrix spans macOS + Linux.

## Risks & Mitigations
- **Rust submodule divergence**: track upstream via dependabot-style reminders; lock commit hash and regenerate artifacts on upgrade.  
- **Cross-platform builds**: provide Docker-based build fallback; run CI on macOS/Linux to catch sandbox differences.  
- **Unknown Python features**: maintain parity checklist updated as we learn; write failing tests first referencing Python behavior.  
- **Binary size in Hex releases**: publish native binary separately (e.g., optional NIF package) to keep main Hex package lightweight.

## Immediate Next Actions
1. Add `openai/codex` as submodule with sparse checkout limited to `codex-rs/**`; script verification in `scripts/bootstrap_rust.sh`.  
2. Inventory Python SDK by cloning repo, exporting feature list & event transcripts (store under `integration/fixtures`).  
3. Update project docs (`docs/02-architecture.md`, `docs/04-testing-strategy.md`) with Python-specific nuances discovered during audit.  
4. Draft initial parity checklist issue to track milestones and assign owners.
