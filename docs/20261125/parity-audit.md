# Codex parity audit — 2026-11-25

## Evidence and boundaries

- Starting SDK: 0.21.6, `194b7cabc1e80ff9772a63fd83ca01ad1c2abe8f`.
- Executable contract: official `rust-v0.172.0`,
  `3d86e43b075adeba2193ec5c22ac92f55afd82e6`.
- Comparison only: official main,
  `06f334aa4b053023c5b4199dde0ba9c004d64820`.
- The previous July protocol sweep and November 0.170.0 authenticated model
  fixture are historical evidence, not evidence of new endpoint behavior.
- Source audit used TS SDK exports and execution implementation/tests, Python
  sync and async clients and goal/router code, Rust CLI/exec, app-server README,
  request registry, v2 Rust payloads, processors, and generated schemas. The
  source snapshots do not include the Core dependency checkout. No CLI or
  Elixir runtime is used here. Fixtures have been added, not executed.

The accompanying inventories are searchable, deliberately conservative:

- [App-server method inventory](app-server-method-inventory.tsv): top-level
  checked-in schema union methods **and** Rust common registry declarations.
  Stable and main checked-in unions both have 110 client requests, 10 server
  requests, 87 server notifications, and one client notification. The 294-row
  combined inventory includes registry-only methods.
  Checked-in schemas omit some experimental requests; a registry attribute
  does not establish all field or runtime gates. Literal paths are leads, not
  a proof of a public wrapper or its behavior. An absent literal does not
  prove an endpoint cannot be reached through the generic connection.
- [Python API inventory](python-sdk-inventory.tsv): AST inventory of named
  public definitions in the official SDK client, handle and helper files,
  not the separate Agents SDK and not all generated payload classes.
- [CLI declaration inventory](cli-declaration-inventory.tsv): Clap declarations
  in root CLI source modules, exec and shared CLI options, including hidden
  and gated commands. This is source-oriented, not a rendered `--help` dump;
  flattening, platform gates and dynamically composed arguments need local
  CLI inspection. No CLI installation, update or management is an SDK goal.

## Feature-level disposition

Paths below are relative to the upstream source root (stable unless marked
main). Tests and examples are SDK-relative. “Implemented” means code and
fixtures, not a passing ExUnit or live result. Existing surfaces were sampled;
not every field or workflow in the inventories has been exhaustively traced.

