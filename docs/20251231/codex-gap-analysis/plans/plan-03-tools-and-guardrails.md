# Implementation Plan - Tools and Guardrails

Source
- docs/20251231/codex-gap-analysis/03-tools-and-guardrails.md

Goals
- Align tool schemas and aliases with upstream codex definitions.
- Implement missing tools (shell_command, write_stdin, view_image, canonical web_search).
- Match apply_patch grammar and semantics.
- Enforce guardrail behavior semantics and parallel execution.

Scope
- Tool registry and schema definitions.
- Tool implementations for shell, apply_patch, web_search, and view_image.
- Guardrail execution flow in agent runner.

Plan
1. Align shell tool schema.
   - Update shell tool to accept argv arrays, workdir, timeout_ms, sandbox permissions,
     and justification.
   - Preserve compatibility with existing string command format (fallback parsing).
   - Files: lib/codex/tools/shell_tool.ex.
2. Add shell_command tool and aliases.
   - Implement a tool that matches upstream schema (string command, login flag).
   - Add aliases: container.exec, local_shell, shell_command.
   - Files: lib/codex/tools/hosted_tools.ex, lib/codex/tools/registry.ex.
3. Add write_stdin tool.
   - Expose a tool that forwards to command_write_stdin for exec sessions.
   - Files: lib/codex/tools/hosted_tools.ex, lib/codex/app_server.ex.
4. Port apply_patch grammar.
   - Implement the *** Begin Patch grammar used upstream, including add/delete/update/move.
   - Preserve current unified diff support as a fallback for compatibility.
   - Files: lib/codex/tools/apply_patch_tool.ex.
5. Add view_image tool.
   - Implement view_image tool and produce corresponding item output.
   - Files: lib/codex/tools/hosted_tools.ex, lib/codex/items.ex.
6. Align web_search tool schema.
   - Implement canonical web_search tool gated by features.web_search_request.
   - Map to existing provider adapters or return a clear error when unavailable.
   - Files: lib/codex/tools/web_search_tool.ex, lib/codex/tools/hosted_tools.ex.
7. Guardrail semantics and parallel execution.
   - Respect run_in_parallel using Task.async_stream.
   - Implement behavior handling: allow, reject, raise (distinguish tripwire if needed).
   - Files: lib/codex/tool_guardrail.ex, lib/codex/guardrail.ex, lib/codex/agent_runner.ex.
8. Decide on SDK-only tools.
   - Either gate with feature flags or document as SDK-only extensions.
   - Files: lib/codex/tools/hosted_tools.ex, README/docs.

Tests
- Add schema validation tests for new tools and aliases.
- Add apply_patch parsing tests for add/delete/update/move paths.
- Add guardrail behavior tests for allow/reject/raise and parallel execution.
- Add web_search gating tests.

Docs
- Update README and docs/ to list tool schemas and guardrail behavior.
- Document compatibility behavior for legacy shell/apply_patch inputs.

Acceptance criteria
- Tool schemas match upstream; model tool calls can be reused across transports.
- Guardrail semantics match upstream behavior.
- All new tools have tests and documentation.
