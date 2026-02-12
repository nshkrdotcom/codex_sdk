# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- Realtime `tool_choice` serialization for `{:function, name}` now emits `%{"type" => "function", "name" => name}` for `session.update` compatibility.
- Realtime and voice live examples now self-report API skip reasons (`insufficient_quota`, `realtime_model_unavailable`) and exit cleanly instead of misreporting success.
- App-server approvals demo now uses a prompt that exercises approvals more reliably and waits briefly for trailing audit messages before summarizing.
- Tool-bridging and rate-limit examples now print explicit runtime notes when transport/rate-limit data is absent so empty output is not mistaken for SDK failure.

### Fixed

- Realtime now surfaces `response.done` failed status payloads as `%Codex.Realtime.Events.ErrorEvent{}` (including failures received via raw server events), enabling deterministic skip/error handling in examples.
- Realtime handoff demo now uses deterministic function tool choice and correctly skips when realtime model access is unavailable.
- Voice TTS streaming now fails fast on non-success HTTP statuses and stream transport errors instead of silently yielding empty/invalid audio chunks.
- Voice multi-turn example now performs a preflight TTS quota check and skips on quota failures rather than timing out.
- Attachments demo now stages a known-good minimal PNG payload to avoid corruption/decoder drift in downstream tooling.

## [0.9.1] - 2026-02-11

### Added

- `Codex.Exec.CancellationRegistry`, a supervised cancellation-token registry that owns the backing ETS table and manages token-to-transport mappings safely across processes.

### Changed

- `Codex.Exec` cancellation token lifecycle now routes through `Codex.Exec.CancellationRegistry` instead of direct multi-process writes to a lazily-created ETS table.

### Fixed

- Eliminated intermittent ETS access-rights crashes in thread stream/property flows during cancellation and cleanup paths.
- Added regression coverage for cancellation registry registration, selective unregister behavior, and dead-process pruning.


## [0.9.0] - 2026-02-11

### Added

- **`Codex.Config.Defaults` module** — single source of truth for every tunable SDK constant (timeouts, buffer sizes, URLs, protocol versions, model names, audio parameters, telemetry IDs, and more). All values are exposed as zero-arity functions; a subset supports runtime override via `Application.get_env/3`.

- **New documentation guides**:
  - `guides/07-models-and-reasoning.md` — model selection, reasoning-effort levels, automatic coercion, and configuration layers
  - `guides/08-configuration-defaults.md` — full reference table of `Codex.Config.Defaults` tunables with runtime override instructions

- **`Codex.Realtime.Agent.default_model/0`** — public accessor for the default realtime model name, replacing hardcoded `"gpt-4o-realtime-preview"` strings.

- **`Codex.Test.ModelFixtures`** — test support module providing canonical model constants (`default_model/0`, `alt_model/0`, `max_model/0`, `realtime_model/0`, `stt_model/0`, `tts_model/0`) so tests stay in sync when defaults change upstream.

- **`Codex.Exec` ThreadStarted metadata enrichment** — `ThreadStarted` events from the exec transport are now enriched with the effective `model`, `reasoning_effort`, and `config.model_reasoning_effort` from the active `Codex.Options`, filling in values the CLI may omit.

- **`Codex.Config.Defaults` test suite** (`test/codex/config/defaults_test.exs`) — 420-line test covering every default value and all runtime-overridable keys.

### Changed

- **Centralized all magic numbers and string literals into `Codex.Config.Defaults`** — 30+ modules now reference `Defaults.*()` instead of inline constants:
  - Transport timeouts and buffer sizes (`Codex.Exec`, `Codex.IO.Transport.Erlexec`)
  - MCP protocol constants and timeouts (`Codex.MCP.Client`, `Codex.MCP.Transport.StreamableHTTP`)
  - App-server timeouts (`Codex.AppServer`, Codex.AppServer.Connection, Codex.AppServer.Approvals, `Codex.AppServer.Mcp`)
  - OAuth/HTTP timeouts (`Codex.MCP.OAuth`)
  - Retry/backoff parameters (`Codex.Retry`, Codex.Thread.Backoff, `Codex.RateLimit`)
  - Tool defaults (`Codex.Tools.ShellTool`, `Codex.Tools.ShellCommandTool`, `Codex.Tools.FileSearchTool`, `Codex.Tools.WebSearchTool`)
  - Audio format constants (`Codex.Realtime.Audio`)
  - Voice/TTS/STT defaults (`Codex.Voice.Config.TTSSettings`, `Codex.Voice.Input`, `Codex.Voice.Models.OpenAISTT`, `Codex.Voice.Models.OpenAITTS`, `Codex.Voice.Models.OpenAIProvider`)
  - URL defaults (`Codex.Config.BaseURL`, `Codex.Realtime.Config.ModelConfig`)
  - Session/file defaults (`Codex.Sessions`, `Codex.Files`, `Codex.Files.Registry`)
  - Stream/run config (Codex.StreamQueue, `Codex.RunResultStreaming`, `Codex.RunConfig`)
  - Telemetry constants (`Codex.Telemetry`)
  - Config layer stack (Codex.Config.LayerStack)
  - Thread options (`Codex.Thread.Options`)

- **Refactored `Codex.Models` presets** — model definitions now use shared reasoning-effort templates (`@efforts_full`, `@efforts_mini`, `@efforts_standard`, `@efforts_frontier`, `@efforts_gpt5`) and derive `model`/`display_name` from `id` via compile-time `Enum.map`, eliminating ~50 lines of duplication. Shell type map is now derived from presets rather than maintained separately.

- **`Codex.Voice.Models.OpenAIProvider`** now delegates default model names to `OpenAISTT.model_name/0` and `OpenAITTS.model_name/0` instead of duplicating strings.

