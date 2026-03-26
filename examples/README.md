# Examples

All examples run with `mix run` from the repository root.

## Architecture Note

This SDK contains two distinct subsystems with different authentication:

1. **Codex CLI integration** (`live_*.exs` scripts, `Codex.Thread.*`, `Codex.Exec.*`, `Codex.CLI.*`)
   - Wraps the `codex` CLI via `CliSubprocessCore` command/session lanes
   - Uses `codex login`, native `Codex.OAuth`, `CODEX_API_KEY`, or local OSS via Ollama
   - SDK default model: `Codex.Models.default_model()` from the shared `cli_subprocess_core` catalog

2. **OpenAI Agents SDK** (Realtime/Voice modules, ported from `openai-agents-python`)
   - Makes **direct API calls** to OpenAI (WebSocket for Realtime, HTTP for Voice)
   - Uses `Codex.Auth` API key precedence:
     `CODEX_API_KEY` -> `auth.json` `OPENAI_API_KEY` -> `OPENAI_API_KEY`
   - Does NOT use the codex CLI

By default, `./examples/run_all.sh` does not pin a local example model. It uses
the shared `CliSubprocessCore.ModelRegistry` default through
`Codex.Models.default_model()`, unless you export `CODEX_MODEL` yourself.
Examples that start Codex turns no longer force a global `:low` reasoning
effort. They rely on the selected model's shared core default unless a live
collaboration-mode preset explicitly advertises a different value.
The runner executes CLI-backed examples first, then runs realtime/voice examples only when a direct API key is available (`CODEX_API_KEY`, `OPENAI_API_KEY`, or `auth.json` `OPENAI_API_KEY`).

For TLS interception or private roots, set `CODEX_CA_CERTIFICATE` first and `SSL_CERT_FILE`
second. Direct HTTP/WebSocket examples mention this in comments, and the same trust root also
applies to Codex CLI subprocesses and MCP HTTP/OAuth flows.

## Running everything

```bash
./examples/run_all.sh
```

Run the same CLI-backed example set against local Codex OSS + Ollama:

```bash
./examples/run_all.sh --ollama
./examples/run_all.sh --ollama --ollama-model llama3.2
```

`--ollama` sets:

- `CODEX_PROVIDER_BACKEND=oss`
- `CODEX_OSS_PROVIDER=ollama`
- `CODEX_MODEL=llama3.2` by default

The runner checks that the requested Ollama model is installed before starting
the examples.

In `--ollama` mode, the runner:

- executes the full CLI-backed example suite against the local Ollama-backed Codex route
- keeps app-server examples enabled by configuring `codex app-server` with supported
  `--config` overrides instead of unsupported OSS argv flags
- uses deterministic local fallbacks where upstream features are not reliable on the
  local OSS path (for example strict structured-output assertions or live web-search
  event enforcement)
- skips the direct OpenAI realtime/voice examples, because those examples are not
  Ollama-backed and use a separate direct API subsystem