| Feature / upstream evidence | SDK surface | Status / check |
| --- | --- | --- |
| TS `sdk/typescript/src/{index,codex,thread,exec,codexOptions,threadOptions,turnOptions,outputSchemaFile}.ts`: thread creation/resume, run and runStreamed | `Codex`, `Thread`, `Exec`, `Runtime.Exec`, `Items`, `Events` | Existing; subprocess fixture and live basic, streaming, resume, structured-output examples; compare exit/cancellation/usage |
| TS per-invocation environment, image order, output schema temporary file | `Options`, `Thread`, `Attachment`, `Exec.Options` | Partial; existing explicit env and attachment path/schema machinery; verify mixed structured inputs and original input/image ordering (not identical APIs) |
| TS main `threadOptions.ts` adds `indexed` web-search enum | `Thread.Options`, `Config.Overrides` | Main-only defer typed value until installed contract and Core evidence; do not treat as stable |
| Python `sdk/python/src/openai_codex/{api,client,async_client,_message_router,_run}.py`: sync/async thread handles, turns, streaming, interrupt, steer | `AppServer`, `Transport.AppServer`, `Thread.run`, `Thread.run_streamed` | Existing/partial; GenServer/Stream rather than Python coroutine API; test two concurrent threads, interruptions, disconnect and server requests; full race audit remains |
| Python `_goal.py`, `api.py`; Rust `protocol/v2/thread.rs`, goal processor | `AppServer.thread_goal_set/get/clear`, `Events.ThreadGoalUpdated/Cleared` | Implemented RPCs/notifications; persisted threads; `goals` feature and user origin; null budget; Python logical goal completion/resumption orchestration deferred |
| Rust `app-server-protocol/src/protocol/common.rs`, v2 `model_provider.rs`, model-provider handler | `model_provider_list`, `model_provider_default_set`, `model_provider_config_write` | Implemented; write only disposable config; settings patch is server-validated; verify provider list and default in subsequently started threads |
| Rust `thread.rs` thread list/search, search processor and `ThreadSearchPartial` | `thread_list`, `thread_search`, `thread_search_occurrences`, `thread_search_stream`, `thread_search_stream_cancel`, subscriber filters | Implemented fields and remote correlation; experimental search; UTF-16 ranges; raw result map; stdio explicit ID path deferred to Core; test concurrent requests, cancel, timeout, disconnect |
| Rust `exec/src/cli.rs`, `exec/src/remote.rs`, `utils/cli/src/shared_options.rs` | `Thread.Options.remote`, `remote_auth_token_env`, `Runtime.Exec.Profile` | Implemented stable remote new/resume-by-ID; no local defaults/model/config/credentials injected; server-owned model/workspace/permissions. CLI validates ID and connection; remote review, fork, last, images/schema and local control unsupported. Main remote model/effort support deferred |
| Rust `exec/src/cli.rs`, `protocol/v2/turn.rs` thread source and Cyber program | `Thread.Options.thread_source`, turn `cyber_access_program` on exec and app-server | Implemented forwarding; fresh exec source only; standard/daybreak access is provider-gated; no model entitlement claim |
| Rust `exec/src/lib.rs`, `tests/suite/resume.rs` permission/workspace restore | `Runtime.Exec`, `Thread.resume` | Inherited with fixture verifying absent cwd/sandbox remain absent; confirm caller overrides and server restore with real CLI |
| Rust `exec/src/exec_events.rs`, v2 `shared.rs`, `account.rs` | `Events`, `NotificationAdapter`, `Sanitizer` | Implemented cache-write usage, false retry, reason and Bedrock access-key mode; raw unknown fields where supported; full lifecycle/realtime projection audit remains |
| Rust v2 `bedrock.rs`, `account.rs`, auth-store and runtime account/Bedrock handlers | `AppServer.Account`, `Auth.Store`, `Sanitizer` | Implemented source-backed discovery/setup/GovCloud advisory, key login and redacted store; experimental handshake; separate AWS live evidence pending |
| Rust v2 `mcp.rs`, MCP handlers, config schema | `AppServer.Mcp`, existing config overrides | Implemented scoped list/resource/tool/OAuth fields; scoped failure never falls back; existing unscoped legacy fallback preserved. Lazy optional stdio startup/cached tools and connected-app reviewer enforcement inherited; test actual config and scope |
| Rust app-server dynamic tool/server-request contracts, approvals, realtime, subagent lifecycle | Existing `AppServer`, `Protocol`, `Realtime`, transport and subagent modules | Existing/partial; wire maps and unknown fallback where already supported; verify queued child replies after interruption, streaming error details and updated realtime history; no full typed projection claim |
| Main v2 `item.rs`, `config.rs`, `fs.rs`, `plugin.rs`, `realtime.rs`, `turn.rs`, dynamic tool call schemas, startup gateway OAuth changes | Generic wire path | Deferred; do not invent result format, hook failure policy, filesystem metadata, moderation or new startup OAuth semantics before verifying main handler/gates and released CLI |
| CLI `cli/src/main.rs`: Agents, Exec, Review, Login, Logout, Mcp, Plugin, AppServer, RemoteControl, App, Completion, Doctor, Sandbox, Debug, Apply, Resume, Queue, Archive, Delete, MigrateRollouts, MigrateNfsDb, Unarchive, Fork, Cloud, ExecServer, Features; hidden/platform commands | `Codex.CLI.run/start` and existing typed helpers, `Thread` | Raw passthrough or typed subset; terminal UI, migrations, daemon/service management and hidden internals out of scope unless intentionally exposed; no update or install workflow |
| Exec clap fields and nested review/fork/resume declarations | `Runtime.Exec.Profile`, `CLI` | Existing/partial; strict-config, trust, approve-for-me, hook-trust bypass, exec fork/advanced review controls need further first-class audit; no silent claim of coverage. Legacy `--full-auto` and `--continuation-token` remain in old local API despite absence in stable exec declaration; resolve via explicit compatibility decision. SDK cancellation is internal on normal exec; governed provider-control contract still needs Core verification |
| Stable remote provider catalog and config | `CliSubprocessCore.ModelRegistry` | Existing shared Nov 17 catalog; no new authenticated model evidence or Core source. Do not change catalog locally; collect authenticated `model/list` with hidden entries and coordinate Core if changed |

## Runtime checks still owed

Use independently installed 0.172.0, then optionally a separately maintained
pinned-main CLI to evaluate main-only surfaces. Use sanitized request/result
metadata, actual argv captured by fixture, exit codes, thread/request IDs
(redact production IDs), and expected counts/ordering. No actual credentials,
raw auth files, production content or signed URLs. See examples README and the
provider behavior manifest. Do not promote rows from source/fixture to live
until a reproducible authenticated check succeeds. The complete local QC plan
must include compilation, formatter, strict Credo, Dialyzer, deterministic
lifecycle tests, full tests/coverage, documentation, and live examples.