- **Codex.Realtime.Session.get_model_name/1** now calls `RealtimeAgent.default_model/0` instead of hardcoding `"gpt-4o-realtime-preview"`.

- **Examples updated** to use `Codex.Models.default_model()` and `Codex.Realtime.Agent.default_model()` instead of hardcoded model strings (`conversation_and_resume.exs`, `live_mcp_and_sessions.exs`, `live_realtime_voice.exs`, `live_session_walkthrough.exs`).

- **Tests updated** to use `Codex.Test.ModelFixtures` imports instead of hardcoded model strings across `exec_test.exs`, `models_test.exs`, `options_test.exs`, `thread_test.exs`, `agent_test.exs`, `realtime_integration_test.exs`, and all voice model tests.

- ExDocs now includes a **Configuration** group listing `Codex.Config.Defaults`, `Codex.Config.BaseURL`, `Codex.Config.Overrides`, and `Codex.Config.OptionNormalizers`; `Codex.Models` is added to the Core group.

### Fixed

- Realtime sessions no longer emit duplicate `%Codex.Realtime.Events.AgentStartEvent{}` on initial connect. `AgentStartEvent` is now emitted on `TurnStartedEvent` only (while `session.update` is still sent on connection), and session tests now include regression coverage for the connect-plus-turn sequence.

## [0.8.0] - 2026-02-10

### Added

- **Realtime handoff execution** in `Codex.Realtime.Session`:
  - Handoff tool schema generation — agent `handoffs` list is automatically converted to `transfer_to_*` function tools in the `session.update` payload
  - `handle_handoff_tool_call/3` switches `state.agent`, sends new `session.update` config, and emits `%Events.HandoffEvent{}`
  - `resolve_handoff_target/4` supports `Codex.Handoff` structs (with `agent`, `on_invoke_handoff`, `input_schema`), `Codex.Realtime.Agent` structs, and plain maps
  - `get_agent_tools/1` merges regular tools and handoff tools; `find_tool/2` matches `%Handoff{tool_name: name}`

- **Codex.IO.Transport behaviour** with 10 callbacks (`start/1`, `start_link/1`, `send/2`, `end_input/1`, `subscribe/2,3`, `close/1`, `force_close/1`, `status/1`, `stderr/1`) providing a unified I/O transport layer

- **Codex.IO.Transport.Erlexec GenServer** implementation:
  - Task-isolated `safe_call/3` via `TaskSupervisor.async_nolink` with timeout and noproc/death handling
  - Async `send`/`end_input` via IO tasks tracked in `pending_calls` map
  - Tagged subscriber dispatch (`{:codex_io_transport, ref, event}`) and legacy dispatch
  - Queue-based stdout drain with `@max_lines_per_batch 200` and `:drain_stdout` backpressure control
  - Buffer overflow protection with overflow recovery at next newline
  - Deferred finalize exit with 25ms delay for late stdout arrival
  - Headless timeout auto-shutdown when no subscribers attach
  - Bounded stderr buffer with tail-truncation at `max_stderr_buffer_size`
  - `force_close/1` with `:exec.stop` + `:exec.kill(pid, 9)` escalation

- **Codex.IO.Buffer** — shared line-splitting and JSON-line decoding extracted from triplicated code:
  - `split_lines/1`, `decode_json_lines/2`, `decode_complete_lines/1`, `decode_line/1`, `iodata_to_binary/1`
  - Replaces identical `split_lines/1` copies in Exec, AppServer.Protocol, and MCP.Protocol

- **Codex.TaskSupport** — async task helper with automatic `Codex.TaskSupervisor` noproc retry and `Application.ensure_all_started` fallback
  - `async_nolink/1,2` extracted from IO.Transport.Erlexec

- `Codex.TaskSupervisor` added to application supervision tree

- **Voice TTS `:client` injection** — Added configurable `:client` option to `OpenAITTS.new/2` for request client injection (testability)

### Changed

- **Codex.Exec migrated to IO.Transport.Erlexec**:
  - Replaced `start_process/2` direct `:exec.run` with `IO.Transport.Erlexec.start_link` using tagged subscription ref
  - Replaced `do_collect/3` and `next_stream_chunk/1` raw `{:stdout, os_pid, chunk}` receive with tagged `{:codex_io_transport, ref, {:message, line}}` events
  - Replaced direct `:exec.stop` in `safe_stop/1` with monitor-based shutdown cascade via IO.Transport
  - Removed `pid`, `os_pid`, `buffer` from internal state; changed `stderr` from list to string; added `transport` and `transport_ref`
  - Deleted `ensure_erlexec_started/0`, `maybe_put_env/2`, `iodata_to_binary/1`, `merge_stderr/1`, and remaining `split_lines`

- **AppServer.Connection migrated to IO.Transport.Erlexec**:
  - Removed `subprocess_mod`, `subprocess_opts`, `subprocess_pid`, `os_pid`, `stdout_buffer` from State; added `transport_mod`, `transport`, and `transport_ref`
  - Replaced raw erlexec message handlers with tagged transport events
  - Deleted `resolve_subprocess_module/1`, `resolve_subprocess_opts/1`, `ensure_erlexec_started/1`, `start_opts/1`

- **MCP.Transport.Stdio migrated to IO.Transport.Erlexec** (same pattern as Connection)

- **Transport lifecycle hardening** (Codex.Exec):
  - `safe_stop/1` now uses monitor-based graceful shutdown escalation: `force_close` → `Process.exit(:shutdown)` → `Process.exit(:kill)` with configurable grace periods (2s / 250ms / 250ms)
  - Added `flush_transport_messages/1` to drain tagged events after shutdown
  - Simplified `send_prompt/2` from with-chain to case-chain
  - Extracted `decode_event_map/1` with function-level rescue (was inline `try`/`rescue` in `decode_line`)

