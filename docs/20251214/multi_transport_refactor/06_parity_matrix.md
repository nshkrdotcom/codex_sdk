# Parity Matrix (Upstream vs `codex_sdk`)

This matrix focuses on *reachable* upstream functionality via either:

- `codex exec` JSONL output (`--experimental-json` in `codex_sdk` today)
- `codex app-server` (JSON-RPC over stdio)

Some functionality exists only in the interactive TUI (core-linked) and is not currently exposed via app-server.

## Transport-level parity

| Capability | Exec JSONL | App-Server | TUI/Core | `codex_sdk` today | Plan |
|---|---:|---:|---:|---:|---|
| Run a turn from text | ✅ | ✅ | ✅ | ✅ | Keep (exec) + add (app-server) |
| Stream per-item progress | ✅ | ✅ | ✅ | ✅ | Add app-server mapping |
| Turn diff updates | ❌ | ✅ (`turn/diff/updated`) | ✅ | ❌ | Map to `%Codex.Events.TurnDiffUpdated{diff: String.t()}` |
| Resume thread by id | ✅ (via CLI args) | ✅ (`thread/resume`) | ✅ | ✅ | Keep + add first-class app-server |
| Interrupt a running turn | ⚠️ (process kill) | ✅ (`turn/interrupt`) | ✅ | ⚠️ | Implement app-server interrupt |
| List threads / history UI | ❌ | ✅ (`thread/list`) | ✅ | ❌ | Implement app-server method |
| Archive thread | ❌ | ✅ (`thread/archive`) | ✅ | ❌ | Implement app-server method |
| Compact thread context | ❌ | ✅ (`thread/compact`) | ✅ | ❌ | Implement app-server method |
| List models | ❌ | ✅ (`model/list`) | ✅ | ❌ | Implement app-server method; optionally keep static defaults |
| Read/write config | ❌ | ✅ (`config/*`) | ✅ | ❌ | Implement app-server config client |
| One-off sandboxed command exec | ❌ | ✅ (`command/exec`) | ✅ | ❌ | Implement app-server method |
| Approval requests (server→client) | ❌ (not interactive) | ✅ (`item/*/requestApproval`) | ✅ | ⚠️ (SDK-local tools only) | Implement app-server approval handling |
| Skills list | ❌ | ✅ (`skills/list`) | ✅ | ❌ | Implement app-server method |
| Skill selection as input | ❌ | ❌ (today) | ✅ | ❌ | Blocked: upstream must expose `UserInput::Skill` in app-server or SDK emulates |
| Review start | ❌ | ✅ (`review/start`) | ✅ | ❌ | Implement app-server method |
| Account login/logout/rate limits | ❌ | ✅ (`account/*`) | ✅ | ❌ | Implement app-server method set |
| MCP servers list / OAuth login | ❌ | ✅ (`mcpServers/list`, `mcpServer/oauth/login`) | ✅ | ❌ | Implement app-server method set |

Legend:
- ✅ supported
- ⚠️ partial / workaround
- ❌ not supported

## Concrete blockers

### `UserInput::Skill` is core-only for now

- Core protocol includes `UserInput::Skill` (`codex/codex-rs/protocol/src/user_input.rs:25-29`).
- App-server v2 input union does not (`codex/codex-rs/app-server-protocol/src/protocol/v2.rs:1289-1293`).
- The conversion explicitly treats extra variants as unreachable (`codex/codex-rs/app-server-protocol/src/protocol/v2.rs:1311`).

So **no external client** (exec JSONL, app-server, TS SDK) can send a skill selection input today.

### Upstream TS SDK scope

The upstream TypeScript SDK (`codex/sdk/typescript/src/thread.ts:28-36`) only supports:
- `type: "text"` (text prompt)
- `type: "local_image"` (local image path)

It does NOT use app-server, only `codex exec`. This means `codex_sdk` achieving "TS SDK parity" is already done for exec transport.

## See Also

For detailed method-by-method implementation planning, see:
- `10_protocol_mapping_spec.md` - Complete protocol mapping with Elixir API names
- `09_requirements_and_nongoals.md` - Explicit parity definitions and scope
