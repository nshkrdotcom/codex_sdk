# Codex SDK TDD Implementation Guide

## Mission & Success Criteria
- Deliver a 100% feature-parity Elixir SDK mirroring the Python client (`openai-agents-python`) while sharing the same `codex-rs` Rust engine.
- Ship an idiomatic, well-documented OTP interface that honors repository conventions, keeps the Rust engine isolated, and maintains deterministic, reproducible builds.
- Sustain a continuous test-driven development cadence: every user-facing capability enters the codebase behind a failing test and lands with green CI, ≥95 % coverage, and lint/format compliance.

## Guiding Principles
1. **Parity First**: All behavior—including edge-case semantics, telemetry, and error surfaces—must match Python unless an intentional deviation is documented.
2. **TDD Discipline**: The red → green → refactor loop is non-negotiable. Each milestone defines acceptance tests before implementation work begins.
3. **Deterministic Tooling**: Tests rely on reproducible fixtures (golden event logs, fake binaries) and never call upstream services implicitly.
4. **Isolated Dependencies**: `codex-rs` stays in a dedicated git submodule with explicit build/install tooling; Elixir code treats it as a black box.
5. **Continuous Documentation**: Every module, behavior, and mix task gains docs/doctests; plans and checklists evolve alongside the implementation.

## Dependency Management & Rust Engine Integration
1. **Git Submodule Setup**
   - Add `openai/codex` as a submodule rooted at `vendor/codex`.
   - Configure sparse checkout to include only `codex-rs/**`, `codex-rs/scripts/**`, and release manifests. Update `.gitmodules` accordingly.
   - Version pin lives in `config/native.exs` and is echoed in `mix.exs` metadata (`@codex_rs_commit`).
2. **Mix Native Wrapper**
   - Introduce `Mix.Tasks.Codex.Install` that bootstraps Rust toolchain checks, applies any `patches/codex-rs/*.patch`, and runs `cargo build --release`.
   - Built binaries land in `priv/codex/<platform>/codex`; path recorded in {@literal Codex.Options.default_codex_path/0}.
   - Cache build artifacts in `_build/native/<platform>` to keep CI fast.
3. **Prebuilt Artifact Fallback**
   - Optional opt-in flag `mix codex.install --prebuilt` downloads signed archives from upstream release buckets.
   - Validate checksums, store in same `priv/codex/<platform>` hierarchy, and respect offline installations by default (no network call unless flag provided).
4. **Isolation Guarantees**
   - Never modify submodule sources directly; maintain `patches/` and reapply during `mix codex.install`.
   - Add CI job that runs `git diff vendor/codex` to ensure no uncommitted changes leak in.

## Iterative TDD Roadmap
### Milestone 0 – Discovery & Characterization (1 sprint)
- Clone Python SDK and enumerate public APIs; capture JSONL transcripts for baseline scenarios (threads, tools, approvals, structured output, attachments, telemetry).
- Build Python ↔ Elixir comparison harness producing golden fixtures under `integration/fixtures/python/*.jsonl`.
- Write failing contract tests that consume the fixtures, asserting parity at the event-stream level (known failures tolerated via `@tag :pending` until corresponding milestone).

### Milestone 1 – Core Thread & Turn Flow (2 sprints)
- Author ExUnit scenarios for thread lifecycle (`Codex.start_thread/2`, `Codex.resume_thread/3`) matching Python behaviors.
- Define event struct doctests covering JSON serialization/deserialization from fixtures.
- Implement minimal code to pass blocking turn tests, then expand to streaming by validating stream ordering and final response extraction.

### Milestone 2 – Tooling & Auto-Run (2 sprints)
- Write red tests for tool registration, invocation lifecycle, and auto-run loops based on Python decorators.
- Build Mox-backed tool registry ensuring concurrency safety and verifying approved command execution semantics.
- Implement sandbox/approval middleware with tests covering accept/deny/bypass cases.

### Milestone 3 – Attachments & File APIs (1 sprint)
- Construct integration tests that simulate file staging, upload, and cleanup using a fake `codex-rs` binary.
- Provide unit tests for `Codex.Files` helpers (content hashing, local caching).

### Milestone 4 – Observability & Error Domains (1 sprint)
- Add failing tests for telemetry emission (`:telemetry` events, logging hooks) matching Python callbacks.
- Enumerate error classes (user errors, transport failures, timeouts) and encode them with property tests verifying message parity.

### Milestone 5 – Regression Harness & Coverage Gate (ongoing)
- Stand up contract suite that spins both Python and Elixir clients against a mock `codex-rs` responder, diffing event streams during CI.
- Enforce coverage gate via `mix coveralls` ≥ baseline; integrate `mix credo --strict` and `mix dialyzer` (with cached PLTs) into CI matrix (macOS + Linux).

