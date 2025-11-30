# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.1] - 2025-11-29

### Added
- App-server event coverage for token usage deltas, turn diffs, and compaction notices, plus explicit thread/turn IDs on item and error notifications
- Streaming example updates to surface live usage and diff events alongside item progress
- Automatic auth fallback to Codex CLI login when API keys are absent; live two-turn walkthrough example
- Regression tests and fixtures for `/new` resets, early-exit session non-persistence, and rate-limit/sandbox error normalization
- Live usage/compaction streaming example aligned with new model defaults and reasoning effort handling
- Live exec controls example (env injection, cancellation tokens, timeout tuning) plus README/docs updates covering safe-command approval bypass
- Sandbox warning normalization updates (Windows read-only `.git` detection, world-writable dedup) and runnable example `sandbox_warnings_and_approval_bypass.exs`
- README/docs refresh covering policy-approved bypass flags and normalized sandbox warning strings
- Added `examples/live_tooling_stream.exs` to showcase streamed MCP/shell events and fallback handling when `turn.completed` omits a final response
- Live telemetry stream example (thread/turn IDs, source metadata, usage deltas, diffs, compaction savings) with README/docs references
- Live telemetry stream defaults tuned for fast runs (minimal reasoning, short prompt)

### Changed
- Thread resumption now uses `codex exec … resume <thread_id>` (no `--thread-id` flag)
- `/new` clears conversations and early-exit turns do not persist thread IDs, matching upstream CLI
- Turn failures normalize rate-limit and sandbox assessment errors into `%Codex.Error{}`
- Telemetry now propagates source info, thread/turn IDs, OTLP mTLS options, and richer token/diff/compaction signals through emitters and OTEL spans

## [0.2.0] - 2025-10-20

### Added
- Core Codex thread lifecycle with streaming, resumption, and structured output decoding (`Codex.Thread`, `Codex.Turn.Result`, `Codex.Events`, `Codex.Items`)
- GenServer-backed `Codex.Exec` process supervision, error handling, and tool invocation pipeline
- Approval policies, hook behaviour, registry support, and telemetry events for tooling approvals
- File staging registry, attachment helpers, parity fixtures, and harvesting script for Python SDK alignment
- Comprehensive telemetry module with OTLP exporter gating, metrics, and approval instrumentation
- Mix tasks (`mix codex.verify`, `mix codex.parity`), integration tests, and Supertester-powered contract suite
- Rich examples and documentation covering approvals, streaming, concurrency, observability, and design dossiers

### Changed
- Refreshed `README.md` with 0.2.0 usage guide, testing workflow, and observability configuration
- Expanded HexDocs configuration to include new guides, design notes, and release documentation
- Updated package metadata to ship changelog, examples, and assets with the Hex release

## [0.1.0] - 2025-10-11

Initial design release.
