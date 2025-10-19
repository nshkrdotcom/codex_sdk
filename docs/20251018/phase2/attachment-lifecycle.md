# Attachment Lifecycle Manager – Design (2025-10-17)

## Overview
Implement automatic pruning and metadata auditing for staged attachments created by `Codex.Files`. Today staged files persist indefinitely; we need TTL-based cleanup, disk usage tracking, and observability hooks.

## Goals
- Introduce configurable TTL (default 24h) for non-persistent attachments.
- Provide background job (GenServer) to prune expired entries.
- Surface staging stats (count, total bytes) via `Codex.Files.metrics/0`.
- Telemetry events for staging/cleanup.

## Non-Goals
- Persist staged file index across reboot (rebuild on demand).
- Remote storage (S3, etc.) — future work.

## Architecture
1. `Codex.Files.Registry` GenServer maintaining ETS manifest (currently map).
2. On `stage/2`, record `inserted_at`, mark `persist?`.
3. Periodic timer every N minutes scans for expired entries (TTL configurable via app env `:codex_sdk, :attachment_ttl_ms`).
4. On cleanup: delete file path, remove ETS row, emit telemetry.
5. `Codex.Files.metrics/0` aggregates counts/bytes.

## API Changes
- `Codex.Files.stage/2` accepts `ttl_ms: :infinity | pos_integer`.
- New `Codex.Files.metrics/0`, `Codex.Files.force_cleanup/0`.
- Application config knob: `:codex_sdk, attachment_cleanup_interval_ms`.

## Risks
- Cleanup job must handle missing files gracefully (external deletion).
- Concurrent staging/cleanup race — use ETS update counters with `:write_concurrency`.

## Implementation Plan
1. Refactor `Codex.Files` registry into GenServer started under application supervision tree.
2. Update `stage/2` to call into server (`GenServer.call`) returning attachment struct.
3. Implement cleanup timer (handle_info).
4. Telemetry events `[:codex, :attachment, :staged]`, `:cleaned`.
5. Update tests to use new API and metrics.

## Implementation Notes (2025-10-17)
- Introduced `Codex.Files.Registry` GenServer that owns the ETS table `:codex_files_manifest`, schedules periodic sweeps using `:attachment_cleanup_interval_ms`, and exposes synchronous calls for staging, metrics, cleanup, and reset.
- `Codex.Files.stage/2` now records `inserted_at` timestamps (UTC, millisecond precision) and persisted TTL metadata on every staging call. Staging the same checksum refreshes `inserted_at`, upgrades `persist?`, and stretches TTL windows rather than shortening them.
- New `Codex.Files.force_cleanup/0` prunes only expired, non-persistent attachments. A legacy `cleanup!/0` alias forwards to the new API to preserve backwards compatibility.
- `Codex.Files.metrics/0` aggregates totals into `%{total_count, total_bytes, persistent_count, persistent_bytes, expirable_count, expirable_bytes}` for downstream dashboards.

## Telemetry Reference
- `[:codex, :attachment, :staged]`
  - Measurements: `%{size_bytes: non_neg_integer()}`
  - Metadata: `%{checksum: String.t(), name: String.t(), persist?: boolean(), ttl_ms: attachment_ttl(), cached?: boolean()}`
- `[:codex, :attachment, :cleaned]`
  - Measurements: `%{count: non_neg_integer(), bytes: non_neg_integer()}`
  - Metadata: `%{checksum: String.t(), name: String.t(), ttl_ms: attachment_ttl()}`

`attachment_ttl()` resolves to a non-negative integer (ms) or `:infinity`. Manual cleanups emit one `:cleaned` event per attachment removed; periodic sweeps reuse the same contract.

## Verification
- Unit tests for TTL logic (immediate expiration, infinity).
- Integration test staging -> cleanup triggered via forced call.
- Telemetry capture ensures metadata correctness.
- Property: staging same file multiple times updates metrics idempotently.

## Open Questions
- Should TTL apply to persistent attachments? Default no (only ephemeral).
- Should cleanup run at application start (synchronous sweep)? consider optional flag.
