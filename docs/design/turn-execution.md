# Turn Execution Design

## Feature Summary
- Implement blocking (`run/3`) and streaming (`run_streamed/3`) turn execution mirroring Python client semantics.
- Support auto-run loops with configurable retry policies and tool invocation bridging.
- Return structured `Codex.Turn.Result` including final response, usage metrics, and collected events.

## Subagent Perspectives
### Subagent Astra (API Strategist)
- Maintain simple API signatures: `run(thread, input, opts \\ [])` returning `{:ok, TurnResult.t()} | {:error, term()}`.
- For streaming, return cold `Enumerable` that yields typed event structs; integrate with Elixir `Stream` API.
- Expose auto-run via `Codex.Thread.run_auto/3` with optional callbacks mirroring Python's `on_event`.

### Subagent Borealis (Concurrency Specialist)
- Ensure each turn starts a dedicated `Codex.Exec` process supervised under a dynamic supervisor.
- Use `GenServer.multi_call` or monitor references to allow early cancellation and clean shutdown.
- Manage backpressure in streaming runs using `GenStage`-style mailbox checks or flow control tokens from codex-rs.

### Subagent Cypher (Test Architect)
- Derive golden event sequences from Python transcripts; assert event ordering, final response extraction, and usage aggregation.
- Write property tests verifying streaming enumerables do not execute until consumed and respect manual halt.
- Simulate failure modes (port crash, malformed JSON) with fake binaries to ensure graceful error propagation.

## Implementation Tasks
- Define `%Codex.Turn{}` and `%Codex.Turn.Result{}` structs with `@enforce_keys`.
- Implement run pipeline: option prep → Exec start → event collection → finalize result → teardown.
- Build streaming layer using `Stream.resource/3`, ensuring cleanup in `after_fun`.
- Add auto-run loop coordinating retries, tool handling, and stop conditions.

## TDD Entry Points
1. Write failing integration test that executes recorded blocking turn fixture and asserts final response and usage.
2. Add streaming test verifying first event is not consumed until enumerated.
3. Introduce red test for auto-run loop using fixture with retryable tool call.

## Risks & Mitigations
- **Resource leaks**: guard with monitors and `try ... after` blocks; add tests that assert process counts remain stable.
- **Backpressure issues**: throttle message sends and document expectations for consumer speed.
- **Auto-run divergence**: log and expose step-by-step events to match Python debug output.

## Open Questions
- Should auto-run expose a callback interface or rely on instrumentation hooks? Await product feedback.
- Confirm whether Python handles partial successes differently when tools fail—need fixtures.
