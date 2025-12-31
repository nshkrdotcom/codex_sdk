# Prompt - Tools and Guardrails Parity

Goal
Implement all work described in this plan:
- docs/20251231/codex-gap-analysis/plans/plan-00-overview.md
- docs/20251231/codex-gap-analysis/plans/plan-03-tools-and-guardrails.md

Required reading before coding
Gap analysis doc
- docs/20251231/codex-gap-analysis/03-tools-and-guardrails.md

Upstream references
- codex/codex-rs/core/src/tools/spec.rs
- codex/codex-rs/core/src/tools/handlers/apply_patch.rs

Elixir sources
- lib/codex/tools/shell_tool.ex
- lib/codex/tools/apply_patch_tool.ex
- lib/codex/tools/web_search_tool.ex
- lib/codex/tools/hosted_tools.ex
- lib/codex/tools/registry.ex
- lib/codex/tool_guardrail.ex
- lib/codex/guardrail.ex
- lib/codex/agent_runner.ex
- lib/codex/items.ex

Context and constraints
- Ignore the known CLI bundling difference; do not edit codex/ except for reference.
- Preserve backward compatibility; accept legacy tool schemas while adding upstream formats.
- Use ASCII-only edits.

Implementation requirements
- Align shell tool schema with upstream (argv array, workdir, timeout_ms, sandbox permissions).
- Add shell_command tool and aliases (container.exec, local_shell, shell_command).
- Add write_stdin tool.
- Implement upstream apply_patch grammar and semantics; keep unified diff support as fallback.
- Add view_image tool.
- Align web_search tool schema and gating with features.web_search_request.
- Implement guardrail run_in_parallel and behavior semantics (allow/reject/raise).
- Decide how to expose SDK-only tools (feature flag or docs).

Documentation and release requirements
- Update README.md and any affected guides in docs/ and examples/.
- Update CHANGELOG.md 0.4.6 entry with the changes implemented here.
- Update the 0.4.6 highlights in README.md.

Testing and quality requirements
- Run: mix format
- Run: mix test
- Run: MIX_ENV=test mix credo --strict
- Run: MIX_ENV=dev mix dialyzer
- No warnings or errors are acceptable.

Deliverable
- Provide a concise change summary and list the tests executed.