- **Transport module dispatch** (Connection, MCP.Transport.Stdio):
  - Added `transport_mod` field to State structs for dynamic transport dispatch
  - Added guard clauses to `send_iolist/2` and `stop_subprocess/1` for disconnected transport safety
  - Connection: refactored `resolve_transport/1` into `normalize_transport_option/2` and `normalize_transport_value/2` clause chain

- IO.Transport.Erlexec `init/1` simplified from with-chain to case expression
- `normalize_payload/1` split: lists try `IO.iodata_to_binary` first, falling back to `Jason.encode!` on `ArgumentError`; added map-specific clause
- `Config.merge_settings` tool serialization refactored into `serialize_tool/1` to handle non-struct tools

- Rewired Exec, AppServer.Protocol, and MCP.Protocol to delegate line-splitting/decoding to `Codex.IO.Buffer`

- **Example hardening** (all realtime examples):
  - Added `main/0` entry points with `:ok` / `{:skip, reason}` / `{:error, reason}` return pattern
  - `insufficient_quota` detection and graceful `SKIPPED:` output instead of `System.halt(1)`
  - `safe_close/1` with rescue in all session teardown paths
  - Stats/audit collection replacing raw event printing in `realtime_basic.exs`, `live_realtime_voice.exs`, and `live_app_server_approvals.exs`
  - `Realtime.send_audio/3` calls updated with `commit: true` on final chunk
  - Voice example (`voice_multi_turn.exs`): replaced `Task.await(output_task, :infinity)` with `Task.yield/2` + `Task.shutdown/2` using 60s timeout

- **Voice TTS `instructions` field** — `maybe_add_instructions/2` now puts `instructions` as a top-level request body field instead of nesting under `extra_body`

- Updated README, getting-started guide, API guide, examples guide, and realtime-and-voice guide to reflect new handoff patterns

### Removed

- Deleted `lib/codex/app_server/subprocess.ex` and `lib/codex/app_server/subprocess/erlexec.ex` (superseded by IO.Transport)
- Deleted triplicated `split_lines/1`, `decode_lines`, `decode_line` private functions from Exec, AppServer.Protocol, and MCP.Protocol

### Fixed

- `Config.merge_settings` now preserves explicit falsy override values (was using `||` which dropped `false`; changed to `if is_nil(override_val)`)
- Voice TTS instructions sent as top-level request body field instead of nested under `extra_body`
- Stderr test race condition resolved with sleep+ordering adjustment
- Stdio transport test fixed to track correct PIDs (fake vs wrapper)
- Added `Kernel.send/2` import guards in test fakes to avoid Transport behaviour `send/2` conflicts
- Updated log assertion to match Buffer module wording
- Buffer decode_line test updated to use sigil syntax
- Added `@moduletag :capture_log` to BufferTest
- Init failure test fixed to assert specific error tuple

## [0.7.2] - 2026-02-06

### Fixed

- OTLP enablement now honors `CODEX_OTLP_ENABLE` values like `1/0` at runtime, including startup banner reporting and telemetry configuration defaults.

### Changed

- Bumped project version metadata to `0.7.2` in `mix.exs`, `VERSION`, README install snippet, and getting-started guide.

## [0.7.1] - 2026-02-06

### Changed

- Bumped `websockex` from `~> 0.4.3` to `~> 0.5.1` (adds telemetry integration)
- Bumped `credo` from 1.7.15 to 1.7.16
- Bumped `ex_doc` from 0.40.0 to 0.40.1

## [0.7.0] - 2026-02-06

### Added

- **Realtime API**: Full integration with OpenAI Realtime API for bidirectional voice interactions
  - `Codex.Realtime` module with agent builder and session orchestration
  - `Codex.Realtime.Session` WebSocket GenServer via WebSockex with reconnection, PubSub event broadcasting, and trapped linked-socket exits
  - `Codex.Realtime.Runner` for high-level agent session management with automatic tool call handling, handoff execution, and guardrail integration
  - `Codex.Realtime.Agent` struct and builder functions for agent configuration (instructions, tools, handoffs)
  - Session-level and model-level event types (`Codex.Realtime.Events`) for comprehensive event handling
  - Configuration structs: `RealtimeSessionConfig`, `RealtimeModelConfig`, `TurnDetectionConfig`, `InputAudioTranscription`
  - Core types: `Codex.Realtime.Audio` (PCM16/G711), `Codex.Realtime.Item`, `PlaybackTracker`
  - Semantic VAD turn detection with `eagerness` parameter (`:low`, `:medium`, `:high`), `silence_duration_ms`, and `prefix_padding_ms`
  - Idempotent `subscribe/unsubscribe` with map-based subscriber tracking
  - Tool calls run outside the session callback path so other session messages stay responsive

- **Voice Pipeline**: Non-realtime STT -> Workflow -> TTS pipeline
  - `Codex.Voice.Pipeline` for single-turn and multi-turn voice flows with async `Task`-based execution
  - `Codex.Voice.Result` for streamed audio output handling
  - `Codex.Voice.Workflow` behaviour, `Codex.Voice.SimpleWorkflow` (function-based), and `Codex.Voice.AgentWorkflow` (wrapping `Codex.Agent`)
  - Multi-turn conversation history management and optional greeting support
  - STT model behaviour (`Codex.Voice.Model.STTModel`) with OpenAI implementation (`gpt-4o-transcribe`)
  - TTS model behaviour (`Codex.Voice.Model.TTSModel`) with OpenAI implementation (`gpt-4o-mini-tts`)
  - `Codex.Voice.Model.ModelProvider` behaviour for model factories
  - `Codex.Voice.Input.AudioInput` for single audio buffers and `StreamedAudioInput` for streaming
  - `Codex.Voice.Events` for voice stream events (audio, lifecycle, error)
  - `Codex.Voice.Config` for pipeline configuration with STT/TTS settings
  - WAV encoding utilities for audio file handling

