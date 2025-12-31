# Prompt - MCP, Skills, and Prompts Parity

Goal
Implement all work described in this plan:
- docs/20251231/codex-gap-analysis/plans/plan-00-overview.md
- docs/20251231/codex-gap-analysis/plans/plan-05-mcp-skills-prompts.md

Required reading before coding
Gap analysis doc
- docs/20251231/codex-gap-analysis/05-mcp-skills-prompts.md

Upstream references
- codex/docs/advanced.md
- codex/docs/prompts.md
- codex/docs/skills.md
- codex/codex-rs/app-server-protocol/src/protocol/common.rs
- codex/docs/config.md

Elixir sources
- lib/codex/mcp/client.ex
- lib/codex/app_server/mcp.ex
- lib/codex/app_server.ex
- lib/codex/config/layer_stack.ex

Context and constraints
- Ignore the known CLI bundling difference; do not edit codex/ except for reference.
- Coordinate with any config changes from prompt-01; extend existing config structures rather than duplicating them.
- Use ASCII-only edits.

Implementation requirements
- Implement a spec-compliant MCP JSON-RPC client (initialize, tools/list, tools/call, resources/list, prompts/list).
- Add MCP OAuth token storage and refresh handling tied to app-server MCP login.
- Provide helpers for MCP configuration management (add/list/remove servers).
- Add Skills helper to list and load skill content, gated by features.skills.
- Add Prompts helper to list and expand custom prompts ($1..$9, $ARGUMENTS, KEY=value).

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
