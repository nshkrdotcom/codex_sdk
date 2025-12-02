# ADR-005: Expose Hosted Tool Configs (Search, Shell, Apply Patch, Computer, Image, Code Interpreter)

Status: Proposed

Context
- Python: `src/agents/tool.py` includes hosted tool classes (`FileSearchTool`, `WebSearchTool`, `ShellTool`/`LocalShellTool`, `ApplyPatchTool`, `ComputerTool`, `ImageGenerationTool`, `CodeInterpreterTool`) with safety/approval callbacks and configuration fields; runner dispatches them in `_run_impl.py`.
- Elixir: no first-class hosted tool configs; relies on codex binary defaults without SDK-level wiring for safety/approval hooks.

Decision
- Add Elixir structs for each hosted tool type with fields aligned to Python (vector_store_ids/filters, shell timeouts/output caps, apply_patch editor, computer safety callback, image generation params, code interpreter settings).
- Update runner to advertise hosted tools to codex exec and route tool calls to provided executors/editors/safety hooks.
- Prefer the modern `ShellTool` style while keeping a compatibility path if codex exposes legacy local shell calls.

Consequences
- Benefits: feature parity for search, code execution, patching, computer control, and image generation; enables approval/safety policies.
- Risks: depends on codex binary support; high surface area for security-sensitive features; executor APIs must be carefully designed.
- Actions: model hosted tool structs, map to codex request payloads, implement dispatch plumbing, and add tests mirroring `tests/test_shell_tool.py`, `tests/test_apply_patch_tool.py`, `tests/test_computer_action.py`, `tests/test_tool_use_behavior.py`, `tests/test_image_generation` (if available).
