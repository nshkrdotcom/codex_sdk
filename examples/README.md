# Examples

All examples run with `mix run` from the repository root.

## Architecture Note

This SDK contains two distinct subsystems with different authentication:

1. **Codex CLI integration** (`live_*.exs` scripts, `Codex.exec/2`, `Codex.run/2`)
   - Wraps the `codex` CLI via erlexec subprocess
   - Uses `codex login` authentication (no separate API key needed)
   - SDK default model: `gpt-5.3-codex`

2. **OpenAI Agents SDK** (Realtime/Voice modules, ported from `openai-agents-python`)
   - Makes **direct API calls** to OpenAI (WebSocket for Realtime, HTTP for Voice)
   - Requires `OPENAI_API_KEY` environment variable
   - Does NOT use the codex CLI

By default, `./examples/run_all.sh` pins `CODEX_MODEL=gpt-5.3-codex` (override by exporting `CODEX_MODEL` before running). A few live scripts also explicitly set `model: "gpt-5.3-codex"`; edit those examples if you need a different model.

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

## Notable Codex CLI Examples (uses `codex login` auth)

The `live_*.exs` scripts hit the live Codex CLI (no OPENAI_API_KEY needed if you are authenticated via `codex login`).

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

## Realtime Voice Examples (OpenAI Agents SDK - requires OPENAI_API_KEY)

These examples use the OpenAI Realtime API directly (not via Codex CLI). They demonstrate real-time bidirectional voice interactions:

- `examples/live_realtime_voice.exs` — full realtime voice interaction demo with real audio I/O
- `examples/realtime_basic.exs` — basic realtime session setup with real audio input
- `examples/realtime_tools.exs` — using function tools with realtime agents
- `examples/realtime_handoffs.exs` — agent-to-agent handoffs in realtime sessions

### Audio Format

All realtime examples use real audio:
- **Input**: `test/fixtures/audio/voice_sample.wav` (24kHz, 16-bit PCM, mono)
- **Output**: Saved to `/tmp/codex_realtime_*.pcm` (24kHz, 16-bit PCM, mono)

### Prerequisites for Realtime Examples

```bash
export OPENAI_API_KEY=your-key-here
mix run examples/realtime_basic.exs

# Play the output audio:
aplay -f S16_LE -r 24000 -c 1 /tmp/codex_realtime_basic.pcm

# Or convert to WAV:
sox -t raw -r 24000 -b 16 -c 1 -e signed-integer /tmp/codex_realtime_basic.pcm /tmp/response.wav
```

## Voice Pipeline Examples (OpenAI Agents SDK - requires OPENAI_API_KEY)

These examples use OpenAI's STT/TTS APIs directly (not via Codex CLI). They demonstrate the voice pipeline (STT → Workflow → TTS):

- `examples/voice_pipeline.exs` — basic STT -> Workflow -> TTS pipeline with real audio
- `examples/voice_multi_turn.exs` — multi-turn conversations with streamed audio input
- `examples/voice_with_agent.exs` — using Codex Agents with voice pipelines

### Audio Format

All voice pipeline examples use real audio:
- **Input**: `test/fixtures/audio/voice_sample.wav` (24kHz, 16-bit PCM, mono)
- **Output**: Saved to `/tmp/codex_voice_*.pcm` (24kHz, 16-bit PCM, mono)

### Prerequisites for Voice Pipeline Examples

```bash
export OPENAI_API_KEY=your-key-here
mix run examples/voice_pipeline.exs

# Play the output audio:
aplay -f S16_LE -r 24000 -c 1 /tmp/codex_voice_response.pcm

# Or convert to WAV:
sox -t raw -r 24000 -b 16 -c 1 -e signed-integer /tmp/codex_voice_response.pcm /tmp/response.wav
```

### Audio Test Fixture

The audio fixture `test/fixtures/audio/voice_sample.wav` is sourced from Google's genai Python SDK (Apache 2.0 license). It contains ~2 seconds of speech at 24kHz, matching OpenAI's native audio format.
