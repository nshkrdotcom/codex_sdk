# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
