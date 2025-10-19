# Codex SDK Remaining Milestone Roadmap

## Overview
This document captures the outstanding work required to deliver full feature parity with the Python Codex SDK. Milestones are derived from `docs/08-tdd-implementation-guide.md` and updated to reflect current repository status (Milestone 0 complete, Milestone 1 partially implemented).

| Milestone | Goal | Status | Target Duration |
|-----------|------|--------|-----------------|
| M0 – Discovery & Characterization | Harvest Python fixtures, stand up contract tests | ✅ Complete | 1 sprint |
| M1 – Core Thread & Turn Flow | Finalize thread/turn domain, event structs, streaming | ⏳ In progress | 2 sprints |
| M2 – Tooling & Auto-Run | Tool registry, auto-run orchestration, sandbox hooks | ⏳ Not started | 2 sprints |
| M3 – Attachments & Files | File staging, uploads, cleanup | ⏳ Not started | 1 sprint |
| M4 – Observability & Errors | Telemetry, logging, error taxonomy | ⏳ Not started | 1 sprint |
| M5 – Regression Harness | Dual-client contract suite, coverage gate, CI hardening | ⏳ Not started | Ongoing |

## Milestone 1 – Core Thread & Turn Flow (Remaining Scope)
- **Event Domain**
  - Generate typed event structs (`Codex.Events.*`) for all protocol items.
  - Implement JSON encode/decode parity tests using harvested fixtures.
- **Turn Pipeline**
  - Support auto-run orchestration loop with retry policies.
  - Persist usage metrics & continuation tokens on thread struct.
- **Streaming Enhancements**
  - Provide backpressure-aware streaming enumerable with cancellation handling.
  - Add property tests ensuring lazy evaluation and deterministic teardown.
- **Acceptance Criteria**
  - Blocking and streaming runs match Python fixtures for single/multi-turn threads.
  - Integration tests prove turn resumption using recorded continuation tokens.

## Milestone 2 – Tooling & Auto-Run
- **Tool Registry**
  - Implement `Codex.Tools.register/2`, deregistration, and metadata persistence.
  - Provide macro DSL aligning with Python decorators.
- **MCP Integration**
  - Build `Codex.MCP.Client` with handshake, capability discovery, tool invocation.
  - Supervise external MCP servers with deterministic lifecycle tests.
- **Auto-Run Loop**
  - Mirror Python auto-run; handle tool call responses, approvals, retries.
  - Document hook interfaces for event callbacks.
- **Acceptance Criteria**
  - Contract tests compare tool invocation streams against Python logs.
  - All tool-enabled threads run using `async: true` tests with Supertester helpers.

## Milestone 3 – Attachments & File APIs
- **Local Staging**
  - Implement staging directory manager with checksum-based deduplication.
  - Support ephemeral and persistent attachments; clean up after runs.
- **Upload Pipeline**
  - Chunked upload flow via codex-rs; fallback to existing Python semantics.
  - Provide `Codex.Files.upload/2` and `Codex.Files.attach/3`.
- **Acceptance Criteria**
  - Integration tests replay Python attachment fixtures.
  - Telemetry emits file lifecycle events for observability milestone.

## Milestone 4 – Observability & Error Domains
- **Telemetry**
  - Emit `:telemetry` spans for thread lifecycle, turn events, tool calls.
  - Ship default logger wiring for structured logs matching Python output.
- **Error Taxonomy**
  - Implement `Codex.Error` hierarchy with parity to Python exceptions.
  - Capture diagnostics (stderr, exit codes) without leaking secrets.
- **Acceptance Criteria**
  - Golden log fixtures diff cleanly between Python and Elixir.
  - Property tests validate error message formatting and codes.

## Milestone 5 – Regression Harness & Coverage
- **Dual-Client Harness**
  - Script to run Python and Elixir clients against mock codex-rs; diff events.
  - Automate via Mix task & nightly CI job.
- **Coverage & Lint Gates**
  - Enforce `mix coveralls` baseline constant with parity coverage.
  - Integrate `mix credo --strict`, `mix dialyzer`, cross-platform matrix.
- **Release Readiness**
  - Document release checklist (binary verification, version pins).
  - Update parity checklist for each milestone completion.

## Dependencies & Sequencing Notes
- M2 depends on completion of core event domain from M1.
- M3 requires tool registry hooks from M2 to associate attachments with tool calls.
- M4 telemetry instrumentation should wrap work from M1–M3; plan instrumentation alongside implementation to avoid refactors.
- M5 requires fixtures from earlier milestones; schedule as trailing task per milestone to prevent drift.
