# Examples

All examples run with `mix run` from the repository root. The `live_*.exs` scripts hit the live Codex CLI (no mocks, no extra API-key setup required if you are already logged in).

By default, `./examples/run_all.sh` pins `CODEX_MODEL=gpt-5.1-codex-mini` for consistent runs (override by exporting `CODEX_MODEL` before running). Auth-aware defaults are `gpt-5.2-codex` for ChatGPT login and `gpt-5.1-codex-max` for API keys. A few live scripts explicitly set `model: "gpt-5.2-codex"` to avoid mini limitations (for example, higher reasoning-effort requests); edit those examples if you need a different model.

## Running everything

```bash
./examples/run_all.sh
```

## Live ExUnit tests

The repo ships an opt-in `:live` ExUnit suite that hits the real `codex` CLI:

```bash
CODEX_TEST_LIVE=true mix test --only live --include live
# Or run the entire suite plus the live tests:
CODEX_TEST_LIVE=true mix test --include live
```

Prereqs:
- `codex` installed and on PATH (or set `CODEX_PATH`)
- authenticated via `codex login` or `CODEX_API_KEY`

## Notable live examples

- `examples/live_cli_demo.exs` — minimal Q&A against the live CLI
- `examples/live_app_server_basic.exs` — minimal turn + skills/models/thread list over `codex app-server`
- `examples/live_app_server_streaming.exs` — streamed turn over app-server (prints deltas + completion)
- `examples/live_app_server_approvals.exs` — demonstrates manual responses to app-server approval requests
- `examples/live_app_server_mcp.exs` — lists MCP servers via `Codex.AppServer.Mcp.list_servers/2` (uses `mcpServerStatus/list` with fallback)
- `examples/live_collaboration_modes.exs` — lists collaboration mode presets and runs a turn with a preset
- `examples/live_personality.exs` — compares friendly vs pragmatic personality overrides
- `examples/live_thread_management.exs` — thread read/fork/rollback/loaded list workflows
- `examples/live_web_search_modes.exs` — runs turns with `web_search_mode` toggles and reports web search items
- `examples/live_rate_limits.exs` — prints rate limit snapshots from token usage/account updates
- `examples/live_session_walkthrough.exs` — multi-turn session with follow-ups and labels
- `examples/live_exec_controls.exs` — demonstrates cancellation/controls on streaming turns
- `examples/live_tooling_stream.exs` — streams tool calls and approvals
- `examples/live_telemetry_stream.exs` — emits telemetry events during streaming
- `examples/live_usage_and_compaction.exs` — shows live usage accumulation
- `examples/live_multi_turn_runner.exs` — multi-turn runner with tool_use_behavior, max_turns, and usage summary
- `examples/live_tooling_guardrails_approvals.exs` — guardrail events, handoffs, and approval hook demos
- `examples/live_structured_hosted_tools.exs` — structured function tool outputs plus hosted shell/apply_patch/computer/file_search/image
- `examples/live_mcp_and_sessions.exs` — hosted MCP stub with retries/filters and a resumable session flow
- `examples/live_model_streaming_tracing.exs` — model/model_settings override with streaming, cancel modes, and tracing metadata
- `examples/live_attachments_and_search.exs` — stages attachments, returns structured file outputs, and runs hosted file_search
- `examples/live_parity_and_status.exs` — quick pointers to parity docs/fixtures and CLI availability
- `examples/live_realtime_voice.exs` — full realtime voice interaction demo

## Realtime Voice Examples

These examples demonstrate the OpenAI Realtime API integration for real-time voice interactions:

- `examples/live_realtime_voice.exs` — full realtime voice interaction demo with event handling
- `examples/realtime_basic.exs` — basic realtime session setup with configuration
- `examples/realtime_tools.exs` — using function tools with realtime agents
- `examples/realtime_handoffs.exs` — agent-to-agent handoffs in realtime sessions

### Prerequisites for Realtime Examples

```bash
export OPENAI_API_KEY=your-key-here
mix run examples/realtime_basic.exs
```

For realtime examples with actual audio, you'll need audio capture/playback capabilities.

## Voice Pipeline Examples

These examples demonstrate the non-realtime voice pipeline (STT -> Workflow -> TTS):

- `examples/voice_pipeline.exs` — basic STT -> Workflow -> TTS pipeline
- `examples/voice_multi_turn.exs` — multi-turn conversations with streaming input
- `examples/voice_with_agent.exs` — using Codex Agents with voice pipelines

### Prerequisites for Voice Pipeline Examples

```bash
export OPENAI_API_KEY=your-key-here
mix run examples/voice_pipeline.exs
```