- **Options-level global config overrides** (`Codex.Options.config_overrides` / `config`)
  - Emitted before derived/thread/turn overrides in exec CLI args and app-server config payload
  - Four-layer precedence: options-level < derived < thread < turn
  - Input aliases `config` and `config_overrides` with nested map auto-flattening

- **Config override runtime validation** (`Overrides.validate_overrides/1`)
  - Validates TOML-compatible types: strings, booleans, integers, floats, arrays, nested maps
  - Rejects `nil`, tuples, PIDs, functions, and non-finite floats with `{:error, {:invalid_config_override_value, path, value}}`
  - Propagated through `build_args`/`config_override_args` via `{:ok, _} | {:error, _}` return paths in Exec

- **`:none` personality variant** across `ConfigTypes`, `Options`, `Thread.Options`, exec, and app-server
  - Encode/decode round-trip, `AppServer.Params.personality/1` clauses for `:none` / `"none"`
  - Works consistently on both exec CLI and app-server transports

- **Nested config override auto-flattening** (`Overrides.flatten_config_map/1`)
  - Recursive map-to-dotted-path flattening (e.g., `%{"model" => %{"personality" => "friendly"}}` → `[{"model.personality", "friendly"}]`)
  - Auto-detected in `normalize_config_overrides` for both exec and thread options
  - Deduplicated normalizer shared between `Exec` and `Thread.Options` via `Overrides.normalize_config_overrides/1`

- **Explicit web search disable tracking** — `Thread.Options` tracks `web_search_mode_explicit` to distinguish user-set `:disabled` from default `:disabled`; only emits `web_search="disabled"` override when explicitly set

- **SDK originator environment variable** — `CODEX_INTERNAL_ORIGINATOR_OVERRIDE=codex_sdk_elixir` set in `Runtime.Env.base_overrides/2` via `Map.put_new` (caller can override in `env`)

- **Shared runtime modules** extracted from duplicated patterns:
  - `Codex.Runtime.Erlexec` — unified erlexec startup across Exec, Connection, Sessions, ShellTool, and MCP Stdio
  - `Codex.Runtime.Env` — subprocess environment construction shared between Exec and AppServer.Connection
  - `Codex.Runtime.KeyringWarning` — deduplicated warn-once logic from Auth and MCP.OAuth
  - `Codex.Config.BaseURL` — `OPENAI_BASE_URL` env fallback with explicit option precedence (option → env → default)
  - `Codex.Config.OptionNormalizers` — shared reasoning summary, verbosity, and history persistence validation across Options and Thread.Options

- **Process lifecycle hardening**:
  - Supervised `MetricsHeir` GenServer replacing ad-hoc spawn/register for tool metrics ETS heir
  - Concurrent stage call coalescing in `Files.Registry` via `pending_stage_requests` map
  - Expired entry collection moved into work queue tasks (non-blocking Registry GenServer)
  - `drain_waiters/2` in MCP Stdio transport for subprocess exit
  - Monitor-based cleanup for `StreamQueue` pop waiters and `OpenAISTTSession` transcript waiters on caller DOWN
  - `Task.start` over `Task.start_link` in StreamableHTTP and RunResultStreaming fallback paths (avoids cascade crashes)
  - `async_nolink` via ephemeral `TaskSupervisor` in `Voice.Pipeline`
  - `StreamQueue`-backed queues replacing Agent-backed queues in `Voice.Result` and `StreamedAudioInput` (backpressure + close semantics)
  - `StreamQueue.try_pop/1` for non-blocking dequeue
  - `ets.select_delete` replacing `ets.foldl` in `Approvals.Registry`
  - Drain pending tool calls in `Realtime.Session.terminate/1`

- **Concurrency and safety improvements**:
  - Work queue in `Files.Registry` for non-blocking file I/O
  - WebSocket exits trapped in `Realtime.Session`; tool calls run outside callback path
  - Idempotent subscribe/unsubscribe with map-based subscriber tracking
  - `terminate/1` cleanup for `StreamableHTTP`, `Registry`, and `STTSession`
  - `String.to_existing_atom` replacing `String.to_atom` in `Config.Overrides` (atom safety)
  - Explicit key maps in `ToolOutput` to avoid atom interning from untrusted input
  - ETS heir process for tool metrics table survival across owner restarts
  - Atomic tool registration via `insert_new` in `Tools.Registry`
  - Lazy-start `ConnectionSupervisor` in `AppServer.connect`

- Hardcoded local preset for `gpt-5.3-codex` as the unified SDK default model

- `config_override`, `config_override_value`, and `config_override_scalar` type specs added to `Overrides`, `Options`, and `Thread.Options`

- `Codex.Files.list_staged_result/0` for explicit `{:ok, list} | {:error, reason}` responses

- Main SDK integration: realtime/voice error types in `Codex.Error`, telemetry events for session and pipeline lifecycle, delegation functions in main `Codex` module

- **Examples**:
  - `live_realtime_voice.exs`: Full realtime voice interaction demo
  - `realtime_basic.exs`: Simple realtime session setup
  - `realtime_tools.exs`: Function calling with realtime agents
  - `realtime_handoffs.exs`: Multi-agent handoffs in realtime sessions
  - `voice_pipeline.exs`: Basic STT -> Workflow -> TTS pipeline
  - `voice_multi_turn.exs`: Multi-turn streaming conversations
  - `voice_with_agent.exs`: Using `Codex.Agent` with voice pipelines
  - `live_config_overrides.exs`: Nested config override auto-flattening (thread and turn level)
  - `live_options_config_overrides.exs`: Options-level global config overrides, precedence, and validation
  - `live_personality.exs`: Updated to exercise all three personality variants including `:none`

