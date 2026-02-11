# Erlexec Consolidation R2 Review (codex_sdk)

## Findings

### 1) Missing concurrent-subscriber stress coverage
- **Severity**: HIGH
- **Area**: Concurrency
- **Description**: Transport tests do not cover multiple concurrent subscribers under burst output, so loss/duplication and fanout correctness under load remain unproven.
- **Location**: `test/codex/io/transport/erlexec_test.exs:1`
- **Recommendation**: Add a test with multiple subscribers and high line volume; assert each subscriber receives all lines exactly once and no deadlock occurs.

### 2) Exec cleanup path lacks monitored shutdown escalation
- **Severity**: HIGH
- **Area**: Shutdown
- **Description**: `Codex.Exec.safe_stop/1` only invokes `IOTransport.force_close/1` and ignores outcome. If transport is wedged (e.g., `force_close` timeout), there is no monitor/await/`Process.exit` escalation path, unlike amp stream cleanup.
- **Location**: `lib/codex/exec.ex:267`
- **Recommendation**: Implement a cleanup cascade (`force_close` -> await DOWN -> `Process.exit(:shutdown)` -> await -> `Process.exit(:kill)` -> demonitor) and flush pending transport-tagged mailbox events.

### 3) Missing finalize-drain responsiveness test
- **Severity**: MEDIUM
- **Area**: Concurrency
- **Description**: No test validates that `GenServer.call` remains responsive while large `pending_lines` are drained during `:finalize_exit`.
- **Location**: `test/codex/io/transport/erlexec_test.exs:1`
- **Recommendation**: Port amp’s large-queue finalize test and assert short-timeout status calls succeed during drain.

### 4) No SIGTERM-ignoring subprocess cleanup regression test
- **Severity**: MEDIUM
- **Area**: Shutdown
- **Description**: There is no stubborn child-process test (TERM/INT ignored) validating cleanup semantics in consumers (`Codex.Exec`, app-server, MCP stdio) against transport timeout edge cases.
- **Location**: `lib/codex/exec.ex:267`
- **Recommendation**: Add cleanup tests using stubborn fixtures and assert subprocess/transport teardown within bounded time.

## Summary Table

| # | Severity | Area | Description | Location |
|---|----------|------|-------------|----------|
| 1 | HIGH | Concurrency | No concurrent-subscriber burst stress coverage | `test/codex/io/transport/erlexec_test.exs:1` |
| 2 | HIGH | Shutdown | `Exec.safe_stop/1` lacks monitored escalation when force-close times out | `lib/codex/exec.ex:267` |
| 3 | MEDIUM | Concurrency | No finalize-drain responsiveness/starvation test | `test/codex/io/transport/erlexec_test.exs:1` |
| 4 | MEDIUM | Shutdown | No stubborn SIGTERM-ignoring cleanup regression test | `lib/codex/exec.ex:267` |

## Recommendations for Follow-Up Work

1. Add concurrent subscriber fanout stress tests to transport suite.
2. Upgrade `Codex.Exec` cleanup to an amp-style monitored escalation cascade.
3. Add finalize-drain responsiveness tests for mailbox fairness during shutdown drain.
4. Add stubborn-process cleanup tests across consumer paths (`Exec`, app-server, MCP stdio).

## Overall Verdict

**ACCEPT WITH CAVEATS** — No CRITICAL issues found, but two HIGH gaps (stress coverage and cleanup escalation) should be addressed in follow-up before relying on failure-mode behavior under load.
