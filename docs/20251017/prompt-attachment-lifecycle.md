# Prompt: Attachment Lifecycle Manager (2025-10-17)

## Required Reading
- `docs/20251017/attachment-lifecycle.md`
- `docs/design/attachments-files.md`
- `lib/codex/files.ex`
- `test/codex/files_test.exs`, `test/integration/attachment_pipeline_test.exs`

## TDD Checklist
1. **Red** – extend tests:
   - Add tests ensuring staged entries track `inserted_at` and TTL.
   - Integration test forcing cleanup (manual trigger) removes expired files.
   - Telemetry test asserting `[:codex, :attachment, :staged]` / `:cleaned` events.
   - Metrics test verifying `Codex.Files.metrics/0` returns counts/bytes.
2. **Green** – implement GenServer registry, periodic cleanup, metrics accessor.
3. **Refactor** – update docs, ensure staging helpers reuse registry, run `mix format`, `mix test`, `mix codex.verify`.