### Changed

- Default model updated to `gpt-5.3-codex` across all credential sources (local presets, upgrade metadata, bundled `priv/models.json`)
- Removed auth-aware default logic (chatgpt vs api key split) and `codex-auto-balanced` preference for chatgpt auth
- `Codex.Files.force_cleanup/0`, `reset!/0`, and `metrics/0` return `{:error, reason}` if the registry is unavailable
- `Codex.Files.Registry.ensure_started` and `AppServer.ensure_connection_supervisor` require application supervision
- MCP transport failures normalized to `{:error, reason}` tuples
- Unified Realtime/Voice API key resolution through `Codex.Auth` precedence chain (`CODEX_API_KEY` → `auth.json OPENAI_API_KEY` → `OPENAI_API_KEY`)
- Replaced `live_realtime_voice_stub.exs` placeholder with working implementation
- Bumped `supertester` to `~> 0.5.1`

### Fixed

- `String.to_atom` replaced with `String.to_existing_atom` in `Config.Overrides` to prevent atom table exhaustion from untrusted input
- Explicit key maps in `ToolOutput` to avoid atom interning from untrusted config payloads
- Web search disable override no longer emitted when defaults are untouched (only when explicitly set via `web_search_mode: :disabled` or `web_search_enabled: false`)
- Removed hardcoded `http_client/0` helper from `WebSearchTool`

### Documentation

- Added Realtime and Voice guide (`guides/06-realtime-and-voice.md`) and sections to examples/README.md
- Documented four-layer config override precedence (options < derived < thread < turn) in README and guides
- Documented `:none` personality variant, SDK originator env, and explicit web search disable behavior
- Updated hexdocs module groups to include all Realtime, Voice, and shared runtime modules

## [0.6.0] - 2026-01-23

### Added

- Protocol types for text elements, collaboration modes, request_user_input, elicitation, rate limit snapshots, and config enums
- Event structs for session configuration, user input requests, MCP startup updates, elicitation requests, undo/rollback, review mode, config warnings, and collaboration lifecycle updates
- Thread/turn options: web search modes, personality overrides, collaboration modes, compact prompts, raw reasoning toggle, and per-thread output schemas
- Global options: model personality, auto-compact token limit, review model, hide agent reasoning, tool output token limit, and max agent threads
- Reasoning effort levels `:minimal` and `:xhigh`
- App-server APIs for thread fork/read/rollback/loaded list, skills config writes, config requirements, collaboration modes, app listing, and MCP reloads
- App-server params for personality, output schemas, and collaboration modes on thread start/resume and turn start
- Rate limit snapshots parsed from token usage updates and stored on threads
- Live examples covering collaboration modes, personality, web search modes, thread management, and rate limit monitoring

### Changed

- Web search config handling now prefers `web_search_mode` while honoring config defaults and feature gating
- Account rate limit notifications normalize to rate limit snapshot types
- Output schemas can be configured at the thread level with turn-level overrides
- Restructured and streamlined guides

### Fixed

- App-server connections stop spawned subprocesses on initialize-send failures and ignore invalid subscriber filters
- Files/approval registries are supervised, with staged attachments cleared on registry startup to prevent orphans
- Streamable HTTP transport and streaming producers avoid blocking GenServer callbacks by running work in tasks

### Deprecated

- `web_search_enabled` on `Codex.Thread.Options` (use `web_search_mode` instead)

## [0.5.0] - 2025-12-31

### Added

- Typed model options for reasoning summaries/verbosity/context window/supports reasoning summaries
- Provider tuning options (`request_max_retries`, `stream_max_retries`, `stream_idle_timeout_ms`)
- Exec config overrides for model provider/instructions, sandbox policy details, shell env policy, and feature flags
- Opt-in retry/rate-limit handling for exec and app-server transports
- Thread rate limit snapshot storage (`thread.rate_limits` + `Thread.rate_limits/1`)
- Exec stream idle timeout handling
- Keyring auth detection with warnings when unsupported
- Forced login enforcement for app-server login flows
- Config layer parsing for dotted core keys and `model_provider`
- Exec JSONL parsing for account notifications (`account/updated`, `account/login/completed`, `account/rateLimits/updated`)
- App-server protocol parity: thread resume `history`/`path`, skills reload, and fuzzy file search helper
- Raw response item structs (ghost snapshots/compaction) plus `rawResponseItem/completed` and `deprecationNotice` events
- Session helpers for metadata preservation, apply, and undo workflows
- History persistence options on `Codex.Options` and `Codex.Thread.Options`
- Legacy app-server v1 conversation helpers (`Codex.AppServer.V1`)
- Hosted tooling parity: `shell_command`, `write_stdin`, and `view_image` tools plus aliases (`container.exec`, `local_shell`)
- Guardrail parallel execution and tool behavior semantics (`reject_content`, `raise_exception`)
- MCP JSON-RPC client with stdio + streamable HTTP transports plus resources/prompts listing
- MCP OAuth credential storage/refresh helpers and MCP config helpers (`Codex.MCP.Config`)
- Skills and custom prompt helpers (`Codex.Skills`, `Codex.Prompts`) with prompt expansion rules

### Changed

- Exec JSONL now uses `--json` (alias of `--experimental-json`)
- Exec no longer passes sandbox/approval defaults unless explicitly configured
- Exec transport failures normalize into `Codex.Error` at thread level
- Config parsing now validates core config keys (features/history/shell env/auth store)
- `Codex.MCP.Client` now speaks MCP JSON-RPC (`initialize`, `tools/list`, `tools/call`)
- Shell tool schema now uses argv arrays with `workdir`/`timeout_ms` (legacy string commands remain supported)
- ApplyPatch supports `*** Begin Patch` grammar with add/update/delete/move, retaining unified diff fallback
- WebSearch schema now supports `action` arguments and honors `features.web_search_request` gating

