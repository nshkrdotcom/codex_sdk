# MCP, Skills, and Prompts Gaps

Agent: mcp-skills

Upstream references
- `codex/docs/advanced.md`
- `codex/docs/prompts.md`
- `codex/docs/skills.md`
- `codex/codex-rs/app-server-protocol/src/protocol/common.rs`

Elixir references
- `lib/codex/mcp/client.ex`
- `lib/codex/app_server/mcp.ex`
- `lib/codex/app_server.ex`

Gaps and deviations
- Gap: Codex.MCP.Client is not MCP JSON-RPC compatible. It sends ad-hoc `handshake`, `list_tools`, and `call_tool` messages rather than `initialize`, `tools/list`, and `tools/call`. It also lacks resources/list and prompts/list. Implement a spec-compliant MCP transport (stdio + streamable HTTP). Refs: `lib/codex/mcp/client.ex`, `codex/docs/advanced.md`.
- Gap: no MCP OAuth token storage or refresh handling in the SDK. App-server exposes oauth login URL, but there is no client-side token management. Implement credential storage if direct MCP client support is expanded. Refs: `lib/codex/app_server/mcp.ex`, `codex/docs/config.md`.
- Gap: no helper for `codex mcp` configuration management (add/list/remove servers). Consider a config helper around `config/value/write` and `config/batchWrite`. Refs: `lib/codex/app_server.ex`, `codex/docs/config.md`.
- Gap: skills are listable via app-server, but there is no SDK helper to read skill content, inject into prompts, or honor `features.skills` gating. Provide a Skills helper that wraps `skills/list` and loads file content. Refs: `lib/codex/app_server.ex`, `codex/docs/skills.md`.
- Gap: custom prompts (stored under $CODEX_HOME/prompts) are not surfaced in the SDK. Provide helpers to list and expand prompts (placeholders, argument parsing) to match codex behavior. Refs: `codex/docs/prompts.md`.

Implementation notes
- For MCP, use JSON-RPC framing and implement a transport abstraction compatible with stdio and HTTP streamable servers.
- For prompts, implement the expansion rules ($1..$9, $ARGUMENTS, KEY=value) from upstream docs.
