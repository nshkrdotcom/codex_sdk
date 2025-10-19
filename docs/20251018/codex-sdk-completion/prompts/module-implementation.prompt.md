# Prompt: Finalize Module Implementations

## Required Reading
1. `docs/20251018/codex-sdk-completion/module-implementation.md`
2. Related design documents for each module:
   - Events: `docs/design/turn-execution.md`, existing event usage in `lib/codex/`
   - Tools & MCP: `docs/design/tools-mcp.md`
   - Sandbox & Approvals: `docs/design/sandbox-approvals.md`
   - Attachments & Files: `docs/design/attachments-files.md`
   - Structured Output: `docs/design/structured-output.md`
   - Observability: `docs/design/observability-telemetry.md`
   - Error Handling: `docs/design/error-handling.md`
3. Current implementations: inspect `lib/codex/*.ex`, `lib/codex/thread/*.ex`, `lib/codex/turn/*.ex`.
4. Existing tests in `test/codex/` and `test/contract/`.

## Implementation Instructions
1. Select a module or feature area described in the module implementation doc.
2. Write failing tests that capture the missing behavior leveraging Supertester and existing fixture infrastructure.
3. Implement the functionality incrementally, ensuring each new behavior is introduced only after a red test.
4. Maintain the Elixir style guide: two-space indentation, meaningful names, `@doc` annotations, doctests where suitable.
5. For cross-cutting features (e.g., structured output integration with the turn pipeline), keep commits and tests scoped; avoid diving into other modules unless required by the current feature.
6. Run `mix test`, `mix compile --warnings-as-errors`, and any relevant tagged suites (`mix test --include integration`, contract tests once fixtures exist).
7. Confirm zero warnings and update documentation when implementations are complete.
