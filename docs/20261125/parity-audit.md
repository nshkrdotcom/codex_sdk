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
  initial source audit used snapshots. Local validation used installed CLI 0.172.0
  and the locked Core 0.9.6 Hex package. The runtime evidence below records the
  scope of the follow-up.

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
main). Tests and examples are SDK-relative. Existing surfaces were sampled. Runtime
results apply to the scenarios listed below.

| Feature / upstream evidence | SDK surface | Status / check |
| --- | --- | --- |
| TS `sdk/typescript/src/{index,codex,thread,exec,codexOptions,threadOptions,turnOptions,outputSchemaFile}.ts`: thread creation/resume, run and runStreamed | `Codex`, `Thread`, `Exec`, `Runtime.Exec`, `Items`, `Events` | Existing; subprocess fixture and live basic, streaming, resume, structured-output examples; compare exit/cancellation/usage |
| TS per-invocation environment, image order, output schema temporary file | `Options`, `Thread`, `Attachment`, `Exec.Options` | Partial; existing explicit env and attachment path/schema machinery; verify mixed structured inputs and original input/image ordering (not identical APIs) |
| TS main `threadOptions.ts` adds `indexed` web-search enum | `Thread.Options`, `Config.Overrides` | Main-only defer typed value until installed contract and Core evidence; do not treat as stable |
| Python `sdk/python/src/openai_codex/{api,client,async_client,_message_router,_run}.py`: sync/async thread handles, turns, streaming, interrupt, steer | `AppServer`, `Transport.AppServer`, `Thread.run`, `Thread.run_streamed` | Existing/partial; GenServer/Stream rather than Python coroutine API; test two concurrent threads, interruptions, disconnect and server requests; full race audit remains |
| Python `_goal.py`, `api.py`; Rust `protocol/v2/thread.rs`, goal processor | `AppServer.thread_goal_set/get/clear`, `Events.ThreadGoalUpdated/Cleared` | Implemented RPCs/notifications; persisted threads; `goals` feature and user origin; null budget; Python logical goal completion/resumption orchestration deferred |
| Rust `app-server-protocol/src/protocol/common.rs`, v2 `model_provider.rs`, model-provider handler | `model_provider_list`, `model_provider_default_set`, `model_provider_config_write` | Implemented; write only disposable config; settings patch is server-validated; verify provider list and default in subsequently started threads |
| Rust `thread.rs` thread list/search, search processor and `ThreadSearchPartial` | `thread_list`, `thread_search`, `thread_search_occurrences`, `thread_search_stream`, `thread_search_stream_cancel`, subscriber filters | Implemented fields and remote correlation; experimental search; UTF-16 ranges; raw result map; stdio explicit IDs deferred to Core; remote fixtures cover concurrent requests, cancellation, timeout, and late partials |
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
| Stable remote provider catalog and config | `CliSubprocessCore.ModelRegistry` | Existing shared Nov 17 catalog; isolated `model/list` with hidden entries returned a different inventory without an authenticated account; authenticated comparison still pending in Core |

## Local validation

Elixir and Mix 1.19.5, Erlang/OTP 28.3.1, locked Hex
`cli_subprocess_core` 0.9.6, and independently installed `codex-cli 0.172.0`.
The vendored stable tag resolves to the pinned revision above.

- The stable exec remote handler supports fresh exec and resume by UUID.
  The SDK checks the endpoint before launch and accepts authenticated loopback
  WebSocket or TLS WebSocket. Unix transport accepts no token argument. The
  child fixture verifies flag placement, the caller token, and absence of
  SDK-injected credentials and base URL. Ambient environment survives unless
  the caller sets `clear_env?: true`.
- Core's `JsonRpc.request/4` builds the adapter request from method and params.
  An explicit ID is available at the lower `ProtocolSession.request/3` and
  adapter layer, where the pending request map overwrites duplicate correlation
  keys. Stdio streaming remains deferred pending an app-server facade contract
  for explicit ID ownership, timeout and late-frame handling, and notification
  fanout. Ordinary stdio history search uses the existing request path.
- Both legacy exec flags are absent from stable Clap declarations. The existing
  SDK option behavior and governed invocation are retained pending a compatibility
  decision. Core 0.9.6 still lists `--full-auto` as a provider control.
- Stable goal service accepts explicit paused creation and substitutes a managed
  maximum when clearing a budget under a configured cap. The isolated config
  had `[features] goals = true` and an experimental app-server handshake.
  A direct probe passed paused create, explicit null budget, get, clear, get
  returning null, and archive on a disposable thread. Separate calls confirmed
  the ephemeral thread and disabled-feature errors.
- The read-only example passed provider inventory, the empty included-ID list,
  and experimental Bedrock discovery. A separate capabilities read passed.
  Account read in the isolated home did not establish an authenticated account.
  The hidden-inclusive model list returned 14 rows (3 hidden), with 3 IDs
  additional and 1 absent compared with the locked Core fixture. This sample
  did not establish entitlement or justify changing the shared catalog.
- The history-and-goals example reached the first model turn and received
  HTTP 401. The local exec examples encountered upstream Responses WebSocket
  connection failures. The failed turn still persisted its user message.
  Ordinary search found the disposable marker by recency, and occurrence
  search returned the right UTF-16 span after an astral character. Multi-page
  forward and backward search with successful turns remains open.
