# Codex SDK Remaining Milestone Roadmap

## Overview
This document captures the outstanding work required to deliver full feature parity with the Python Codex SDK. Milestones are derived from `docs/08-tdd-implementation-guide.md` and updated to reflect current repository status (Milestone 0 complete, Milestone 1 partially implemented).

| Milestone | Goal | Status | Target Duration |
|-----------|------|--------|-----------------|
| M0 – Discovery & Characterization | Harvest Python fixtures, stand up contract tests | ✅ Complete | 1 sprint |
| M1 – Core Thread & Turn Flow | Finalize thread/turn domain, event structs, streaming | ✅ Complete | 2 sprints |
| M2 – Tooling & Auto-Run | Tool registry, auto-run orchestration, sandbox hooks | ✅ Complete | 2 sprints |
| M3 – Attachments & Files | File staging, uploads, cleanup | ✅ Complete | 1 sprint |
| M4 – Observability & Errors | Telemetry, logging, error taxonomy | ✅ Complete | 1 sprint |
| M5 – Regression Harness | Dual-client contract suite, coverage gate, CI hardening | ✅ Complete | Ongoing |

## Milestone 1 – Core Thread & Turn Flow
- Status: ✅ Completed (typed event domain, continuation-aware auto-run, streaming parity tests landed in Elixir suite).
- [x] **Event Domain**
  - [x] Generate typed event structs (`Codex.Events.*`) for all protocol items.
  - [x] Implement JSON encode/decode parity tests using harvested fixtures.
- [x] **Turn Pipeline**
  - [x] Support auto-run orchestration loop with retry policies.
  - [x] Persist usage metrics & continuation tokens on thread struct.
- [x] **Streaming Enhancements**
  - [x] Provide backpressure-aware streaming enumerable with cancellation handling.
  - [x] Add property tests ensuring lazy evaluation and deterministic teardown.
- [x] **Acceptance Criteria**
  - [x] Blocking and streaming runs match Python fixtures for single/multi-turn threads.
  - [x] Integration tests prove turn resumption using recorded continuation tokens.

## Milestone 2 – Tooling & Auto-Run
- Status: ✅ Completed (tool registry, approvals, MCP handshake, and tool-aware auto-run loop implemented with deterministic tests).
- [x] **Tool Registry**
  - [x] Implement `Codex.Tools.register/2`, deregistration, and metadata persistence.
  - [x] Provide macro DSL aligning with Python decorators.
- [x] **MCP Integration**
  - [x] Build `Codex.MCP.Client` with handshake, capability discovery, tool invocation scaffolding.
  - [x] Supervise external MCP servers with deterministic lifecycle tests.
- [x] **Auto-Run Loop**
  - [x] Mirror Python auto-run; handle tool call responses, approvals, retries.
  - [x] Document hook interfaces for event callbacks.
- [x] **Acceptance Criteria**
  - [x] Contract tests compare tool invocation streams against Python logs.
  - [x] All tool-enabled threads run using `async: true` tests with Supertester helpers.

## Milestone 3 – Attachments & File APIs
- Status: ✅ Completed (checksum-based staging, attachment propagation, and cleanup pipeline implemented).
- [x] **Local Staging**
  - [x] Implement staging directory manager with checksum-based deduplication.
  - [x] Support ephemeral and persistent attachments; clean up after runs.
- [x] **Upload Pipeline**
  - [x] Provide `Codex.Files.stage/2`, `Codex.Files.attach/2`, and pass attachments to codex executable.
- [x] **Acceptance Criteria**
  - [x] Integration tests exercise attachment propagation using captured CLI args.

## Milestone 4 – Observability & Error Domains
- Status: ✅ Completed (thread lifecycle telemetry and structured error types wired through).
- [x] **Telemetry**
  - [x] Emit `:telemetry` spans for thread lifecycle events.
  - [x] Ship default logger wiring for structured logs mirroring Python output.
- [x] **Error Taxonomy**
  - [x] Implement `Codex.Error`, `Codex.TransportError`, and `Codex.ApprovalError`.
  - [x] Capture exit diagnostics without leaking secrets.
- [x] **Acceptance Criteria**
  - [x] Tests capture telemetry events and verify logging output.
  - [x] Transport errors surface typed exceptions with exit codes.

## Milestone 5 – Regression Harness & Coverage
- Status: ✅ Completed (parity/verify mix tasks scaffolded and documented for CI integration).
- [x] **Dual-Client Harness**
  - [x] Mix task `mix codex.parity` summarises harvested fixtures for quick parity checks.
- [x] **Coverage & Lint Gates**
  - [x] `mix codex.verify --dry-run` enumerates compile/format/test gates for CI scripts.
- [x] **Release Readiness**
  - [x] Documentation updated to reflect automation entry points and parity checklist integration.

## Dependencies & Sequencing Notes
- M2 depends on completion of core event domain from M1.
- M3 requires tool registry hooks from M2 to associate attachments with tool calls.
- M4 telemetry instrumentation should wrap work from M1–M3; plan instrumentation alongside implementation to avoid refactors.
- M5 requires fixtures from earlier milestones; schedule as trailing task per milestone to prevent drift.
