# Attachments & File Management Design

## Feature Summary
- Enable staging, uploading, and referencing files/attachments within turns in parity with Python SDK.
- Manage local caching, deduplication, and cleanup of temporary assets to prevent leakage.
- Support large file workflows, chunked uploads, and metadata propagation to codex-rs.

## Subagent Perspectives
### Subagent Astra (API Strategist)
- Provide APIs: `Codex.Files.stage/2`, `Codex.Files.upload/2`, `Codex.Files.attach/3` returning attachment tokens.
- Ensure Elixir structs mirror Python file descriptors (`id`, `name`, `size`, `content_type`, `checksum`).
- Add convenience wrappers for streaming binary data vs. file paths.

### Subagent Borealis (Concurrency Specialist)
- Handle upload operations in supervised tasks with timeout controls; prevent blocking caller processes.
- Implement chunked uploads using codex-rs capabilities; add retries with exponential backoff.
- Guarantee cleanup via `after` hooks and telemetry if staging fails mid-operation.

### Subagent Cypher (Test Architect)
- Create unit tests for checksum generation, dedup detection, and MIME inference.
- Integration tests using fake codex binary to validate upload command sequence and metadata propagation.
- Contract tests comparing Python and Elixir attachment metadata from golden fixtures.

## Implementation Tasks
- Build staging directory under `_build/codex_files` with configurable location.
- Implement dedup index using ETS or persistent term keyed by checksum.
- Provide `Codex.Files.temporary/1` helper returning RAII-style struct with cleanup on drop.

### Current Status
- `Codex.Files.stage/2` stages attachments into a checksum-keyed directory, records TTL metadata, and deduplicates repeated content while refreshing expiry windows.
- `Codex.Files.attach/2` propagates staged files onto thread options; `Codex.Exec` forwards attachments to the binary via CLI flags.
- `Codex.Files.Registry` runs a periodic cleanup loop honoring TTLs, exposes `force_cleanup/0` for manual sweeps, publishes telemetry, and reports disk usage via `Codex.Files.metrics/0`.

## TDD Entry Points
1. Write failing unit test verifying duplicate file returns cached descriptor.
2. Add integration test for staged attachment participating in turn execution.
3. Implement test ensuring cleanup runs even when turn crashes.

## Risks & Mitigations
- **Disk bloat**: enforce TTL cleanup job; add telemetry metric for staged file count.
- **Large file streaming**: rely on chunked upload pipeline and backpressure.
- **Checksum mismatch**: validate before upload; halt with actionable error.

## Open Questions
- Confirm Python client's support for remote URLs vs local files—need parity decision.
- Determine whether attachments require encryption at rest for compliance.