- The isolated optional stdio MCP fixture launched zero times before first
  tool use and once after. Thread/name inventory, echo, thread/global resource
  reads, and exclusion of an unrelated registration passed. Hosted environment
  scope, OAuth, and reviewer policy remain unverified.
- A raw Bedrock access-key fixture echoed synthetic credentials in success,
  error, and child stderr. SDK response values and its own disconnect diagnostic
  were redacted. Core 0.9.6 still logs raw child stderr in its OTP crash report.
  `ProtocolSession.channel_exit_stop_reason/1` uses the raw process exit as an
  abnormal termination reason. Its JSON-RPC facade has no stderr redaction hook
  before that report. This blocks release validation of real Bedrock access keys
  over stdio and needs a Core fix.
- Remote deployment, gateway writes, AWS mutations, hosted MCP OAuth and
  environment selectors, SSH, and main-only behavior require
  operator-provided endpoints, credentials, or builds.
- Lazy MCP startup and cache behavior, queued child replies, connected-app
  reviewer enforcement, and resume restoration are CLI responsibilities.
  Python logical goal orchestration and full realtime, approval, subagent,
  structured input, and typed error coverage remain open.

### Verification commands

Run from the SDK checkout with the locked dependencies.

```sh
mix deps.get
mix deps
mix compile --warnings-as-errors
MIX_ENV=test mix compile --warnings-as-errors
mix format
mix format --check-formatted
mix test test/codex/app_server/{api,account_bedrock,mcp,notification_adapter,remote_connection}_test.exs \
  test/codex/{runtime_exec_render,exec,thread}_test.exs --seed 0 --trace
mix test test/codex/app_server_transport_test.exs test/codex/runtime/exec_test.exs --seed 0 --trace
mix test --seed 0 --trace
mix test
MIX_ENV=test mix credo --strict
MIX_ENV=dev mix dialyzer --plt
MIX_ENV=dev mix dialyzer
mix docs
mix coveralls
mix coveralls.detail
bash scripts/atom_guard.sh
bash scripts/secrets_guard.sh
bash -n examples/run_all.sh
bash -n scripts/atom_guard.sh
bash -n scripts/secrets_guard.sh
git diff --check
```

The targeted runs passed 243 and 36 tests. The full suite reported 1,581 tests
with zero failures, four skipped, and 16 excluded. The remote connection,
stdio transport, runtime exec, error, and session race subset passed 56 tests
at each of seeds 1, 42, and 172. Dialyzer found zero errors and reused a matching
PLT. Generated HTML linked to all three inventory files, which matched the
tracked TSVs byte for byte. Coverage was 66.8%, up from 66.1% on the clean
0.21.6 baseline worktree with the same locked dependencies.

Live commands used `~/scripts/with_bash_secrets` with private temporary
`CODEX_HOME` and disposable Git project directories. State changes were scoped
to disposable threads, goals, and local fixture configuration.

```sh
~/scripts/with_bash_secrets codex --version
~/scripts/with_bash_secrets mix run examples/live_parity_0172.exs --cwd "$DISPOSABLE_PROJECT"
CODEX_PARITY_BEDROCK_DISCOVERY=1 \
  ~/scripts/with_bash_secrets mix run examples/live_parity_0172.exs
CODEX_PARITY_HISTORY=1 \
  ~/scripts/with_bash_secrets mix run examples/live_parity_0172.exs --cwd "$DISPOSABLE_PROJECT"
CODEX_PARITY_HISTORY=1 CODEX_PARITY_GOALS=1 \
  ~/scripts/with_bash_secrets mix run examples/live_parity_0172.exs --cwd "$DISPOSABLE_PROJECT"
~/scripts/with_bash_secrets mix run examples/live_remote_parity_0172.exs --cwd "$DISPOSABLE_PROJECT"
```

Stable CLI parsing rejected `--full-auto` and `--continuation-token` with
exit 2. A local parse-only remote smoke used `ws://127.0.0.1:1` and a synthetic
token variable. The CLI returned exit 1 for both missing and empty values
before reaching an endpoint. The Bedrock login policy probe used synthetic
keys and confirmed forced ChatGPT mode and governed authority reject login
before sending an RPC.


```sh
CODEX_EXAMPLES_TIMEOUT_SECONDS=20 \
  ~/scripts/with_bash_secrets bash examples/run_all.sh --cwd "$DISPOSABLE_PROJECT"
CODEX_EXAMPLES_TIMEOUT_SECONDS=20 CODEX_PARITY_HISTORY=1 CODEX_PARITY_GOALS=1 \
  ~/scripts/with_bash_secrets bash examples/run_all.sh --cwd "$DISPOSABLE_PROJECT"
```

Both run-all invocations exited 1 after starting 46 demos each. The default
run recorded 18 nonzero exits, 4 timeouts, and 11 explicit skip messages.
The opt-in run recorded 16 nonzero exits, 4 timeouts, and 9 explicit skip
messages. The shared timeouts were the web search modes, config overrides,
personality, and approvals demos. Repeated Responses WebSocket connection
failures and HTTP 401 responses blocked model-backed checks. The speech
examples returned HTTP 401 with an invalidated API key. The standalone
Realtime voice example reported upstream `server_error` and skipped. Some
examples returned exit 0 after reporting an error or a skip. None established
an authenticated model-backed run. The remote example explicitly skipped
because no authorized endpoint was supplied.
