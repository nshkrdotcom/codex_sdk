# Prompt: Configurable Sandbox Hooks (2025-10-17)

## Required Reading
- `docs/20251017/sandbox-hooks.md`
- `docs/design/sandbox-approvals.md`
- `lib/codex/approvals.ex` and `lib/codex/thread/options.ex`
- `test/codex/thread_auto_run_test.exs`

## TDD Checklist
1. **Red** – add tests covering sync + async hooks:
   - New unit tests for `Codex.Approvals` dispatcher (sync allow/deny, async with timeout).
   - Integration test simulating delayed approval via fake hook module.
   - Telemetry capture test asserting `[:codex, :approval, ...]` events.
2. **Green** – implement behaviour, ETS registry, and dispatcher updates to make tests pass.
3. **Refactor** – cleanup duplication, document new options, ensure `mix format`, `mix test`, `mix compile --warnings-as-errors` are green, update relevant docs.
