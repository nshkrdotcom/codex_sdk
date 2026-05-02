# Examples

All examples run with `mix run` from the repository root.

## Architecture Note

This SDK contains two distinct subsystems with different authentication:

1. **Codex CLI integration** (`live_*.exs` scripts, `Codex.Thread.*`, `Codex.Exec.*`, `Codex.CLI.*`)
   - Wraps the `codex` CLI via `CliSubprocessCore` command/session lanes
   - Uses `codex login`, native `Codex.OAuth`, `CODEX_API_KEY`, or local OSS via Ollama
   - Shared catalog metadata default: `Codex.Models.default_model()`
   - Live CLI-backed runs do not force that catalog default when model is unset; they defer to the installed `codex` CLI's auth-aware default unless you export `CODEX_MODEL`

2. **OpenAI Agents SDK** (Realtime/Voice modules, ported from `openai-agents-python`)
   - Makes **direct API calls** to OpenAI (WebSocket for Realtime, HTTP for Voice)
   - Uses `Codex.Auth` API key precedence:
     `CODEX_API_KEY` -> `auth.json` `OPENAI_API_KEY` -> `OPENAI_API_KEY`
   - Does NOT use the codex CLI

Both subsystems describe standalone example behavior. Governed Codex runs must
enter through the platform authority path with explicit refs, credential
handles or leases, target grants, and materialized auth. Example env vars,
`auth.json`, local login state, and CLI defaults cannot satisfy governed
authority by themselves.

