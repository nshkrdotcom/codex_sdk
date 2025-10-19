# Prompt: Complete Remaining Milestones

## Required Reading
1. `docs/20251018/codex-sdk-completion/milestone-roadmap.md`
2. `docs/08-tdd-implementation-guide.md`
3. `docs/python-parity-checklist.md`
4. `docs/fixtures.md`
5. `integration/fixtures/README.md`
6. For milestone-specific work, review the corresponding design notes:
   - M1: `docs/design/thread-lifecycle.md`, `docs/design/turn-execution.md`
   - M2: `docs/design/tools-mcp.md`, `docs/design/sandbox-approvals.md`
   - M3: `docs/design/attachments-files.md`, `docs/design/structured-output.md`
   - M4: `docs/design/observability-telemetry.md`, `docs/design/error-handling.md`
   - M5: `docs/20251018/codex-sdk-completion/testing-and-ci.md`

## Implementation Instructions
1. For the targeted milestone, enumerate the remaining acceptance criteria and convert each into one or more failing tests (unit, integration, contract) before writing implementation code.
2. Follow strict TDD:
   - Add tests that fail for missing functionality.
   - Implement minimal code to pass the tests.
   - Refactor while keeping the suite green.
3. Ensure all new code is formatted with `mix format` and documented (`@doc`, doctests where applicable).
4. Run the full suite (`mix compile --warnings-as-errors`, `mix test`, relevant tagged suites, coverage/lint tasks) verifying zero warnings and all tests passing.
5. Update related checklists (`docs/python-parity-checklist.md`, milestone status) and documentation to reflect completed work.
6. Repeat the process milestone by milestone until all are marked complete; do not proceed to the next milestone until the current one is fully green with no warnings.
