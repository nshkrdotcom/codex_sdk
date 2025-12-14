# Multi-Transport Refactor (Exec + App-Server)

This doc set describes a proposed **major refactor** of `codex_sdk` to achieve **feature parity** with upstream `codex` by supporting both:

1. `codex exec --json` (JSONL over stdout; one-shot process per run)
2. `codex app-server` (stateful, bidirectional JSON-RPC over stdio)

It also explains what is and is not currently possible regarding **Skills** and `UserInput::Skill`.

## Index

### Analysis & Context
- [`01_upstream_surfaces.md`](./01_upstream_surfaces.md) — What upstream "transports" exist (TUI vs exec vs app-server) and what TS/Python projects do
- [`02_userinput_skill_and_skills.md`](./02_userinput_skill_and_skills.md) — `UserInput::Skill` reality: defined in core, used by TUI, not exposed by app-server v2
- [`03_current_elixir_state.md`](./03_current_elixir_state.md) — What `codex_sdk` does today (exec JSONL only) and why it's insufficient for app-server-only APIs

### Architecture & Implementation
- [`04_target_architecture.md`](./04_target_architecture.md) — Recommended Elixir architecture (transport behaviour + app-server connection GenServer)
- [`05_app_server_protocol_inventory.md`](./05_app_server_protocol_inventory.md) — App-server method/notification inventory and message framing notes
- [`06_parity_matrix.md`](./06_parity_matrix.md) — Feature parity matrix (exec vs app-server vs TUI/core vs `codex_sdk`)
- [`07_phased_implementation_plan.md`](./07_phased_implementation_plan.md) — Proposed phases for the refactor + delivery plan
- [`08_testing_strategy.md`](./08_testing_strategy.md) — Contract + integration testing strategy for app-server

### Design Review Additions (2025-12-14)
- [`09_requirements_and_nongoals.md`](./09_requirements_and_nongoals.md) — **NEW**: Explicit parity definitions, requirements, and out-of-scope items
- [`10_protocol_mapping_spec.md`](./10_protocol_mapping_spec.md) — **NEW**: Complete method-by-method mapping with Elixir API names and return types
- [`11_failure_modes_and_recovery.md`](./11_failure_modes_and_recovery.md) — **NEW**: Timeouts, crashes, reconnect strategies, and error handling
- [`12_public_api_proposal.md`](./12_public_api_proposal.md) — **NEW**: Elixir modules/functions/options and backwards compatibility story
- [`13_executive_summary.md`](./13_executive_summary.md) — **NEW**: Risks, missing requirements fixed, and upstream blockers

## Related (skills pull analysis)

This refactor doc set complements the 2025-12-14 upstream pull analysis:
- `docs/20251214/git_diff_analysis/changes-summary.md`
- `docs/20251214/skills_analysis/skills-comparison.md`
- `docs/20251214/protocol_changes/new-protocol-types.md`
- `docs/20251214/technical_plan/porting-plan.md`

