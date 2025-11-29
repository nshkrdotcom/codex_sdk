# Prompt: Align auth, account, and session handling (TDD)

Required reading:
- docs/20251129/auth/auth_and_sessions.md
- docs/05-api-reference.md (session/account behavior)
- lib/codex/thread.ex, lib/codex/items.ex, lib/codex/approvals.ex (conversation lifecycle, approvals)
- test/codex/thread_test.exs, test/codex/approvals_test.exs

Context to carry:
- `/new` drops existing conversations; early-exit sessions are not persisted.
- Upgrade checks can be skipped for enterprises; rollout init errors clarified.
- Rate-limit and sandbox assessment fixes may change error shapes.

Instructions (TDD):
1) Read the docs to fix desired lifecycle/upgrade behaviors.
2) Add failing tests for `/new` conversation resets, non-persistence of early-exit sessions, and updated error parsing (rate-limit/sandbox assessment).
3) Implement conversation/session handling and error normalization to satisfy tests.
4) Document any divergence if the SDK cannot skip upgrade prompts when embedded.
5) Run targeted tests then `mix test`; keep scope to auth/session flows.
