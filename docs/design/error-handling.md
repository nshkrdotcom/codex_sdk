# Error Handling & Diagnostics Design

## Feature Summary
- Provide consistent error taxonomy mirroring Python client's exception hierarchy while staying idiomatic in Elixir.
- Capture detailed diagnostics (stderr, exit codes, offending events) without leaking sensitive data.
- Support retriable errors, approval denials, and user-facing validation failures with clear messaging.

## Subagent Perspectives
### Subagent Astra (API Strategist)
- Define error structs: `Codex.Error`, `Codex.TransportError`, `Codex.ValidationError`, `Codex.ApprovalError`, etc.
- Implement `Exception.message/1` to align with Python error strings for parity.
- Offer helper `Codex.Error.normalize/1` converting raw tuples or exceptions into structured errors.

### Subagent Borealis (Concurrency Specialist)
- Ensure Exec layer traps exits and converts port crashes into structured errors with context (exit status, stderr tail).
- Provide retry metadata when errors are transient; auto-run loop consumes this to decide retries.
- Maintain error stack data in process dictionary or explicit metadata for debugging.

### Subagent Cypher (Test Architect)
- Build unit tests for error constructors and message parity (compare with Python exception strings).
- Integration tests simulating codex-rs failures (non-zero exit, malformed JSON) verifying diagnostic payload.
- Contract tests ensuring parity for approval denials, sandbox violations, and validation failures.

## Implementation Tasks
- Create error modules with `defexception` and supportive helper functions.
- Instrument Exec GenServer to capture stderr buffer and include truncated output in errors.
- Update turn pipeline to return `{:error, Codex.Error.t()}` consistently; document tuple shapes.

### Current Status
- Transport exits now surface `%Codex.TransportError{}` with exit status metadata.
- Approval denials return `%Codex.ApprovalError{}` consumed by the auto-run loop.
- Base `Codex.Error` struct provides structured error shape for future expansion.

## TDD Entry Points
1. Start with failing test expecting `Codex.TransportError` when fake binary exits non-zero.
2. Add test for structured validation failure returning Python-equivalent message.
3. Implement test for approval denial returning `{:error, %Codex.ApprovalError{}}`.

## Risks & Mitigations
- **Information leakage**: scrub API keys and sensitive file paths before exposing diagnostics.
- **Error explosion**: maintain manageable taxonomy; document mapping table.
- **Retry loops**: ensure auto-run respects max retries; add tests for runaway scenarios.

## Open Questions
- Need to confirm Python error hierarchy exact names; derive from audit.
- Decide whether to expose detailed diagnostics in production or gate behind debug flag.