### Documentation

- Updated README, API reference, and transport guides for MCP/skills/prompts parity


## [0.4.5] - 2025-12-30

### Added

- Shell hosted tool with `Codex.Tools.ShellTool` for executing shell commands
- Built-in default executor using erlexec for real command execution
- Command timeout support with configurable `:timeout_ms` option (default: 60s)
- Output truncation with configurable `:max_output_bytes` option (default: 10KB)
- Working directory support via `cwd` argument or `:cwd` option
- Approval integration for shell commands via `:approval` callback
- Custom executor support for testing and mocking shell behavior
- MCP tool discovery with `Codex.MCP.Client.list_tools/2` and `qualify?: true` option
- Tool name qualification with `mcp__<server>__<tool>` format matching upstream Rust implementation
- Tool name truncation with SHA1 hash suffix for names exceeding 64 characters
- `qualify_tool_name/2` public function for standalone tool name qualification
- `server_name` option for `Codex.MCP.Client.handshake/2` to enable qualified tool names
- Allow/deny list filtering for MCP tools via `:allow` and `:deny` options
- Tool caching with configurable bypass via `cache?: false`
- Duplicate qualified name deduplication (skips duplicates like upstream)
- MCP tool invocation with `Codex.MCP.Client.call_tool/4`
- ApplyPatch hosted tool with `Codex.Tools.ApplyPatchTool`
- Unified diff parsing and application for file create/modify/delete operations
- Dry-run support for patch validation without file modification
- Approval integration for file modifications via `:approval` callback
- Exponential backoff retry logic for MCP calls (default 3 retries, 100ms base delay, 5s max)
- Approval integration for MCP tool calls via `:approval` callback option
- Timeout control for MCP tool calls via `:timeout_ms` option (default 60s)
- Comprehensive retry module `Codex.Retry` with configurable backoff strategies
- Support for exponential, linear, constant, and custom backoff strategies
- Jitter support for retry delays to prevent thundering herd
- Customizable retry predicates via `:retry_if` option
- `on_retry` callbacks for logging and observability
- Stream retry support via `Codex.Retry.with_stream_retry/2`
- `Codex.TransportError` now includes `retryable?` field for automatic retry classification
- Telemetry events for MCP tool invocation:
  - `[:codex, :mcp, :tool_call, :start]` - When a tool call begins
  - `[:codex, :mcp, :tool_call, :success]` - On successful completion
  - `[:codex, :mcp, :tool_call, :failure]` - On failure after retries exhausted
- Rate limit detection with `Codex.RateLimit.detect/1` for automatic rate limit identification
- Rate limit handling with configurable backoff via `Codex.RateLimit.with_rate_limit_handling/2`
- Retry-After header parsing supporting both map and list header formats
- Rate limit telemetry events (`[:codex, :rate_limit, :rate_limited]`)
- Configurable rate limit delays via `:rate_limit_default_delay_ms`, `:rate_limit_max_delay_ms`, and `:rate_limit_multiplier`
- `Codex.Error.rate_limit/2` constructor for creating rate limit errors with retry hints
- `Codex.Error.rate_limit?/1` predicate for checking if an error is a rate limit error
- `Codex.Error.retry_after_ms/1` for extracting retry-after hints from errors
- `retry_after_ms` field on `Codex.Error` struct for rate limit retry hints
- FileSearch hosted tool with `Codex.Tools.FileSearchTool` for local filesystem search
- Glob pattern matching for file discovery (`**/*.ex`, `*.{ex,exs}`, etc.)
- Content search with regex support for finding text within files
- Case-sensitive/insensitive search modes via `case_sensitive` option
- Configurable result limits via `max_results` option (default: 100)
- Renamed `FileSearchTool` (vector store) to `VectorStoreSearchTool` for clarity
- WebSearch hosted tool with `Codex.Tools.WebSearchTool` for performing web searches
- Support for Tavily and Serper search providers via `:provider` option
- Mock provider for testing without API keys (`:provider => :mock`)
- HTTP client abstraction with `Codex.HTTPClient` for testability
- Custom searcher callback support for backwards compatibility and flexibility
- Configurable max results via `max_results` argument or `:max_results` option

### Changed

- `Codex.MCP.Client` struct now includes `server_name` field for tool qualification
- `call_tool/4` now uses exponential backoff by default
- `call_tool/4` default retries changed from 0 to 3 for improved resilience
- `Codex.Retry.retryable?/1` now recognizes `Codex.Error` with `:rate_limit` kind as retryable
- `Codex.Events.AccountRateLimitsUpdated` now includes optional `thread_id` and `turn_id` fields

### Fixed

### Documentation

- Added MCP Tool Discovery section to README with qualification examples
- Updated `Codex.MCP.Client` module documentation with tool name qualification details
- Added comprehensive `call_tool/4` documentation with examples for retries, backoff, approval, and telemetry

## [0.4.4] - 2025-12-29

### Added

- App-server `UserInput` list support for `Codex.Thread.run/3` and `run_streamed/3` (text/image/localImage)
- Thread/turn app-server params for model/provider/config/instructions, sandbox_policy, and experimental raw events, with defaults for model + reasoning effort
- Typed app-server notifications for reasoning summaries/deltas, command/file output deltas, terminal interaction, MCP progress, and account updates
- Exec CLI parity flags (`--profile`, `--oss`, `--local-provider`, `--full-auto`, `--dangerously-bypass-approvals-and-sandbox`, `--output-last-message`, `--color`)
- Generic `-c key=value` config overrides, exec review wrapper, and resume --last support
- Grant-root approval handling for file changes and `Codex.AppServer.command_write_stdin/4`

