# Execution plan (TDD-first) to close applicable gaps

This plan is ordered by “live compatibility” impact: fixes that prevent the SDK from working
against a real `codex exec` come first.

## Phase 0 — Lock transport scope (exec JSONL only)

1. Document (and enforce in code/docs) that the default transport is:
   - `codex exec --experimental-json`
2. Treat protocol/app-server-only features as explicitly out of scope until a transport spike
   proves we can connect and decode events safely.

## Phase 1 — Make exec argument building match real `codex exec --help`

**Goal**: eliminate SDK-spawned `codex exec` invocations that fail due to unknown flags.

TDD checklist:

1. Add failing tests that assert we only emit flags present in `codex exec --help`.
   - Keep tests deterministic by asserting against a *known* allowlist (derived from upstream
     `codex/codex-rs/exec/src/cli.rs`) rather than shelling out to a local binary.
2. Update `lib/codex/exec.ex` arg builder:
   - Map image attachments to `--image` (if we keep a concept of “attachments” on exec transport).
   - Remove or gate any unsupported flags (`--attachment`, `--tool-output`, `--tool-failure`).
3. Update docs and examples to reflect what is truly supported on exec transport:
   - If “attachments” exist in the SDK, label them as **images only** for exec.
   - Move tool-calling examples behind an explicit “requires non-exec transport” label (or remove
     from `run_all.sh`) until a real transport exists.

## Phase 2 — Refresh fixtures to reflect canonical exec JSONL schema

**Goal**: deterministic fixtures should resemble the real CLI so tests catch schema drift.

TDD checklist:

1. Add a new minimal fixture transcript that matches `exec_events.rs` exactly:
   - `thread.started` (thread_id only)
   - `turn.started` (no ids)
   - `item.completed` reasoning + agent_message
   - `turn.completed` usage only
2. Add unit tests for `Codex.Events.parse!/1` and `Codex.Items.parse!/1` against that fixture.
3. Keep backwards compatibility:
   - Preserve existing richer fixtures, but mark them as “legacy/extended” and add explicit tests
     proving we can decode both shapes.

## Phase 3 — Expose missing exec flags as explicit SDK options

**Goal**: make common `codex exec` flags reachable without requiring users to hand-roll env/args.

Candidates (all supported upstream in `exec/src/cli.rs`):

- `--skip-git-repo-check`
- `--cd <dir>` and `--add-dir <dir>`
- sandbox policy flags (`--sandbox`, `--full-auto`, `--dangerously-bypass-approvals-and-sandbox`)
- `--output-last-message <file>` (if useful for integrations)

Approach:

- Put “run-scoped” toggles in `Codex.RunConfig` (or `Codex.Thread.Options` if they are truly
  per-thread).
- Add validation tests first (reject invalid types/values).
- Add integration tests that assert the generated CLI args include the correct flags.

## Phase 4 — Optional: exec review wrapper

Upstream now supports `codex exec review ...`.

If we want to expose it:

- Add `Codex.Review` with a small API that maps to the CLI (`uncommitted`, `base`, `commit`, etc).
- Provide a dedicated fixture-driven test (no network) and a `:live` smoke test.

## Phase 5 — Optional: isolated `CODEX_HOME` hook (for codex-rs config / `[otel]`)

If programmatic codex-rs config becomes important:

- Add a small helper that creates a temporary config dir containing a generated `config.toml`.
- Run `codex` with `CODEX_HOME=<tempdir>` in the exec environment.
- Add unit tests ensuring the env var is set only when requested and cleaned up reliably.

## Phase 6 — Expand live validation (developer-only)

Keep live tests small and explicit:

- `mix test --only live --include live` should run a handful of fast prompts.
- Add a “schema probe” live test that asserts the event sequence matches `exec_events.rs`
  (presence of `thread.started`, `turn.started`, `item.completed`, `turn.completed`).

## Done definition

- `mix format --check-formatted`
- `mix compile --warnings-as-errors`
- `mix test`
- `mix test --include integration`
- `MIX_ENV=test mix credo --strict`
- `MIX_ENV=dev mix dialyzer`
- README / API reference / examples accurately describe what works on exec JSONL vs what requires
  another transport.

