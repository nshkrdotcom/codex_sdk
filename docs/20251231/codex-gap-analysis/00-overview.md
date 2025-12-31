# Codex vs Elixir SDK Gap Analysis (2025-12-31)

Agent: coordinator

Scope
- Compare canonical ./codex (CLI + app-server + runtime protocols/tools) against the Elixir port in ./ (codex_sdk).
- Known difference: CLI bundling is intentionally excluded.
- Focus on implementable gaps and concrete deviations that can be applied to the Elixir SDK.

Method
- Read upstream docs and protocol/tool definitions in ./codex.
- Cross-check Elixir modules under lib/ and current README.
- Report gaps with file references and implementation notes.

Documents in this report set
- 01-exec-jsonl-and-cli-surface.md: exec JSONL transport and CLI option parity.
- 02-app-server-protocol.md: app-server v2 protocol coverage and missing handlers.
- 03-tools-and-guardrails.md: tool schemas, missing tools, guardrails, and tool registry deviations.
- 04-config-auth-models.md: config parsing, auth, and model registry gaps.
- 05-mcp-skills-prompts.md: MCP client parity, skills, and custom prompt handling.
- 06-sessions-history-undo.md: session history, ghost snapshots, undo/apply.
- 07-observability-rate-limit-errors.md: retries, rate limits, error surface, and timeouts.

Top cross-cutting gaps to prioritize
- Default sandbox policy diverges from codex exec defaults (read-only vs workspace-write).
- apply_patch and shell tool schemas do not match canonical tool definitions.
- app-server missing rawResponseItem/deprecation notifications and fuzzy file search request.
- MCP client is not JSON-RPC compatible with the MCP spec used by codex.
- Keyring-based auth (cli_auth_credentials_store) is not readable by the SDK.