### Changed

- Reasoning items now preserve `summary`/`content` structure instead of flattened text
- App-server `turn.error` payloads are surfaced on `Codex.Events.TurnCompleted`

### Fixed

- Streamed turn failures now handle non-text `final_response` payloads without crashing and include `turn.error` details when present
- Structured `/new` input blocks now reset conversation state for app-server/exec turn runs and streams
- Tool guardrail and approval hook exceptions are surfaced as errors instead of crashing the turn
- Progress telemetry metadata now merges even when base metadata is nil

### Documentation

- Updated README and API reference for new input types, exec flags, and app-server deltas

## [0.4.3] - 2025-12-27

### Added

- App-server error notifications now expose `additional_details` and retry metadata
- Config layer loader that honors system/user/project `config.toml` sources

### Changed

- Remote models gating now respects `/etc/codex/config.toml` and `.codex/config.toml` layers
- `priv/models.json` synced to latest upstream format

### Documentation

- Documented config layer precedence for remote model gating in README/examples

## [0.4.2] - 2025-12-20

### Added

- Internal `Constrained` module for wrapping configuration values with validation constraints
- Internal `ConstraintError` exception for reporting constraint violations
- `:external_sandbox` sandbox mode for containerized/external sandbox environments
- `{:external_sandbox, :enabled | :restricted}` tuple variant with explicit network access control
- Support for `:admin` skill scope (reads from `/etc/codex`) - pass-through from CLI
- Support for `short_description` field in skill metadata - pass-through from CLI

### Changed

- Updated bundled `priv/models.json` to upstream (commits d7ae342ff..987dd7fde)
- Model presets updated:
  - `gpt-5.1-codex-max`: priority 0 → 1, now upgrades to `gpt-5.2-codex`
  - `gpt-5.1-codex-mini`: visibility `:list` → `:hide` (hidden by default)
  - `gpt-5.1-codex`: visibility now `:hide`
  - `gpt-5.1`: now upgrades to `gpt-5.2-codex`

### Fixed

- Normalize signal-based exits to conventional shell exit codes (`128 + signal`) when reporting `Codex.TransportError`

### Documentation

- Added `docs/20251220/` directory with comprehensive porting plan and validation

### Internal

- Synced with upstream codex-rs commits d7ae342ff..987dd7fde (32 commits)
- Added constraint system aligned with upstream `Constrained<T>` type

## [0.4.1] - 2025-12-18

### Added

- Auth-aware model defaults (ChatGPT `gpt-5.2-codex`, API `gpt-5.1-codex-max`) with `codex-auto-balanced` preference when remote models are enabled
- Full model registry port with local presets, upgrade metadata, and reasoning effort normalization including `none`
- Remote model support behind `features.remote_models`, with bundled `models.json` parsing and cache handling

### Changed

- API key handling now prioritizes `CODEX_API_KEY` and `auth.json` `OPENAI_API_KEY`; ChatGPT tokens no longer populate `api_key`
- Documentation and examples updated for the new defaults, model list, and remote model behavior

## [0.4.0] - 2025-12-17

### Breaking Changes

- `Codex.AppServer.thread_compact/2` now returns `{:error, {:unsupported, _}}` - the upstream `thread/compact` API was removed; compaction is now automatic

### Changed

- `Codex.AppServer.Mcp.list_servers/2` now uses `mcpServerStatus/list` method with automatic fallback to legacy `mcpServers/list` for older servers
- Added `Codex.AppServer.Mcp.list_server_statuses/2` as an alias

### Documentation

- Updated app-server transport guide to reflect removed `thread/compact` API
- Added skills feature flag prerequisite documentation
- Added `.codex/` sandbox read-only behavior note
- Updated config layer schema documentation for `ConfigLayerSource` tagged union

## [0.3.0] - 2025-12-14

### Added
- Multi-transport refactor: exec JSONL remains the default, and a new app-server JSON-RPC (stdio) transport is available via `transport: {:app_server, conn}`
- `Codex.AppServer` connection API plus v2 request wrappers (threads, turns, skills, models, config, review, command exec, feedback, account, MCP)
- Stateful approval handling for app-server server-initiated requests (`item/*/requestApproval`) with both hook-based auto-approval and manual `respond/3`
- Typed event/item adapters for core app-server notifications, with lossless passthrough for unknown methods/items

### Changed
- `turn/diff/updated` now surfaces `diff` as a unified diff string (app-server v2)

### Fixed
- App-server default subprocess selection and iodata sending for stdio writes

## [0.2.5] - 2025-12-13

### Fixed
- Quieted `mix test` output by default (test log capture + console logger level) while keeping logs available on failures
- Fixed an ETS race in tool registry resets that could intermittently fail in async tests

## [0.2.4] - 2025-12-13

### Added
- `examples/run_all.sh` defaults to `gpt-5.1-codex-mini` for consistent runs and reports failures without stopping the whole suite

### Fixed
- Exec subprocess env inheritance so `codex` can use CLI-login auth when no env overrides are provided
- Structured output example schema compatibility with `codex exec --output-schema`, plus clearer example error output
- Concurrency example progress output and timeouts to avoid “stuck” runs

## [0.2.3] - 2025-12-13

### Added
- Forwarded Codex CLI execution options via `Codex.Thread.Options`: sandbox mode, working directory, additional writable directories, skip-git-repo-check, web search toggle, approval policy, and workspace-write network access
- `turn_opts[:clear_env?]` to optionally clear inherited subprocess environment when spawning `codex`

