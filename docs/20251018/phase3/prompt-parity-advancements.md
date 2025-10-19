# Prompt: Parity Advancements (Tool Bridging, Rich Events, Structured Output)

## Required Reading
- `docs/20251018/python-parity-status.md`
- `docs/20251018/codex-sdk-completion/module-implementation.md`
- `codex/codex-rs/exec/src/cli.rs`
- `codex/codex-rs/exec/src/exec_events.rs`
- `codex/codex-rs/core/tests/suite/tool_harness.rs`
- `lib/codex/thread.ex`
- `lib/codex/exec.ex`
- `lib/codex/events.ex`
- `lib/codex/turn/result.ex`
- `codex/sdk/typescript/src/thread.ts`

> Make sure you understand how the TypeScript SDK forwards tool outputs and structured schemas, how the Rust event schema represents command/file/MCP/web-search/todo items, and how the Elixir thread pipeline currently processes events and turn results.

## Context
We recently added schema persistence, basic tool output tracking, and item lifecycle support in the Elixir SDK. The next parity push focuses on:
1. Replaying tool outputs/failures back into `codex exec` so continuation attempts mirror Python.
2. Surfacing rich item structs (command executions, file diffs, MCP/tool activity, web search, todo list) so downstream code can reason about event payloads without ad-hoc maps.
3. Decoding structured responses into typed maps/structs (rather than raw JSON strings) and exposing helper APIs for callers.

The Rust CLI already supports these capabilities; our Elixir layer must catch up while preserving the existing TDD discipline.

## Implementation Instructions (TDD)
Work through each focus area sequentially, following red/green/refactor for every change. Keep the tests isolated and deterministic by relying on fixture scripts or new unit tests where appropriate.

1. **Tool Output Forwarding**
   - *Red*: add regression tests that assert `Codex.Exec` forwards tool outputs/failures (e.g., capture CLI args or simulate multiple continuation attempts). Ensure tests fail until the CLI contract is honored.
   - *Green*: confirm the CLI flag/JSON payload required by `codex exec` (consult Rust tests) and plumb the pending outputs/failures from `Codex.Thread` into `Codex.Exec`. Update auto-run tests to validate end-to-end behavior.
   - *Refactor*: clean up temporary scaffolding, deduplicate argument assembly, and document the contract in code comments.

2. **Rich Event Structs**
   - *Red*: expand `Codex.EventsTest` (and any integration tests) to expect typed structs for command execution, file change, MCP tool call, web search, and todo list events. Cover both parse and round-trip serialization.
   - *Green*: implement the structs and parser updates in `Codex.Events`, update the turn-event reducer in `Codex.Thread` (planned as {@literal Codex.Thread.fold_events/2}) to incorporate new metadata, and ensure the turn result reflects richer data.
   - *Refactor*: consolidate shared helpers, keep the struct definitions organized, and update docs or doctests as needed.

3. **Structured Response Decoding**
   - *Red*: write tests validating that `Codex.Thread.run/3` returns decoded maps when an output schema is supplied (include failure cases for invalid JSON). Consider property-based tests for schema-conformant payloads.
   - *Green*: add a decoder layer (e.g., helper function or new module) that takes the final response and, when the schema is present, parses the JSON into maps/structs. Ensure streaming callers receive consistent types.
   - *Refactor*: extract reusable utilities, surface helper APIs for callers (e.g., `Codex.Turn.Result.json/1`), and document the behavior.

## Deliverables
- Updated tests and implementation across the Elixir SDK covering the three focus areas.
- Any new fixture scripts or harvested transcripts needed to exercise the behavior.
- Documentation or comments capturing CLI contracts and structured-response semantics.
- Update `docs/20251018/python-parity-status.md` after completion to reflect the newly closed gaps.
