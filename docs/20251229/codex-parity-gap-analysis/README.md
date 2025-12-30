# Codex CLI Parity Gap Analysis (2025-12-29)

This report compares the vendored upstream Codex CLI (`codex/`) with the Elixir SDK in this repo.
The only accepted difference is that the SDK does not bundle the CLI runtime. Everything else is
treated as a parity requirement unless explicitly marked as UI-only or upstream-internal.

## Scope and sources

- Upstream: `codex/` at commit `810ebe0d2b23cdf29f65e6ca50ee46fa1c24a877`
  - Exec CLI options and JSONL schema: `codex/codex-rs/exec/src/cli.rs`,
    `codex/codex-rs/exec/src/exec_events.rs`
  - App-server protocol: `codex/codex-rs/app-server/README.md`,
    `codex/codex-rs/app-server-protocol/src/protocol/common.rs`,
    `codex/codex-rs/app-server-protocol/src/protocol/v2.rs`
  - Config and feature flags: `codex/docs/config.md`
- SDK: `lib/codex/*`, `docs/*`, and current README behavior claims

## Summary

- Exec JSONL parity is strong for core event parsing and tool/command/file items.
- App-server support exists but the high-level `Codex.Thread` API is text-only and does not expose
  several thread/turn parameters (model/provider/config/instructions) that the protocol supports.
- Several app-server notifications are only surfaced as raw `AppServerNotification` events instead
  of typed events.
- Exec CLI parity gaps remain for `--profile`, `--oss`/`--local-provider`, `review`, and general
  config overrides.
- Interactive CLI/TUI features are deferred (see plan); parity will focus on programmatic APIs and
  exec CLI behavior first.

## Gaps by area

### 1) High-level thread/turn API (app-server)

- **Missing multi-modal input support**: `Codex.Thread.run/3` and `run_streamed/3` accept only
  binary input, but app-server supports `UserInput` blocks (`text`, `image`, `localImage`).
  - Upstream: `UserInput` union in `codex/codex-rs/app-server-protocol/src/protocol/v2.rs`
  - SDK: `lib/codex/thread.ex` guards on `is_binary/1`
- **Thread start/resume parameter coverage**: app-server `thread/start` supports `model`,
  `model_provider`, `config`, `base_instructions`, `developer_instructions`, and
  `experimental_raw_events`, but the SDK does not expose or forward them.
  - Upstream: `ThreadStartParams` / `ThreadResumeParams`
  - SDK: `lib/codex/transport/app_server.ex` only forwards `working_directory`, `approval_policy`,
    `sandbox`
- **Defaults ignored for app-server**: `Codex.Options.model` and `reasoning_effort` are not used
  for app-server runs unless callers pass `turn_opts` explicitly.
  - SDK: `lib/codex/transport/app_server.ex` does not include model/effort defaults
- **Sandbox policy shape not modeled**: app-server supports structured `SandboxPolicy` with
  `writableRoots` and `networkAccess`; SDK only has coarse `sandbox` enums and does not surface
  a typed `sandbox_policy` field in thread options.

### 2) App-server notifications and item fidelity

- **Missing typed notifications** (currently only raw):
  - `item/reasoning/summaryPartAdded`
  - `item/fileChange/outputDelta`
  - `item/commandExecution/terminalInteraction`
  - `item/mcpToolCall/progress`
  - `account/rateLimits/updated`
  - `mcpServer/oauthLogin/completed`
  - `windows/worldWritableWarning`
  - Upstream registry: `codex/codex-rs/app-server-protocol/src/protocol/common.rs`
  - SDK mapping: `lib/codex/app_server/notification_adapter.ex`
- **Turn error details dropped**: app-server `turn/completed` carries `turn.error` but the SDK
  `Events.TurnCompleted` struct has no error field and the adapter discards it.
  - SDK: `lib/codex/events.ex`, `lib/codex/app_server/notification_adapter.ex`
- **Reasoning structure collapsed**: app-server `reasoning` items include `summary` and `content`
  with deltas; SDK flattens into a single `text` field, losing section boundaries and raw content.
  - SDK: `lib/codex/app_server/item_adapter.ex`, `lib/codex/items.ex`
- **File change output stream not exposed**: `item/fileChange/outputDelta` deltas are not mapped,
  so clients cannot reconstruct apply-patch output streams.

### 3) Exec CLI parity

