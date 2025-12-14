# Current `codex_sdk` State (Why Exec JSONL Isn’t Enough)

## What transport `codex_sdk` uses today

`codex_sdk` runs the upstream `codex` binary in **exec JSONL mode** via erlexec:

- `lib/codex/exec.ex:228` builds args starting with `["exec", "--experimental-json"]`
- `lib/codex/thread.ex:107` calls `Codex.Exec.run/2` for each turn

This is a **one-shot** workflow:
- spawn process
- write prompt to stdin
- read JSONL events from stdout
- process exits

It is not a bidirectional, stateful RPC channel.

## Why this transport cannot expose `skills/list` / app-server APIs

The upstream `skills/list` operation is an **app-server JSON-RPC method**, registered here:

- `codex/codex-rs/app-server-protocol/src/protocol/common.rs:124`

`codex exec` JSONL output has no general “send request / receive response” mechanism for these app-server methods. It only runs a turn and streams turn events.

So the transport isn’t “broken”; it’s just a different upstream surface.

## What this means for feature parity

If “feature parity with upstream codex” includes **app-server capabilities** like:
- `thread/list`, `thread/archive`, `thread/compact`
- `model/list`
- `config/read` + `config/*write`
- `skills/list`
- approvals via server→client JSON-RPC requests

…then `codex_sdk` needs a second transport that speaks app-server JSON-RPC.

This aligns with upstream’s own division:
- The TypeScript SDK in `./codex` also wraps exec-only and does not expose skills/app-server APIs (see `codex/sdk/typescript/src/thread.ts:28`).