## Module Implementation Playbook
### Options & Configuration (`Codex.Options`, `Codex.Thread.Options`)
- Start with doctests capturing default propagation and environment overrides (`CODEX_API_KEY`, `CODEX_URL`).
- Use property tests to confirm that option merging is associative and idempotent.

### Event Domain (`Codex.Events.*`)
- Generate struct modules per event type; tests enforce required keys and maintain exhaustive pattern matching.
- Provide `Codex.Events.parse!/1` with table-driven tests sourced from fixtures.

### Exec Layer (`Codex.Exec`)
- Begin with failing Supertester scenarios verifying process supervision, stderr propagation, and crash resilience.
- Mock port interactions using `Port` stubs; integration tests validate real Port behavior against fake binary.

### Thread & Turn APIs (`Codex.Thread`, `Codex.Turn`)
- Tests define blocking and streaming semantics, auto-run loop, structured output handling, and tool-call bridging.
- Leverage property tests to ensure streaming enumerables remain cold (no side effects until consumption) and respect cancellation.

### Tools & MCP (`Codex.Tools`, `Codex.MCP`)
- Introduce behaviors and default implementations with tests covering registration, metadata exposure, and invocation context.
- Integration tests spawn supervised fake MCP servers to validate handshake and lifecycle management.

### Files & Attachments (`Codex.Files`)
- Unit tests cover staging, deduplication, MIME detection; integration tests ensure cleanup on success/failure.

### Observability (`Codex.Telemetry`, logging)
- Tests assert emission of telemetry events with expected metadata; include golden snapshots for log formatting.

## Test Infrastructure & Tooling
- **Unit Tests**: `async: true`, leverage Mox for external interactions; enforce fast runtime (<1 ms).
- **Integration Tests**: Tagged `:integration`, using Supertester to orchestrate deterministic Port interactions; rely on fixtures.
- **Contract Tests**: Compare Python vs Elixir outputs using golden logs; executed nightly or on-demand due to runtime.
- **Property Tests**: Use StreamData for invariants (event encode/decode, options merging, stream ordering).
- **Live Tests**: Optional `:live` suite hitting real API; requires manual opt-in via env var.
- **Test Utilities**: Maintain `test/support/` helpers for fixture loading, fake codex binary creation, and telemetry capture.
- **Coverage & Linting**: Gate merges on `mix coveralls`, `mix credo --strict`, and `mix dialyzer` (post-PLT warmup).

## Fixture & Golden Data Strategy
- Store Python-generated event transcripts in `integration/fixtures/python`.
- Maintain schema snapshots for structured outputs in `integration/fixtures/schemas`.
- Keep fake codex scripts under `test/support/fakes` with helper for on-the-fly generation.
- Version fixtures with semantic names (`thread_auto_run_success.jsonl`) and document updates in `docs/fixtures.md`.

## CI/CD & Automation
- Expand GitHub Actions to run:
  1. `mix deps.get && mix compile --warnings-as-errors`
  2. `mix format --check-formatted`
  3. `mix test --include integration`
  4. `mix coveralls.github`
  5. `MIX_ENV=dev mix dialyzer`
  6. Nightly job: contract parity suite + Python harness
- Add job ensuring `mix codex.install --check` verifies binary integrity and submodule cleanliness.
- Publish artifacts (coverage reports, parity diff logs) as CI attachments to inform regressions.

## Documentation & Communication
- Update `docs/02-architecture.md`, `docs/03-implementation-plan.md`, and `docs/04-testing-strategy.md` after each milestone with distilled learnings.
- Maintain running parity checklist in `docs/python-parity-checklist.md` (new file) capturing feature status, associated tests, and owners.
- Ensure every public module ships `@doc` and doctests; include usage examples mirroring Python README scenarios.
- Prepare release notes summarizing parity gaps closed per sprint; attach telemetry or fixture updates as needed.

## Risk Register & Mitigations
- **Rust Submodule Drift**: Automate weekly reminder to sync commit hash; require explicit changelog entry for upgrades.
- **Fixture Rot**: Regenerate Python transcripts via automation script and diff results; tests fail if fixtures change unexpectedly.
- **Cross-Platform Variance**: Execute integration suite on macOS and Linux; provide container image to equalize developer environments.
- **Binary Size Constraints**: Consider optional Hex package `codex_sdk_native` for binaries; document install steps.
- **TDD Discipline Slippage**: Enforce code review checklist requiring failing test link before feature implementation.

## Immediate Next Actions
1. Introduce `vendor/codex` submodule with sparse checkout and create `Mix.Tasks.Codex.Install`.
2. Build Python harness (`scripts/harvest_python_fixtures.py`) to capture golden data for Milestone 0.
3. Author baseline failing contract tests asserting parity for thread lifecycle and event parsing.
4. Schedule architecture review to validate roadmap, resourcing, and milestone timelines.
