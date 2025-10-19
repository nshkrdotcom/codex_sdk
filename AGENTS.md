# Repository Guidelines

## Project Structure & Module Organization
The Elixir source lives in `lib/`, with public modules under `CodexSdk` expected to wrap the upstream `codex` binary. Unit and integration tests sit in `test/`, sharing helpers via `test_helper.exs`. Long-form design notes and API references are in `docs/`, while `doc/` is Mix-generated HTML that should remain untouched. Brand assets (logos, diagrams) live in `assets/`. The vendored upstream CLI and related tooling are isolated under `codex/`; treat that subtree as third-party code and avoid modifying it without coordinating upstream.

## Build, Test, and Development Commands
Run `mix deps.get` once per checkout to install dependencies. Compile the SDK with `mix compile` and check for warnings. Execute `mix test` for the default ExUnit suite; pass `MIX_ENV=test mix credo --strict` to lint with Credo’s strict checks. Use `mix format` to apply the shared formatter, and finish release branches with `MIX_ENV=dev mix dialyzer` once the PLTs are cached. Generate versioned HTML docs via `mix docs`.

## Coding Style & Naming Conventions
Prefer idiomatic Elixir: two-space indentation, guard-heavy pattern matching, and pipeline-friendly function signatures. Modules use PascalCase (`Codex.Thread`), functions and variables use snake_case, and atoms stay lowercase. Keep public APIs documented with `@doc` and include doctests when feasible. Run `mix format` before every commit; CI will enforce the same rules via `.formatter.exs`. Handle lint feedback (`mix credo --strict`) before opening a PR.

## Testing Guidelines
Write ExUnit tests alongside the code they cover, using descriptive `"module: behavior"` string names. Mock external processes with Mox and rely on Supertester for deterministic GenServer supervision scenarios. For coverage, ensure `mix coveralls` remains above the baseline reported in CI; prefer adding focused tests rather than loosening assertions. When reproducing race conditions, use `mix test --seed 0 --trace` to force deterministic ordering.

## Commit & Pull Request Guidelines
History shows compact subject lines (`fb`, `initial import, for v0.1.0 design release`); continue using short, present-tense subjects under 50 characters, optionally adding a scope prefix (`sdk: add streaming`). Squash incidental commits before pushing. Pull requests should outline motivation, highlight any API changes, list manual or automated test runs, and link the relevant issue. Include screenshots or terminal transcripts when behavior changes are user-facing.
