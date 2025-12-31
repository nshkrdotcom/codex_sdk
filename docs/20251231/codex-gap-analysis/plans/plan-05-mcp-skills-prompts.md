# Implementation Plan - MCP, Skills, and Prompts

Source
- docs/20251231/codex-gap-analysis/05-mcp-skills-prompts.md

Goals
- Implement a spec-compliant MCP JSON-RPC client.
- Provide SDK helpers for MCP config, skills, and custom prompts.

Scope
- MCP client transport and JSON-RPC framing.
- Skills and prompts helpers.
- App-server MCP support enhancements.

Plan
1. Implement MCP JSON-RPC client.
   - Create a transport abstraction for stdio and streamable HTTP.
   - Implement initialize, tools/list, tools/call, resources/list, prompts/list.
   - Use JSON-RPC 2.0 request/response framing with id correlation.
   - Files: lib/codex/mcp/client.ex (plus new modules as needed).
2. Add MCP OAuth token storage/refresh handling.
   - Store tokens in CODEX_HOME config or a dedicated file.
   - Integrate with app-server MCP login endpoints.
   - Files: lib/codex/app_server/mcp.ex, lib/codex/config/layer_stack.ex.
3. Add MCP config helpers.
   - Wrap config/value/write and config/batchWrite for add/list/remove servers.
   - Files: lib/codex/app_server.ex (or new Codex.MCP.Config module).
4. Add Skills helper.
   - Wrap skills/list and load file contents when requested.
   - Respect features.skills gating.
   - Files: lib/codex/app_server.ex, new Codex.Skills module.
5. Add Prompts helper.
   - List prompts from CODEX_HOME/prompts.
   - Implement expansion rules ($1..$9, $ARGUMENTS, KEY=value parsing).
   - Files: new Codex.Prompts module.

Tests
- MCP JSON-RPC unit tests with stub server.
- Skills list and content loading tests.
- Prompt expansion tests with argument parsing.

Docs
- Update README and docs/advanced.md, docs/skills.md, docs/prompts.md.
- Add usage examples for MCP client, skills, and prompts.

Acceptance criteria
- MCP client interoperates with standard MCP servers.
- Skills and prompts helpers match codex CLI behavior.
- OAuth token handling is documented and covered by tests.
