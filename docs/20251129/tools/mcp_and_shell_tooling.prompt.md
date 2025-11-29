# Prompt: Update MCP and shell tooling support (TDD)

Required reading:
- docs/20251129/tools/mcp_and_shell_tooling.md
- docs/06-examples.md (tooling examples), docs/05-api-reference.md (tool call schemas)
- lib/codex/tools.ex, lib/codex/tools/registry.ex, lib/codex/exec.ex (tool call execution/registration)
- test/codex/tools_test.exs, test/codex/thread_test.exs (tool call streaming)

Context to carry:
- MCP elicitations are supported; shell-tool-mcp declares capabilities and publishing is fixed.
- Tool calls can include richer arguments/results with streamed output.
- Git branch context and env overrides may be surfaced alongside unified exec.

Instructions (TDD):
1) Read the docs to understand new MCP capability metadata and elicitation handling.
2) Add failing tests for elicitation parsing, capability propagation, and streamed argument/result payloads.
3) Implement registry/protocol updates so tool calls preserve new fields and streams; ensure backwards compatibility.
4) Decide and document whether git branch/env wiring is exposed in SDK APIs; add tests if surfaced.
5) Run targeted tests then `mix test`; keep scope to SDK-facing tooling.
