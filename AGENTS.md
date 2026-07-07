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
- Defaults must come from the shared `CliSubprocessCore.ModelRegistry` Codex catalog.
- The allowed bundled Codex picker models are `gpt-5.5` (default), `gpt-5.4`, and `gpt-5.4-mini` (plus the internal, non-picker `codex-auto-review`). Verified against a live `model/list` probe (including hidden entries) against a real, authenticated `codex` CLI install on 2026-07-06 - do not assume the vendored `codex-rs` source snapshot's model list is current; it can list models the live backend no longer serves.
- `Codex.Options` accepts `allow_unknown_model` (default `true`) so a model newer than this bundled list still passes through; do not treat this list as a hard allowlist when reviewing model-related changes.
- Remote model registry is gated by `features.remote_models` (default false) in `config.toml`.
- Keep local presets, upgrade metadata, and reasoning effort normalization aligned with upstream behavior.

## Execution Plane Stack
- `codex_sdk` sits above `cli_subprocess_core`; it should not depend directly on or expose raw `ExecutionPlane.*` internals.
- Use `CliSubprocessCore` facade modules for execution surfaces, transport errors, transport info, and process exits.
- Dependency source selection is handled by `build_support/dependency_sources.exs` and `build_support/dependency_sources.config.exs`.
- Local dependency overrides use `.dependency_sources.local.exs`.
- Default dependency priority is `path -> GitHub -> Hex`; publish mode is Hex-only and must fail with exact blockers if an internal dep is unavailable on Hex.
- Dependency source selection must not use environment variables.
- Weld maintains helper drift, manifests, clone checks, publish checks, and publish order, but this repo is not a Weld consumer in this pass and must not receive a blind Weld dependency.
- Keep `cli_subprocess_core` dependency resolution publish-aware: local path deps for sibling development, GitHub fallback for standalone clones, and Hex constraints for release builds.
- Runtime application code under `lib/**` must not call direct OS env APIs such as `System.get_env`, `System.fetch_env`, `System.put_env`, or `System.delete_env`.
- Runtime and deployment env reads belong in `config/runtime.exs` or an explicit `Config.Provider`.
- Library APIs receive explicit options, config structs, credential providers, application config materialized by the top-level app, or caller-supplied env maps.
- Tests may manipulate env only for config-boundary, SDK compatibility, or live-wrapper checks.
- Live Codex commands use `~/scripts/with_bash_secrets <command>` and must not print secrets.

## ASM Boundary
- Codex-native controls such as app-server, dynamic tools, MCP, sandbox flags and policies, approval flows, realtime, voice, model-provider routing, output schemas, and additional directories belong in this SDK.
- Codex's richer host-tool and app-server surfaces must not define ASM common tools by themselves.
- ASM may derive only common placement/session data unless a caller passes explicit Codex-native overrides through a provider extension or calls this SDK directly.
- Before asserting a Codex-native feature exists, add or update `guides/provider_behavior_manifest.md` with source, fixture, or live-smoke evidence.
- SDK-direct promotion examples in `examples/promotion_path/` must not import or alias ASM.

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
