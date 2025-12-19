# Repository Guidelines

## Project Structure & Module Organization
- `lib/` holds Elixir source. Public modules live under `CodexSdk` and wrap the upstream `codex` CLI.
- `test/` contains ExUnit unit/integration tests; shared helpers live in `test_helper.exs`.
- `docs/` holds design notes, migration docs, and API references. `doc/` is Mix-generated HTML and should not be edited.
- `examples/` contains runnable scripts; keep them aligned with current defaults and auth behavior.
- `assets/` stores brand assets. The vendored CLI and tooling live under `codex/` and should be treated as third-party.
- `priv/` contains runtime assets (ex: model registry JSON). Keep these in sync with upstream sources.

## Build, Test, and Development Commands
- Install deps: `mix deps.get`
- Compile: `mix compile` (resolve warnings)
- Format: `mix format`
- Unit tests: `mix test`
- Lint: `MIX_ENV=test mix credo --strict`
- Dialyzer: `MIX_ENV=dev mix dialyzer` (after PLTs are cached)
- Docs: `mix docs`

## Coding Style & Naming Conventions
- Use idiomatic Elixir (2-space indentation, guard-heavy pattern matching, pipeline-friendly signatures).
- Modules: PascalCase (`Codex.Thread`); functions/vars: snake_case; atoms: lowercase.
- Public APIs must have `@doc` and doctests when feasible.
- Keep changes minimal and avoid touching `codex/` without explicit upstream coordination.

## Model Registry and Auth Behavior
- Auth mode inference order: `CODEX_API_KEY`, then `auth.json` `OPENAI_API_KEY`, else ChatGPT tokens.
- Defaults must be auth-aware; prefer `codex-auto-balanced` when available.
- Remote model registry is gated by `features.remote_models` (default false) in `config.toml`.
- Keep local presets, upgrade metadata, and reasoning effort normalization aligned with upstream behavior.

## Testing Guidelines
- Use descriptive ExUnit test names: `"module: behavior"`.
- Mock external processes with Mox; prefer deterministic GenServer tests via Supertester.
- Maintain or improve `mix coveralls` baseline from CI; add focused tests rather than weakening assertions.
- For race conditions: `mix test --seed 0 --trace`.

## Documentation & Examples
- Update README and `docs/` for API changes, defaults, and behavior changes.
- Keep `examples/` runnable with current defaults; avoid hard-coded models unless required.
- Mention any auth or model registry changes in example output and docs.

## Versioning, Changelog, and Releases
- Bump versions consistently in `mix.exs`, `README.md`, `CHANGELOG.md`, and `VERSION`.
- Add a dated changelog entry for behavior changes.
- Keep release notes compact and action-oriented.

## Commit & Pull Request Guidelines
- Use short, present-tense commit subjects under 50 characters; scope prefixes are allowed (`sdk: add streaming`).
- Squash incidental commits before pushing.
- PRs should include motivation, API changes, test runs, and issue links. Include screenshots or terminal transcripts for user-facing behavior changes.
