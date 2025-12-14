# Agent Prompt: Upstream Sync Implementation (TDD, Elixir)

## Mission

Port the **synced** upstream changes documented in `docs/20251213/upstream-sync-plan/` into the
Elixir SDK **using TDD** (red → green → refactor), without introducing warnings or dialyzer issues.

This repo wraps the upstream `codex` CLI; many upstream Rust features are **transport-dependent**
(exec JSONL vs core/app-server protocol). Your first job is to keep scope honest and tests
deterministic.

## Success Criteria (Non-Negotiable)

- `mix format --check-formatted` passes
- `mix compile --warnings-as-errors` passes (no warnings)
- `mix test` passes (no failures)
- `mix test --include integration` passes (fixture-script integration tests)
- `MIX_ENV=test mix credo --strict` passes
- `MIX_ENV=dev mix dialyzer` passes (no new warnings)
- Docs and examples are updated to match behavior

## Repository Constraints / Rules

- Follow `AGENTS.md` instructions for the repo and any subtrees you touch.
- Treat `codex/` as **third-party** (vendored upstream). **Do not modify** it.
- Treat `openai-agents-python/` as upstream reference. Avoid modifying it (read-only).
- Keep Elixir code idiomatic (pattern matching, small functions, clear typespecs).
- Prefer SDK-native architecture: run-scoped options belong in `Codex.RunConfig`.
- Add features behind tests; do not “ship hope”.

## Scope & Upstream Versions

### openai-agents-python
- Range: `0d2d771..71fa12c` (mainline)
- Tags in range: `v0.6.2` (`9fcc68f`), `v0.6.3` (`8e1fd7a`)
- Key commits referenced in docs:
  - `a9d95b4` — `auto_previous_response_id`
  - `df020d1` — chat-completions logprobs preservation
  - `509ddda` — usage normalization
  - `9f96338` — apply-patch context threading

### codex (codex-rs)
- Range: `6eeaf46ac..a2c86e5d8`
- Key tag in range: `rust-v0.73.0-alpha.1`
- Key commits referenced in docs:
  - `ad7b9d63c` — OTEL export (TOML driven)
  - `92098d36e` — layered config loader + ConfigService (protocol/app-server)
  - `00cc00ead`, `53a486f7e`, `222a49157` — ModelsManager + caching (protocol/app-server)
  - `b36ecb6c3`, `60479a967` — Skills (protocol/core)
  - `4b78e2ab0`, `0ad54982a` — review + unified exec refactors (protocol)

## Required Reading (Do This First)

### This repo (rules + release docs)
- `AGENTS.md`
- `README.md`
- `CHANGELOG.md`

### This repo (audit + upstream sync plan)
- `AUDIT-REPORT.md`
- `docs/20251213/upstream-sync-plan/AUDIT-PROMPT.md` (the original assignment spec)
- `docs/20251213/upstream-sync-plan/00-overview.md`
- `docs/20251213/upstream-sync-plan/01-agents-python-changes.md`
- `docs/20251213/upstream-sync-plan/02-codex-rs-changes.md`
- `docs/20251213/upstream-sync-plan/03-elixir-port-gaps.md`
- `docs/20251213/upstream-sync-plan/04-porting-requirements.md`
- `docs/20251213/upstream-sync-plan/05-implementation-plan.md`

### This repo (testing + TDD conventions)
- `docs/04-testing-strategy.md` (fixtures + integration patterns)
- `docs/08-tdd-implementation-guide.md` (repo TDD conventions)
- `docs/fixtures.md` (fixture inventory + regeneration notes)
- `integration/fixtures/README.md`
- `test/test_helper.exs`

### This repo (API + examples)
- `docs/05-api-reference.md` (public API + types)
- `docs/06-examples.md`
- `examples/README.md`
- `examples/LIVE_EXAMPLES_PROMPT.md`

### This repo (source hotspots)
- `lib/codex/run_config.ex` (run-scoped config; add new options here)
- `lib/codex/agent_runner.ex` (runner loop; state + turn boundaries)
- `lib/codex/thread.ex` and `lib/codex/thread/options.ex` (thread surface + thread config)
- `lib/codex/exec.ex` (exec JSONL decoding + process management)
- `lib/codex/telemetry.ex` (Elixir OTLP exporter; keep distinct from codex-rs OTEL)
- `lib/codex/session/memory.ex` (session adapter used in tests / short-lived runs)
- Tests:
  - `test/codex/agent_runner_test.exs` (RunConfig tests already live here)
  - `test/support/fixture_scripts.ex` (fake `codex` fixture scripts)
  - `test/integration/*` and `test/contract/*` (integration/contract boundaries)

### Upstream references (read-only)

#### Agents Python (reference)
- `openai-agents-python/src/agents/run.py`
- `openai-agents-python/src/agents/usage.py`
- `openai-agents-python/src/agents/models/chatcmpl_helpers.py`
- `openai-agents-python/src/agents/editor.py`

#### Codex (reference)
- `codex/docs/config.md` (source of truth for `[otel]` and config keys)
- `codex/codex-rs/core/src/config/types.rs` (OTEL/config types)
- `codex/codex-rs/exec/src/exec_events.rs` (exec JSONL event schema)
- `codex/codex-rs/protocol/src/protocol.rs` (core protocol; not exec JSONL)

## Work Plan (TDD)

### Phase 0 — Confirm transport scope

The Elixir SDK currently integrates via:
- `codex exec --experimental-json` JSONL stream (stdout JSON lines)

Do **not** assume core/app-server protocol features exist on this transport. If you propose adding
protocol/app-server support, first write a short design note and a minimal spike test proving you
can connect and decode events without breaking existing exec JSONL.

