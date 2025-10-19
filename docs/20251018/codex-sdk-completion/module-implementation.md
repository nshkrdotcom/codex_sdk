# Remaining Module Implementation Details

This document enumerates the outstanding module work required to achieve full parity. Each section links to design references (see `docs/design/*.md`) and maps to milestone deliverables.

## Core Event Domain (`Codex.Events`)
- **Tasks**
  - Generate dedicated struct modules for every event type emitted by codex-rs (thread, turn, item deltas, sandbox decisions, tool calls, attachments, telemetry).
  - Implement {@literal Codex.Events.parse!/1} and {@literal Codex.Events.serialize/1} with exhaustive pattern matching.
  - Ensure enumerated atom types (`:thread_started`, `:turn_completed`, etc.) remain in sync with Python enums.
- **Tests**
  - Table-driven fixtures using `integration/fixtures/python/*.jsonl`.
  - Property tests verifying `serialize(parse(json)) == json`.
- **Dependencies**
  - Requires fixture coverage from Milestones 0–2.

## Turn Pipeline (`Codex.Turn`, `Codex.Turn.Result`)
- **Outstanding Features**
  - Auto-run orchestration (loop until terminal event or retry limit).
  - Structured output validation integration (pending structured output feature).
  - Usage aggregation including cached tokens, tool tokens, latency metrics.
- **Testing**
  - Contract tests for auto-run sequences (tool retries, approvals).
  - Supertester-based property tests for stream cancellation and cold enumerables.

## Tooling Layer (`Codex.Tools`, `Codex.Tool`, `Codex.MCP`)
- **Implementation Checklist**
  - Define behaviour `Codex.Tool` with callbacks for invoke, metadata, schema.
  - Provide registry with ETS-backed lookup and unique registration handles.
  - Implement MCP client handshake, command dispatch, and error handling.
  - Expose Mix task to validate tool manifests.
- **Testing**
  - Unit tests using Mox to simulate tool modules.
  - Integration tests with fake MCP server scripts (spawned via Supertester).
  - Contract tests comparing Python auto-run transcripts.

## Sandbox & Approvals (`Codex.Approvals`, `Codex.Approvals.*`)
- **Implementation**
  - Build approval behaviours with synchronous and asynchronous policies.
  - Integrate with Exec pipeline to pause turn processing awaiting decisions.
  - Map thread options to codex-rs sandbox flags (filesystem/network).
- **Testing**
  - Integration tests covering accept/deny/timeout flows.
  - Property tests verifying policy combinators.

## Attachments & File APIs (`Codex.Files`, `Codex.Files.Attachment`)
- **Features**
  - Staging with checksum dedup, TTL cleanup, concurrency-safe writes.
  - Upload orchestration leveraging codex-rs commands; fallback to prebuilt binary downloads.
  - Temporary attachment helper supporting RAII-style cleanup.
- **Testing**
  - Unit tests for hashing, MIME inference, dedup map.
  - Integration tests with fake codex script verifying upload commands.
  - Contract tests aligning with Python attachment events.

## Structured Output (`Codex.StructuredOutput`)
- **Tasks**
  - Schema builder DSL, serialization to disk, cleanup.
  - Decoder pipeline converting JSON to typed structs.
  - Error reporting for schema violations with parity to Python.
- **Testing**
  - Doctests for schema builders.
  - Integration tests with fixtures containing valid/invalid payloads.

## Observability (`Codex.Telemetry`, logging integration)
- **Implementation**
  - Emit telemetry for thread lifecycle, turn start/stop, tool invocation, attachments, approvals.
  - Provide logger utilities to mirror Python log format; support JSON output mode.
  - Integrate correlation IDs across processes.
- **Testing**
  - Capture telemetry events via `:telemetry.attach_many`.
  - Golden log snapshots compared to Python outputs.

## Error Handling (`Codex.Error`, `Codex.TransportError`, etc.)
- **Outstanding Work**
  - Define exception structs with messages matching Python errors.
  - Normalize Exec failures (port exit, malformed JSON, timeouts, approvals).
  - Expose retry metadata for auto-run decisions.
- **Testing**
  - Unit tests for error constructors & messages.
  - Integration tests inducing failures with fake binaries.
  - Contract tests for parity with Python error fixtures.

## Mix Tasks & CLI Integration
- **Tasks**
  - Implement `mix codex.install` (build/download codex-rs).
  - Add `mix codex.verify` (ensure binary integrity, fixtures up to date).
  - Provide `mix codex.parity` to run regression harness comparisons.
- **Testing**
  - Mix task unit tests using temporary directories.
  - CI pipeline verifying tasks run successfully on Linux/macOS.
