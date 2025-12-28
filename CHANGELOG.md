# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