- **Missing CLI flags**:
  - `--profile` (config profile selection)
  - `--oss` and `--local-provider` (open-source provider mode)
  - `--full-auto`, `--dangerously-bypass-approvals-and-sandbox` (aliases to policy/sandbox config)
  - `--output-last-message`, `--color` (less critical but still missing)
  - Upstream: `codex/codex-rs/exec/src/cli.rs`
  - SDK: `lib/codex/exec.ex` only passes a subset
- **No wrapper for `codex exec review`**: upstream supports review as an exec subcommand; SDK has
  `AppServer.review_start/4` but no exec-mode review entry point.
- **No `resume --last` support**: upstream exec supports resuming most recent session without an id.
- **No generic config overrides**: upstream allows arbitrary `-c key=value` overrides; SDK only
  emits a small fixed set of `--config` values.

### 4) Model/provider configuration

- **Exec path cannot select provider**: OSS/local provider selection (`--oss`/`--local-provider`)
  has no equivalent in the SDK exec wrapper.
- **App-server model_provider not exposed** in `Codex.Thread.Options` or turn options (only
  available via direct `Codex.AppServer.thread_start` calls).

### 5) Approvals and sandbox edge cases

- **File-change approval grant root**: app-server can send `grantRoot` but SDK cannot reply with
  a grant-root acceptance payload.
  - SDK: `lib/codex/app_server/approvals.ex`, `lib/codex/app_server/approval_decision.ex`
- **Terminal interaction flow**: no SDK-level API to forward stdin for interactive commands when
  `item/commandExecution/terminalInteraction` arrives.

### 6) UI-only CLI features (deferred)

The following upstream features exist only in the interactive CLI/TUI and have no SDK equivalent:
slash commands, TUI animations, notifications, update checks, shell completion, and interactive
session pickers. These are explicitly deferred until the programmatic and exec CLI parity items
are complete.

## Plan to close gaps (priority order)

### 1) App-server parity for programmatic APIs

1. **Multi-modal input**: allow `Codex.Thread.run/3` and `run_streamed/3` to accept
   `String.t()` or `[UserInput]` (text/image/localImage). Reuse `Codex.AppServer.Params.user_input/1`
   for normalization.
2. **Thread start/resume expansion**: add fields to `Codex.Thread.Options` and wire through:
   `model`, `model_provider`, `config`, `base_instructions`, `developer_instructions`,
   `experimental_raw_events`, and a typed `sandbox_policy`.
3. **Apply defaults for app-server**: pipe `Codex.Options.model` and `reasoning_effort` into
   app-server start/turn defaults (via `model` and `config` overrides).
4. **Typed notifications**: add event structs + adapter entries for the missing app-server
   notifications and map `turn.error` into `TurnCompleted`.
5. **Reasoning fidelity**: extend `Items.Reasoning` (or add a new struct) to preserve summary
   and content, and emit structured deltas.

### 2) Exec CLI parity

1. **Flag support**: plumb `--profile`, `--oss`, `--local-provider`, `--full-auto`,
   `--dangerously-bypass-approvals-and-sandbox`, `--output-last-message`, and `--color`
   through `Codex.Options`/`Codex.Thread.Options` into `Codex.Exec`.
2. **Generic config overrides**: accept a `config_overrides` map or list that translates to
   `-c key=value` in `Codex.Exec`.
3. **Review/resume wrappers**: add `Codex.Exec.review/2` and `Codex.resume_thread(:last)`
   (or equivalent) to reach `codex exec review` and `resume --last`.

### 3) Approvals/sandbox edge cases

1. **Grant-root approvals**: support file-change approval responses that include `grantRoot`.
2. **Terminal interaction API**: expose an API for writing stdin to interactive commands after
   `item/commandExecution/terminalInteraction` events.
3. **Sandbox policy parity**: model and validate full `SandboxPolicy` shapes for app-server,
   including writable roots and `networkAccess`.

### Deferred: CLI wrapper for interactive UI features

Interactive CLI/TUI features (slash commands, animations, notifications, update checks, shell
completion, session picker) are deferred until the three core parity groups above are complete.

## Validation and tests

- Add fixtures for the missing app-server notifications and ensure typed events are emitted.
- Add tests for multi-modal input handling in app-server transport.
- Add live or mocked exec tests for `review` and `resume --last`.
- Update parity matrices and examples to cover new surfaces.
