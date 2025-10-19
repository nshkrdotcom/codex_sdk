# Tooling & MCP Design

## Feature Summary
- Recreate Python tooling API: register tools, bridge to MCP protocol, and enable auto-run orchestration.
- Provide behaviors for synchronous and asynchronous tools, supporting metadata, parameters, and structured outputs.
- Manage external MCP servers under supervision, mirroring Python's server lifecycle.

## Subagent Perspectives
### Subagent Astra (API Strategist)
- Design `Codex.Tools.register/2` accepting module + options, returning registration tokens for deregistration.
- Offer macro or DSL similar to Python decorators: `use Codex.Tool, name: "web_search"`.
- Expose MCP client API for connecting to remote servers (`Codex.MCP.connect/2`) with session contexts.

### Subagent Borealis (Concurrency Specialist)
- Maintain a `Codex.Tools.Registry` backed by ETS for fast lookup; coordinate with DynamicSupervisor for tool processes.
- Ensure MCP connections run under supervisors with restart strategies matching Python (transient).
- Handle command routing via GenServer to enforce sequential execution per tool instance.

### Subagent Cypher (Test Architect)
- Build unit tests for tool registration, duplicate handling, and deregistration idempotency.
- Create integration tests with fake MCP server abiding by recorded handshake transcripts; leverage Supertester for deterministic scheduling.
- Define contract tests verifying Python vs Elixir tool invocation sequences using golden logs.

## Implementation Tasks
- Implement behaviour `Codex.Tool` specifying `c:invoke/2`, metadata spec, and optional structured schema.
- Create `Codex.MCP.Client` handling handshake, capability negotiation, and message dispatch.
- Provide auto-run support by wiring tool invocations into turn loop with approval checks.

## TDD Entry Points
1. Start with failing test registering tool module and invoking via mock codex event.
2. Add MCP handshake integration test using script that emits handshake events.
3. Implement golden parity test ensuring event order matches Python logs for tool-assisted run.

## Risks & Mitigations
- **Tool process leaks**: add supervision tree tests and assert cleanup after deregistration.
- **MCP protocol drift**: version handshake schemas and pin to codex-rs release; contract tests catch regressions.
- **DSL complexity**: keep macro minimal; provide explicit API alternative.

## Open Questions
- Determine whether Python exposes tool versioning metadata; confirm need for same field.
- Investigate support for streaming tool outputs; gather fixtures before implementation.
