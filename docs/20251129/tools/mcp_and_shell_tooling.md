# MCP and shell tooling changes relevant to the Elixir SDK

Key upstream updates:
- MCP elicitations are now supported; shell-tool-mcp declares its server capability and publishing flow was fixed.
- Unified exec and MCP tool calls include richer arguments/results, with streaming events for tool output.
- Git branch tooling and custom env for unified exec are available for integrations that expose repository context.

SDK impact:
- If the SDK proxies MCP, extend protocol handling to support elicitations and the updated capability metadata.
- Tool-call parsing should accept richer payloads (arguments, streamed results) without discarding fields.
- Expose git branch context and env overrides where appropriate so parity with the CLI is maintained.

Action items:
- Update MCP client/server adapters to recognize elicitations and the latest shell-tool-mcp capabilities.
- Add decoding tests for streamed tool output and argument-rich tool calls.
- Decide whether to surface git branch/env wiring in SDK APIs or document the absence explicitly.
