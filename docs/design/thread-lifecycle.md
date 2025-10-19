# Thread Lifecycle Design

## Feature Summary
- Provide Elixir APIs (`Codex.start_thread/2`, `Codex.resume_thread/3`) that mirror the Python client's thread lifecycle semantics.
- Preserve thread metadata (IDs, continuation tokens, default options) and guarantee compatibility with existing fixtures and golden transcripts.
- Ensure thread construction remains stateless and side-effect free until a turn is executed.

## Subagent Perspectives
### Subagent Astra (API Strategist)
- Align function signatures with idiomatic Elixir while retaining Python parity (`start_thread(options)`, `resume_thread(thread_id, options)`).
- Introduce `%Codex.Thread{}` struct with explicit fields: `thread_id`, `codex_opts`, `thread_opts`, `metadata`, `labels`.
- Support keyword and map inputs by funneling through `Codex.Options.new/1` and `Codex.Thread.Options.new/1`.
- Document usage with doctests that mirror Python README examples for starting and resuming sessions.

### Subagent Borealis (Concurrency Specialist)
- Keep thread factories pure; avoid GenServer interactions inside `start_*` to maintain fast, deterministic construction.
- Ensure resumed threads validate continuation tokens synchronously and emit telemetry on mismatch.
- Plan for thread struct immutability—mutating per-turn overrides should clone structs to avoid shared state hazards.

### Subagent Cypher (Test Architect)
- Author unit tests for option coercion and struct validation, including malformed thread IDs and missing API keys.
- Add characterization tests comparing Python-generated thread metadata JSON with Elixir serialization.
- Create integration test harness that resumes a thread using recorded fixtures to verify continuity of run IDs.

## Implementation Tasks
- Build option constructors with guard clauses and meaningful error tuples.
- Implement metadata hydration (`Codex.Thread.Metadata.from_json/1`) using typed structs.
- Wire resume validation to call lightweight Python parity fixture until codex-rs addition arrives.

## TDD Entry Points
1. Write failing doctest for `Codex.start_thread/1` returning `%Codex.Thread{thread_id: nil}`.
2. Add ExUnit case asserting resumed thread populates metadata from fixture.
3. Implement code to satisfy tests, then refactor struct modules into dedicated namespace.

## Risks & Mitigations
- **Mismatch with Python metadata**: lock fixture schema and add contract test; fail fast on unexpected keys.
- **State mutation bugs**: enforce `%Codex.Thread{}` as `@enforce_keys`; use `put_in/2` copies for updates.

## Open Questions
- Should thread labels and metadata be stored as `map()` or keyword list? Await parity confirmation from Python audit.
- How do we expose continuation tokens to callers? Decide whether to surface in struct or keep private.
