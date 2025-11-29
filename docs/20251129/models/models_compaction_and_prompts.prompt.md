# Prompt: Sync models, compaction, and prompt handling (TDD)

Required reading:
- docs/20251129/models/models_compaction_and_prompts.md
- docs/05-api-reference.md (model options, reasoning), docs/observability-runbook.md (compaction signals)
- lib/codex/items.ex, lib/codex/thread.ex, lib/codex/telemetry.ex (model selection, history, compaction events)
- test/codex/thread_test.exs, test/codex/items_test.exs, test/codex/telemetry_test.exs

Context to carry:
- Model defaults shift toward gpt-5.1 variants with reasoning-level tweaks; experimental tool-enabled models exist.
- Compaction is on by default; emits explicit compaction events and token-usage updates.
- Truncation helpers were refactored to avoid double truncation and align token accounting.

Instructions (TDD):
1) Read the docs to align on new defaults and compaction/truncation expectations.
2) Add failing tests for model default selection/reasoning options, compaction events, and token-usage updates.
3) Implement model list/default updates and compaction event handling; ensure truncation logic matches upstream (no double truncation).
4) Verify history replay/prompt sizing aligns with the refactored helpers; adjust tests accordingly.
5) Run targeted tests then `mix test`; keep scope to SDK model/prompt/compaction surfaces.
