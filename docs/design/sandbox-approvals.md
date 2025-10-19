# Sandbox & Approval Workflow Design

## Feature Summary
- Mirror Python client's sandbox modes and approval callbacks for command execution, tool usage, and file access.
- Provide flexible policy engine allowing synchronous approval, async queueing, and default deny/allow behaviors.
- Surface audit logs and telemetry for governance visibility.

## Subagent Perspectives
### Subagent Astra (API Strategist)
- Introduce `Codex.Approvals.Hook` behaviour with callbacks: `prepare/2`, `review_tool/3`, `review_command/3`, `review_file/3`, plus optional `await/2`.
- Expose helper `Codex.Approvals.StaticPolicy` for simple allow/deny modes and `Codex.Approvals.Queue` for manual moderation.
- Allow thread-level overrides via `Codex.Thread.Options`.

### Subagent Borealis (Concurrency Specialist)
- Embed approval workflow in turn execution pipeline, pausing event processing until decision arrives.
- Use `GenServer.call` with timeout to avoid deadlocks; support async decisions via `Task` with reply.
- Ensure sandbox enforcement integrates with codex-rs flags (filesystem isolation, network policy) via command args.

### Subagent Cypher (Test Architect)
- Write integration tests simulating command execution events requiring approval; verify acceptance continues run, denial halts with error.
- Add property tests for policy combinators (priorities, fallbacks).
- Create contract tests using Python logs to confirm identical approval sequencing and error messages.

## Implementation Tasks
- Build policy registry accessible per thread; default to allow but log warnings if no policy configured.
- Map sandbox options to codex-rs CLI flags and ensure they are idempotent.
- Emit telemetry events (`[:codex, :approval, ...]`) for monitoring dashboards.

### Current Status
- `Codex.Approvals.StaticPolicy` ships with `allow/0` and `deny/1` helpers used by tests and the default auto-run pipeline.
- Tool invocations now consult the configured policy and halt auto-run with a tagged error when denied.

## TDD Entry Points
1. Red test where approval module denies command and turn returns specific error tuple.
2. Add test verifying sandbox flag translation from thread options to codex-rs command line.
3. Implement asynchronous approval queue test ensuring decisions resume execution.

## Risks & Mitigations
- **Deadlocks**: enforce timeouts and fallback policies; document defaults.
- **Policy misconfiguration**: provide compile-time warnings when policies missing required callbacks.
- **Telemetry gaps**: add integration tests ensuring audit events emitted consistently.

## Open Questions
- Do we need multi-step approvals (e.g., staged vs execute)? Confirm with product requirements.
- Should approvals integrate with external message bus? Evaluate after MVP.