### Changed
- `OPENAI_BASE_URL` is now set for the `codex` subprocess from `Codex.Options.base_url`
- Port gap analysis docs updated to reflect the wired Codex CLI surface and erlexec hardening option

## [0.2.2] - 2025-12-13

### Added
- `auto_previous_response_id` run option via `Codex.RunConfig` (forward-compatible; requires backend `response_id` support)
- `last_response_id` on `Codex.Turn.Result` when the backend surfaces a response identifier

### Changed
- README/docs now distinguish Elixir-side OTLP exporting from codex-rs `[otel]` config.toml exporting

### Fixed
- Tool metadata is loaded before registration so hosted tools register under their declared names (e.g. `file_search`)
- Exec CLI arg compatibility: image attachments now use `--image`, and unsupported `--tool-output/--tool-failure` flags are no longer emitted

## [0.2.1] - 2025-11-29

### Added
- App-server event coverage for token usage deltas, turn diffs, and compaction notices, plus explicit thread/turn IDs on item and error notifications
- Streaming example updates to surface live usage and diff events alongside item progress
- Automatic auth fallback to Codex CLI login when API keys are absent; live two-turn walkthrough example
- Regression tests and fixtures for `/new` resets, early-exit session non-persistence, and rate-limit/sandbox error normalization
- Live usage/compaction streaming example aligned with new model defaults and reasoning effort handling
- Live exec controls example (env injection, cancellation tokens, timeout tuning) plus README/docs updates covering safe-command approval bypass
- Sandbox warning normalization updates (Windows read-only `.git` detection, world-writable dedup) and runnable example `sandbox_warnings_and_approval_bypass.exs`
- README/docs refresh covering policy-approved bypass flags and normalized sandbox warning strings
- Added `examples/live_tooling_stream.exs` to showcase streamed MCP/shell events and fallback handling when `turn.completed` omits a final response
- Live telemetry stream example (thread/turn IDs, source metadata, usage deltas, diffs, compaction savings) with README/docs references
- Live telemetry stream defaults tuned for fast runs (minimal reasoning, short prompt)

### Changed
- Thread resumption now uses `codex exec … resume <thread_id>` (no `--thread-id` flag)
- `/new` clears conversations and early-exit turns do not persist thread IDs, matching upstream CLI
- Turn failures normalize rate-limit and sandbox assessment errors into `%Codex.Error{}`
- Telemetry now propagates source info, thread/turn IDs, OTLP mTLS options, and richer token/diff/compaction signals through emitters and OTEL spans

## [0.2.0] - 2025-10-20

### Added
- Core Codex thread lifecycle with streaming, resumption, and structured output decoding (`Codex.Thread`, `Codex.Turn.Result`, `Codex.Events`, `Codex.Items`)
- GenServer-backed `Codex.Exec` process supervision, error handling, and tool invocation pipeline
- Approval policies, hook behaviour, registry support, and telemetry events for tooling approvals
- File staging registry, attachment helpers, parity fixtures, and harvesting script for Python SDK alignment
- Comprehensive telemetry module with OTLP exporter gating, metrics, and approval instrumentation
- Mix tasks (`mix codex.verify`, `mix codex.parity`), integration tests, and Supertester-powered contract suite
- Rich examples and documentation covering approvals, streaming, concurrency, observability, and design dossiers

### Changed
- Refreshed `README.md` with 0.2.0 usage guide, testing workflow, and observability configuration
- Expanded HexDocs configuration to include new guides, design notes, and release documentation
- Updated package metadata to ship changelog, examples, and assets with the Hex release

## [0.1.0] - 2025-10-11

Initial design release.

[Unreleased]: https://github.com/nshkrdotcom/codex_sdk/compare/v0.9.1...HEAD
[0.9.1]: https://github.com/nshkrdotcom/codex_sdk/compare/v0.9.0...v0.9.1
[0.9.0]: https://github.com/nshkrdotcom/codex_sdk/compare/v0.8.0...v0.9.0
[0.8.0]: https://github.com/nshkrdotcom/codex_sdk/compare/v0.7.2...v0.8.0
[0.7.2]: https://github.com/nshkrdotcom/codex_sdk/compare/v0.7.1...v0.7.2
[0.7.1]: https://github.com/nshkrdotcom/codex_sdk/compare/v0.7.0...v0.7.1
[0.7.0]: https://github.com/nshkrdotcom/codex_sdk/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/nshkrdotcom/codex_sdk/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/nshkrdotcom/codex_sdk/compare/v0.4.5...v0.5.0
[0.4.5]: https://github.com/nshkrdotcom/codex_sdk/compare/v0.4.4...v0.4.5
[0.4.4]: https://github.com/nshkrdotcom/codex_sdk/compare/v0.4.3...v0.4.4
[0.4.3]: https://github.com/nshkrdotcom/codex_sdk/compare/v0.4.2...v0.4.3
[0.4.2]: https://github.com/nshkrdotcom/codex_sdk/compare/v0.4.1...v0.4.2
[0.4.1]: https://github.com/nshkrdotcom/codex_sdk/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/nshkrdotcom/codex_sdk/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/nshkrdotcom/codex_sdk/compare/v0.2.5...v0.3.0
[0.2.5]: https://github.com/nshkrdotcom/codex_sdk/compare/v0.2.4...v0.2.5
[0.2.4]: https://github.com/nshkrdotcom/codex_sdk/compare/v0.2.3...v0.2.4
[0.2.3]: https://github.com/nshkrdotcom/codex_sdk/compare/v0.2.2...v0.2.3
[0.2.2]: https://github.com/nshkrdotcom/codex_sdk/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/nshkrdotcom/codex_sdk/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/nshkrdotcom/codex_sdk/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/nshkrdotcom/codex_sdk/releases/tag/v0.1.0
