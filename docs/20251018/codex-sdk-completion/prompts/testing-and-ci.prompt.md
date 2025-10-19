# Prompt: Complete Testing & CI Backlog

## Required Reading
1. `docs/20251018/codex-sdk-completion/testing-and-ci.md`
2. `docs/04-testing-strategy.md`
3. `docs/fixtures.md` and fixture structure under `integration/fixtures/`.
4. Supertester reference: `test/support/` helpers and `mix.exs` dependency versions.
5. CI references (if present): `.github/workflows/`, `mix.exs` `docs` & `preferred_cli_env` sections.

## Implementation Instructions
1. Enumerate pending test coverage items from the backlog table; pick one scope at a time (e.g., event property tests, auto-run coverage).
2. Add failing tests using appropriate tooling (Supertester, StreamData, integration harness) to capture each gap.
3. Implement code to satisfy the new tests while keeping the suite green.
4. Integrate missing CI commands:
   - Update workflow definitions to run compilation, formatting, tests, coverage, credo, dialyzer, and nightly parity tasks as described.
5. Ensure automation scripts exist for fixture regeneration and parity harness execution; add tests or CI checks where applicable.
6. Run the entire suite locally, confirm zero warnings, and document CI updates within the docs directory.