### Phase 1 — agents-python parity (actionable on current transport)

#### 1) Add `auto_previous_response_id` option (API parity + future-proof wiring)

**Requirement**: `docs/20251213/upstream-sync-plan/04-porting-requirements.md` (R1.1–R1.4)

**TDD steps**
1. Add a failing unit test:
   - `RunConfig.new/1` accepts `auto_previous_response_id: true|false`
   - defaults to `false`
   - rejects non-boolean values (match existing validation style)
2. Implement the config field in `lib/codex/run_config.ex`.
3. Add a characterization test for runner behavior:
   - If a backend-provided `response_id` is ever surfaced, the runner should persist “last response
     id” and (when `auto_previous_response_id` is enabled) reuse it as `previous_response_id` for
     the next turn.

**Important**: The current exec JSONL stream does not expose an OpenAI `response_id`. Your tests
must remain deterministic by simulating the field in fixture JSON, and your implementation must be
defensive (no crash if absent).

**Example test sketch (adapt to existing style)**
```elixir
test "RunConfig accepts auto_previous_response_id" do
  assert {:ok, config} = Codex.RunConfig.new(%{auto_previous_response_id: true})
  assert config.auto_previous_response_id

  assert {:ok, config} = Codex.RunConfig.new(%{})
  refute config.auto_previous_response_id

  assert {:error, {:invalid_auto_previous_response_id, "yes"}} =
           Codex.RunConfig.new(%{auto_previous_response_id: "yes"})
end
```

### Phase 2 — Observability alignment (docs-first, optional code)

#### 2) Document codex-rs OTEL export (do not conflate with Elixir OTLP)

**Requirement**: `docs/20251213/upstream-sync-plan/04-porting-requirements.md` (R2.1–R2.3)

**Work**
- Update docs/README to clearly distinguish:
  - Elixir-side OTLP export (`lib/codex/telemetry.ex`, `CODEX_OTLP_ENABLE=1`)
  - codex-rs OTEL export via `~/.codex/config.toml` `[otel]` (see `codex/docs/config.md`)
- If programmatic control is needed, add a small, well-tested hook to run codex with an isolated
  `CODEX_HOME` (generated config directory). Keep this optional and backwards compatible.

### Phase 2.5 — Documentation + Examples (Required)

Update documentation and examples as part of the same TDD loop:
- When adding a new public option/field, update `README.md` and `docs/05-api-reference.md`.
- If you add or change any runnable scripts, update `docs/06-examples.md` and `examples/README.md`.
- Keep the upstream-sync plan docs accurate if implementation decisions change:
  - `docs/20251213/upstream-sync-plan/*`

### Phase 3 — Transport-dependent codex-rs features (only if Phase 0 opts in)

Do **not** implement these on exec JSONL unless the backend surfaces them:
- Skills (protocol/core)
- ModelsManager (protocol/app-server)
- ConfigService (app-server)
- Review mode (protocol)

If adopting protocol/app-server, require:
- a minimal, tested transport module
- clear event/request decoding boundaries
- docs that label which transport exposes which features

## Testing & Quality Workflow

Run frequently while iterating:
```bash
mix format
mix compile --warnings-as-errors
mix test
mix test --include integration
MIX_ENV=test mix credo --strict
MIX_ENV=dev mix dialyzer
```

Prefer targeted runs while in the red/green loop:
```bash
mix test test/codex/agent_runner_test.exs:52
```

## Live Validation (Optional, Real CLI)

Use live scripts under `examples/` to validate behavior against a real `codex` install.

Prereqs:
- `codex` CLI installed and on PATH (or set `CODEX_PATH`)
- authenticated via `codex` login **or** set `CODEX_API_KEY`

Examples:
```bash
mix run examples/live_cli_demo.exs "Say 'ok' and nothing else"
mix run examples/live_session_walkthrough.exs "two turns demo"
mix run examples/live_telemetry_stream.exs
```

If your change affects runner options or env wiring, validate with:
```bash
mix run examples/live_exec_controls.exs "print environment and exit"
```

### Live Tests (Decide + Make Docs Honest)

The repo currently has deterministic unit/integration tests driven by fixture scripts.
If you want “live tests” that hit a real `codex` binary / network:

- Option A (recommended): keep live validation in `examples/live_*.exs` only, and update docs to
  stop implying `mix test` can be toggled “live” by an env var unless that is actually implemented.
- Option B: add a `:live` ExUnit tag that is excluded by default and only enabled when an env var
  is set (e.g., `CODEX_TEST_LIVE=true`), then document:
  - how to enable it (`CODEX_TEST_LIVE=true mix test --only live --include live`)
  - required env (`CODEX_PATH`, auth via CLI login or `CODEX_API_KEY`)
  - strict timeouts + deterministic prompts

Whichever option you choose, ensure README/testing docs match reality.

## Release Tasks (Required for This Assignment)

After implementation is green, perform a patch version bump and release docs updates:

1. Bump patch `x.y.z++`:
   - `mix.exs` (`@version`)
   - `README.md` (dependency snippet + “Current Version” section)
   - Update any version strings that are meant to track the SDK version (including tests/examples
     that assert a literal version value).
2. Add a changelog entry dated `2025-12-13`:
   - `CHANGELOG.md` with a new `## [<new_version>] - 2025-12-13` section
   - Summarize the actual shipped changes (features + docs) with user-facing wording.

## Deliverables

- Code changes with tests (TDD: new tests first, then implementation)
- Updated docs reflecting actual behavior and transport constraints
- Updated runnable examples if behavior is user-facing
- Patch version bump and `2025-12-13` changelog entry (required)
