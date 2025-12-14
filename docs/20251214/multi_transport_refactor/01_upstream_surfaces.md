# Upstream Codex Surfaces (TUI vs Exec vs App-Server)

Upstream `codex` (Rust) is one binary with multiple “surfaces” that matter for SDK parity:

1. **Interactive TUI** (in-process, uses core protocol types directly)
2. **Non-interactive Exec** (`codex exec --json` JSONL stream; one-shot)
3. **Stateful App-Server** (`codex app-server` JSON-RPC over stdio; long-lived)

This distinction is why some upstream features are *impossible* to reach from `codex exec --json` and require an app-server transport in `codex_sdk`.

## 1) Interactive TUI (in-process)

The TUI (`codex-rs/tui` and `codex-rs/tui2`) links the core crates and can use any core protocol variant directly.

Example: the TUI constructs `UserInput::Skill` values (see `codex/codex-rs/tui/src/chatwidget.rs:1754`) and submits them as part of `Op::UserInput` (see `codex/codex-rs/tui/src/chatwidget.rs:1761`).

## 2) Exec JSONL (one-shot, stdout only)

`codex exec` emits a newline-delimited JSON event stream. The event schema lives in `codex/codex-rs/exec/src/exec_events.rs:7`.

This surface is intentionally narrow: it does **not** expose “RPC” endpoints like `skills/list`, `model/list`, `config/read`, etc.

## 3) App-Server (JSON-RPC over stdio; stateful)

`codex app-server` is a long-lived subprocess that speaks JSON-RPC-like messages over stdin/stdout.

Upstream docs: `codex/codex-rs/app-server/README.md:17` describes the protocol (“JSON-RPC 2.0, though the `\"jsonrpc\":\"2.0\"` header is omitted”) and the initialization handshake (see `codex/codex-rs/app-server/README.md:39`).

The authoritative method registry is in `codex/codex-rs/app-server-protocol/src/protocol/common.rs:96`:
- Client requests (including v2 methods like `thread/start`, `turn/start`, `skills/list`, …)
- Server notifications (streaming events like `item/agentMessage/delta`, `turn/completed`, …)
- Server requests (approvals) like `item/commandExecution/requestApproval`

## What “SDKs” do upstream

### TypeScript SDK in `./codex`

Upstream `codex` only includes a **TypeScript** SDK in `codex/sdk/typescript`.

It shells out to `codex exec` and normalizes input into prompt + local images. The `UserInput` union is only `text` and `local_image` (see `codex/sdk/typescript/src/thread.ts:28`).

So: **the upstream TS SDK does not support `UserInput::Skill`.**

### “Python SDK” in `./codex`

There is **no Python codex SDK** under `./codex` in this checkout; only TypeScript exists under `codex/sdk/`.

### `./openai-agents-python`

`openai-agents-python` is a separate Agents framework that talks to the OpenAI APIs; it is not a wrapper around the `codex` CLI/runtime.

Evidence: `openai-agents-python/README.md:3` (“supports the OpenAI Responses and Chat Completions APIs”).

So: **it does not support Codex core protocol types like `UserInput::Skill` either.**

