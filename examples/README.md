# Examples

All examples run with `mix run` from the repository root. The `live_*.exs` scripts hit the live Codex CLI (no mocks, no extra API-key setup required if you are already logged in).

## Running everything

```bash
./examples/run_all.sh
```

## Notable live examples

- `examples/live_cli_demo.exs` — minimal Q&A against the live CLI
- `examples/live_session_walkthrough.exs` — multi-turn session with follow-ups and labels
- `examples/live_exec_controls.exs` — demonstrates cancellation/controls on streaming turns
- `examples/live_tooling_stream.exs` — streams tool calls and approvals
- `examples/live_telemetry_stream.exs` — emits telemetry events during streaming
- `examples/live_usage_and_compaction.exs` — shows live usage accumulation
