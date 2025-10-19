# Structured Output Design

## Feature Summary
- Support JSON schema-driven structured responses identical to Python's `structured_output` helpers.
- Manage temporary schema files, validation of returned payloads, and error reporting for mismatches.
- Provide ergonomic API for generating schema from Elixir structs and validating results.

## Subagent Perspectives
### Subagent Astra (API Strategist)
- Offer `Codex.StructuredOutput.enable/2` to attach schema to thread or turn options.
- Provide schema builders from `TypedStruct` or plain maps; integrate with existing `Codex` macros.
- Return parsed structs in `Codex.Turn.Result`, exposing both raw JSON and decoded struct.

### Subagent Borealis (Concurrency Specialist)
- Ensure schema files are written atomically with deterministic paths and cleaned after use.
- Handle concurrent turns with unique schema directories to avoid collisions.
- Manage fallback when codex-rs returns invalid JSON—surface error without crashing Exec process.

### Subagent Cypher (Test Architect)
- Create doctests for schema builders, verifying JSON output matches Python examples.
- Build integration tests using fixtures where codex-rs returns valid and invalid structured payloads.
- Add property tests verifying round-trip encode/decode for generated schemas.

## Implementation Tasks
- Implement schema serializer to disk (`Codex.StructuredOutput.SchemaWriter`) with cleanup hooks.
- Add decoder pipeline leveraging `Jason` and optional custom modules for domain structs.
- Extend `Codex.Turn.Result` with `structured_data` field and error metadata.

## TDD Entry Points
1. Start with failing doctest generating schema for simple struct.
2. Add integration test with recorded fixture verifying parsed payload matches expected struct.
3. Write red test for invalid payload producing descriptive error.

## Risks & Mitigations
- **Schema drift**: store generated schema snapshots and version them; contract test against Python.
- **File cleanup**: enforce `after` hook and telemetry warning when cleanup fails.
- **Decoding errors**: allow callers to supply custom decoder to handle version mismatches.

## Open Questions
- Determine whether Python client exposes schema caching; replicate if necessary.
- Decide on API ergonomics for nested schemas—builder DSL or direct map input?