If direct API credentials are missing, realtime/voice examples are reported as `SKIPPED` and do not fail the run.
If credentials exist but direct API access is unavailable (for example `insufficient_quota`, missing realtime model access, or an upstream Realtime `server_error`), direct API examples print `SKIPPED: <reason>`. Realtime demos now run a minimal raw-WebSocket health probe first and include the upstream `session_id` in the skip reason when OpenAI fails before any example-specific logic.
The native OAuth example also self-skips in runner contexts unless you point it
at an existing `CODEX_OAUTH_EXAMPLE_HOME` or opt into `--interactive`.

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
- `examples/live_cli_passthrough.exs` — direct wrappers for `completion`, `features`, `login status`, and arbitrary raw `codex` argv
- `examples/live_cli_session.exs` — PTY-backed root `codex` prompt mode via `Codex.CLI.interactive/2`
- `examples/live_oauth_login.exs` — native OAuth status/login/refresh demo using an isolated temporary `CODEX_HOME` by default; prints the browser URL before waiting, supports `--browser`, `--device`, and `--no-browser`, and can optionally show memory-mode app-server auth via `--app-server-memory`
- `examples/live_app_server_basic.exs` — minimal turn + skills/models/thread list over `codex app-server`
- `examples/live_app_server_filesystem.exs` — end-to-end `fs/*` app-server demo (write/read/list/metadata/copy/remove); self-skips when the connected CLI build does not advertise those legacy parity methods
- `examples/live_app_server_plugins.exs` — provisions a disposable local marketplace under the system temp directory, launches `codex app-server` with an isolated temporary `CODEX_HOME`, then exercises `plugin/list` + `plugin/read` without mutating your real `$CODEX_HOME` or requiring a preinstalled plugin; prints `needsAuth` when available and self-skips when the connected CLI build does not advertise `plugin/read`
- `examples/live_app_server_streaming.exs` — streamed turn over app-server (prints deltas + completion)
- `examples/live_app_server_approvals.exs` — demonstrates command/file approvals, opts into app-server `experimentalApi`, provisions a disposable temp workspace plus temporary `CODEX_HOME`, enables the under-development approval feature flags only inside that isolated home, and prints a structured-grant fallback plus guardian/request-resolution events when live permissions requests still do not appear
- `examples/live_app_server_mcp.exs` — lists MCP servers and prints original vs sanitized qualified tool names
- `examples/live_collaboration_modes.exs` — opts into app-server `experimentalApi`, lists collaboration mode presets, and runs a turn with the server-advertised preset settings plus built-in preset instructions (or skips when the connected CLI build rejects that capability or omits `collaborationMode/list`)
- `examples/live_subagent_host_controls.exs` — one parent -> one child subagent workflow that explicitly enables the current runtime's `features.multi_agent` flag, sets thread/depth limits, exercises the full `Codex.Subagents` helper surface, and then reuses/resumes the child to drive `spawn_agent`, `send_input`, `resume_agent`, `wait`, and `close_agent` through live parent turns
- `examples/live_personality.exs` — compares friendly, pragmatic, and none personality overrides
- `examples/live_thread_management.exs` — thread read/fork/rollback/loaded list workflows
- `examples/live_web_search_modes.exs` — demonstrates `web_search_mode` toggles, validates disabled/live behavior, and reports cached-mode search events when available
- `examples/live_rate_limits.exs` — prints rate limit snapshots from token usage/account updates
- `examples/live_session_walkthrough.exs` — multi-turn session with follow-ups and labels
- `examples/live_exec_controls.exs` — demonstrates cancellation/controls on streaming turns
- `examples/live_tooling_stream.exs` — streams tool calls and approvals
- `examples/live_telemetry_stream.exs` — emits telemetry events during streaming
- `examples/live_usage_and_compaction.exs` — shows live usage accumulation
- `examples/live_multi_turn_runner.exs` — multi-turn runner with tool_use_behavior, max_turns, and usage summary
- `examples/live_tooling_guardrails_approvals.exs` — guardrail events, handoffs, and approval hook demos
- `examples/live_structured_hosted_tools.exs` — structured function tool outputs plus hosted shell/apply_patch/computer/file_search/image
- `examples/live_mcp_and_sessions.exs` — hosted MCP stub with retries/filters, sanitized qualified names, and a resumable session flow
- `examples/live_model_streaming_tracing.exs` — model/model_settings override with streaming, cancel modes, and tracing metadata
- `examples/live_attachments_and_search.exs` — stages attachments, returns structured file outputs, and runs hosted file_search
- `examples/live_config_overrides.exs` — nested config override auto-flattening plus layered `openai_base_url` / `model_providers` parity
- `examples/live_options_config_overrides.exs` — options-level global config overrides, precedence, runtime validation, and reserved-provider notes
- `examples/live_parity_and_status.exs` — quick pointers to parity docs/fixtures and CLI availability

## Realtime Voice Examples (OpenAI Agents SDK)

These examples use the OpenAI Realtime API directly (not via Codex CLI). They demonstrate real-time bidirectional voice interactions:

`./examples/run_all.sh --ollama` skips this entire section on purpose. Those examples are
OpenAI-only and do not participate in the local Codex OSS + Ollama route.

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
# One of:
export CODEX_API_KEY=your-key-here
# or export OPENAI_API_KEY=your-key-here
# or populate auth.json OPENAI_API_KEY under CODEX_HOME
mix run examples/realtime_basic.exs

# Play the output audio:
aplay -f S16_LE -r 24000 -c 1 /tmp/codex_realtime_basic.pcm

# Or convert to WAV:
sox -t raw -r 24000 -b 16 -c 1 -e signed-integer /tmp/codex_realtime_basic.pcm /tmp/response.wav
```

## Voice Pipeline Examples (OpenAI Agents SDK)

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
# One of:
export CODEX_API_KEY=your-key-here
# or export OPENAI_API_KEY=your-key-here
# or populate auth.json OPENAI_API_KEY under CODEX_HOME
mix run examples/voice_pipeline.exs

# Play the output audio:
aplay -f S16_LE -r 24000 -c 1 /tmp/codex_voice_response.pcm

# Or convert to WAV:
sox -t raw -r 24000 -b 16 -c 1 -e signed-integer /tmp/codex_voice_response.pcm /tmp/response.wav
```

### Audio Test Fixture

The audio fixture `test/fixtures/audio/voice_sample.wav` is sourced from Google's genai Python SDK (Apache 2.0 license). It contains ~2 seconds of speech at 24kHz, matching OpenAI's native audio format.
