# Remaining Testing & CI Requirements

This document details the outstanding test coverage, automation, and CI pipeline work needed to support full Codex SDK delivery.

## Test Coverage Backlog

| Area | Required Additions | Milestone |
|------|-------------------|-----------|
| Event Domain | StreamData property suite, full fixture decoding coverage | M1 |
| Turn Pipeline | Auto-run loop tests, cancellation, usage aggregation | M1 |
| Tooling & MCP | Tool registry unit tests, MCP handshake integration | M2 |
| Approvals & Sandbox | Policy combinator property tests, integration scenarios | M2 |
| Attachments | Chunked upload integration tests, cleanup assertions | M3 |
| Structured Output | Schema builder doctests, invalid payload error handling | M3 |
| Observability | Telemetry snapshot tests, log diff tests | M4 |
| Error Handling | Failure fixture contract tests | M4 |
| Regression Harness | Python vs Elixir diff runner, nightly job | M5 |

## Supertester Adoption Tasks
- Introduce `Codex.SupertesterCase` with `use Supertester.UnifiedTestFoundation`.
- Replace manual Port mocks with `Supertester.GenServerHelpers` where applicable.
- Add `assert_no_process_leaks/1` checks to integration suites.
- Document Supertester patterns in `docs/04-testing-strategy.md`.

## Fixture Management
- Implement fixture checksum manifest to detect drift.
- Automate fixture regeneration via CI job invoking `scripts/harvest_python_fixtures.py`.
- Store structured-output schemas under `integration/fixtures/schemas` (pending for M3).

## CI Pipeline Enhancements
1. **Per-PR Jobs**
   - `mix compile --warnings-as-errors`
   - `mix format --check-formatted`
   - `mix test --include integration`
   - `mix coveralls.github`
   - `mix credo --strict`
2. **Nightly Jobs**
   - `mix codex.parity` (Python vs Elixir diff)
   - `MIX_ENV=dev mix dialyzer` (with cached PLTs)
   - Fixture regeneration + diff check
3. **Cross-Platform**
   - Matrix for Ubuntu/macOS to validate binary handling and file permissions.

## Test Tooling Backlog
- Build fake codex binary generator (configurable event scripts) for integration tests.
- Add telemetry capture helper to simplify event assertions.
- Provide Mox-compatible wrappers for tool registry to maintain async tests.

## Success Metrics
- ≥95 % coverage maintained in CI (`mix coveralls`).
- All tests `async: true` except where external orchestration forbids (document exceptions).
- Zero flaky tests over a 30-day window (monitored via CI stability dashboard).
- Nightly parity harness produces zero diffs or opens blocking issue automatically.