By default, `./examples/run_all.sh` does not pin a local example model. It lets
the installed `codex` CLI choose its auth-aware default unless you export
`CODEX_MODEL` yourself.
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
./examples/run_all.sh --ssh-host example.internal
./examples/run_all.sh --ssh-host example.internal --cwd /srv/trusted/repo
./examples/run_all.sh --ssh-host example.internal --danger-full-access
./examples/run_all.sh --ssh-host builder@example.internal --ssh-port 2222
```

Run the same CLI-backed example set against local Codex OSS + Ollama:

```bash
./examples/run_all.sh --ollama
./examples/run_all.sh --ollama --ollama-model gpt-oss:20b
./examples/run_all.sh --ollama --ollama-model llama3.2
```

`--ollama` sets:

- `CODEX_PROVIDER_BACKEND=oss`
- `CODEX_OSS_PROVIDER=ollama`
- `CODEX_MODEL=gpt-oss:20b` by default

The runner checks that the requested Ollama model is installed before starting
the examples. In `--ollama` mode, CLI-backed examples use the local OSS route
and do not require `codex login` or `CODEX_API_KEY`.

SSH routing is explicit and flag-driven. When you pass `--ssh-host`, the
CLI/app-server examples switch to `execution_surface: :ssh_exec` while keeping
their existing local default when you omit the flag.

Supported SSH flags for CLI/app-server examples:

- `--cwd <path>`
- `--danger-full-access`
- `--ssh-host <host>` or `--ssh-host <user>@<host>`
- `--ssh-user <user>`
- `--ssh-port <port>`
- `--ssh-identity-file <path>`

Example SSH runs are intentionally noninteractive. The shared execution surface
adds `BatchMode=yes` and `ConnectTimeout=10` so unattended example runs fail
fast instead of hanging on password or connection prompts.

`--cwd` is optional for the exec-backed examples. In SSH mode it becomes
required for app-server thread demos and raw prompt-mode CLI sessions, because
those upstream surfaces do not expose `--skip-git-repo-check`. Point it at a
trusted directory on the remote host when you want those examples to run over
`execution_surface: :ssh_exec`.

`--danger-full-access` keeps the same transport placement and switches only the
Codex runtime sandbox mode to `:danger_full_access`. This is the explicit
example-level escape hatch for remote Linux hosts where sandboxed shell tool
execution fails before the command runs, for example when the host's userns or
AppArmor policy blocks the `bwrap` path that the remote Codex CLI is trying to
use.

`--ssh-host` is mutually exclusive with `--ollama`, because `--ollama` is the
local OSS route and `--ssh-host` is remote subprocess placement.

`./examples/run_all.sh --ssh-host ...` applies only to examples that actually
run through the Codex CLI execution surface. It does not apply to the direct
Realtime/Voice examples, and it intentionally skips
`examples/live_oauth_login.exs` because that example demonstrates local OAuth
session storage and local browser/device login flow rather than subprocess
placement.

In SSH mode, the runner also skips examples that depend on host-local fixtures
or staged local file paths rather than pure subprocess placement. Today that
includes:

- `examples/structured_output.exs`
- `examples/live_app_server_plugins.exs`
- `examples/live_marketplace_management.exs`
- `examples/live_app_server_approvals.exs`
- `examples/live_attachments_and_search.exs`

`gpt-oss:20b` remains the default validated Codex/Ollama example model, but
the runner also accepts other installed Ollama models such as `llama3.2`.
Those non-default models may trigger upstream fallback metadata warnings and
can behave less reliably under the full Codex agent prompt/tool stack.

In `--ollama` mode, the runner:

- executes the full CLI-backed example suite against the local Ollama-backed Codex route
- uses the same config-driven `model_provider="ollama"` / `model="..."` route
  that current upstream Codex expects for exec/app-server local-model startup
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

Default local usage stays unchanged:

```bash
mix run examples/live_cli_demo.exs "What is the capital of France?"
mix run examples/live_app_server_basic.exs "Reply with exactly ok and nothing else."
```

SSH usage for CLI/app-server examples is explicit:

```bash
mix run examples/live_cli_demo.exs -- --ssh-host example.internal "What is the capital of France?"
mix run examples/live_cli_demo.exs -- --ssh-host example.internal --danger-full-access "Run the shell command ls and then say done."
mix run examples/live_app_server_basic.exs -- --ssh-host builder@example.internal --ssh-port 2222 --cwd /srv/trusted/repo "Reply with exactly ok and nothing else."
mix run examples/live_cli_session.exs -- --ssh-host example.internal --cwd /srv/trusted/repo "Summarize this repository in three bullets."
```

- `examples/live_cli_demo.exs` — minimal Q&A against the live CLI
- `examples/live_cli_passthrough.exs` — direct wrappers for `completion`, `features`, `login status`, and arbitrary raw `codex` argv
- `examples/live_cli_session.exs` — PTY-backed root `codex` prompt mode via `Codex.CLI.interactive/2`; in SSH mode, pass `--cwd <remote trusted dir>`
- `examples/live_oauth_login.exs` — native OAuth status/login/refresh demo using an isolated temporary `CODEX_HOME` by default; prints the browser URL before waiting, supports `--browser`, `--device`, and `--no-browser`, and can optionally show memory-mode app-server auth via `--app-server-memory`
- `examples/live_app_server_basic.exs` — minimal turn + skills/models/thread list over `codex app-server`; in SSH mode, pass `--cwd <remote trusted dir>`
- `examples/live_app_server_filesystem.exs` — end-to-end `fs/*` app-server demo (write/read/list/metadata/copy/remove); self-skips when the connected CLI build does not advertise those legacy parity methods
- `examples/plugin_scaffold.exs` — local plugin authoring walkthrough using `Codex.Plugins.scaffold/1`; writes a disposable manifest, optional skill, and marketplace entry under the system temp directory and prints the resulting paths
- `examples/live_app_server_plugins.exs` — provisions a disposable local plugin fixture through `Codex.Plugins.scaffold/1`, launches `codex app-server` with an isolated temporary `CODEX_HOME`, then exercises the typed `plugin_list_typed/2` + `plugin_read_typed/3` wrappers without mutating your real `$CODEX_HOME` or requiring a preinstalled plugin; prints derived `needs_auth` state from typed app summaries and self-skips when the connected CLI build does not advertise `plugin/read`. This example is local-only and does not support `--ssh-host`.
- `examples/live_marketplace_management.exs` — provisions a disposable local marketplace root, then exercises `Codex.CLI.marketplace_add/2` plus the app-server marketplace add/remove/upgrade helpers against isolated temporary `CODEX_HOME` directories so it never mutates your real marketplace state. This example is local-only and does not support `--ssh-host`.
- `examples/live_app_server_streaming.exs` — streamed turn over app-server (prints deltas + completion); in SSH mode, pass `--cwd <remote trusted dir>`
- `examples/live_app_server_dynamic_tools.exs` — streamed app-server turn that advertises an `echo_json` dynamic host tool, responds to `DynamicToolCallRequested` with `Codex.AppServer.respond/3`, and fails if no live dynamic tool call is observed; in SSH mode, pass `--cwd <remote trusted dir>`
- `examples/live_app_server_approvals.exs` — demonstrates command/file approvals, opts into app-server `experimentalApi`, provisions a disposable temp workspace plus temporary `CODEX_HOME`, enables the under-development approval feature flags only inside that isolated home, and prints a structured-grant fallback plus guardian/request-resolution events when live permissions requests still do not appear. This example is local-only and does not support `--ssh-host`.
- `examples/live_app_server_mcp.exs` — lists MCP servers with `detail: :tools_and_auth_only`, prints original vs sanitized qualified tool names, and points at the thread-scoped `resource_read/4` and `tool_call/5` helpers for trusted MCP surfaces
- `examples/live_collaboration_modes.exs` — opts into app-server `experimentalApi`, lists collaboration mode presets, and runs a turn with the server-advertised preset settings plus built-in preset instructions (or skips when the connected CLI build rejects that capability or omits `collaborationMode/list`). In SSH mode, pass `--cwd <remote trusted dir>`.
- `examples/live_subagent_host_controls.exs` — one parent -> one child subagent workflow that explicitly enables the current runtime's `features.multi_agent` flag, sets thread/depth limits, exercises the full `Codex.Subagents` helper surface, and then reuses/resumes the child to drive `spawn_agent`, `send_input`, `resume_agent`, `wait`, and `close_agent` through live parent turns. In SSH mode, pass `--cwd <remote trusted dir>`.
- `examples/live_personality.exs` — compares friendly, pragmatic, and none personality overrides; in SSH mode, pass `--cwd <remote trusted dir>`
- `examples/live_thread_management.exs` — thread read/inject/fork/rollback/memory-mode/loaded list workflows; in SSH mode, pass `--cwd <remote trusted dir>`
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
- `examples/live_attachments_and_search.exs` — stages attachments, returns structured file outputs, and runs hosted file_search. This example is local-only and does not support `--ssh-host`.
- `examples/live_config_overrides.exs` — nested config override auto-flattening plus layered `openai_base_url` / `model_providers` parity
- `examples/live_options_config_overrides.exs` — options-level global config overrides, precedence, runtime validation, and reserved-provider notes
- `examples/live_parity_and_status.exs` — quick pointers to parity docs/fixtures and CLI availability

`examples/live_oauth_login.exs` remains local-only for its primary flow. The
OAuth session storage, browser launch, and device-code UX are local host
concerns, not `execution_surface` concerns, so `--ssh-host` is not documented
for that script.

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
## Recovery-Oriented Examples

For the emergency hardening lane, the most relevant examples are:

- `examples/conversation_and_resume.exs`
- `examples/live_session_walkthrough.exs`
- `examples/live_mcp_and_sessions.exs`

Those examples exercise the same persisted-thread surfaces that now back the standardized
`list_provider_sessions/1` runtime projection used by upper orchestration layers.
