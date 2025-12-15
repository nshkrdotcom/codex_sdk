# Phased Implementation Plan (Major Refactor)

This plan assumes we want `codex_sdk` to support:

- exec JSONL parity (keep as default)
- app-server parity (add second transport)

And then port the new upstream skills/list functionality (2025-12-14 pull) via app-server.

## Phase 0 — Transport abstraction (refactor only)

Goal: make `Codex.Thread` transport-agnostic while keeping exec as default.

Deliverables:
- Introduce a transport behaviour (`Codex.Transport`).
- Refactor `Codex.Thread` to delegate `run_turn/3` + `run_turn_streamed/3` to the configured transport instead of calling `Codex.Exec` directly (today: `lib/codex/thread.ex:107`).
- Implement `Codex.Transport.ExecJsonl` by wrapping existing `Codex.Exec`.

Exit criteria:
- All existing tests pass with the exec transport as default.

## Phase 1 — App-server connection (handshake + minimal RPC)

Goal: establish a stable JSON-RPC connection to `codex app-server`.

Deliverables:
- `Codex.AppServer.Connection` GenServer:
  - spawns `codex app-server`
  - performs initialize/initialized handshake (docs: `codex/codex-rs/app-server/README.md:39`)
  - implements request id correlation and response routing
- Minimal methods:
  - `thread/start`
  - `turn/start`
  - stream notifications until `turn/completed`

Exit criteria:
- A basic integration test can start a thread and complete a turn over app-server.

## Phase 2 — Event + item normalization layer

Goal: map app-server notifications into canonical `Codex.Events` and `Codex.Items`.

Deliverables:
- A notification adapter that converts `{method, params}` into `%Codex.Events{}` via `Codex.Events.parse!/1`.
- An item adapter that converts app-server v2 `ThreadItem` unions (camelCase) into `Codex.Items` structs (snake_case) via `Codex.Items.parse!/1`.
- Raw passthrough for unknown notification/item types (do not crash on schema drift).
- Explicitly handle:
  - `turn/diff/updated` (`diff` is a unified diff string: `codex/codex-rs/app-server-protocol/src/protocol/v2.rs:1524-1530`)
  - `turn/plan/updated` (`codex/codex-rs/app-server-protocol/src/protocol/v2.rs:1535-1540`)

Exit criteria:
- `run_turn_streamed/3` yields the same high-level event categories for both exec and app-server.

## Phase 3 — Approvals (server requests → Hook)

Goal: handle server-initiated approval requests so turns can proceed.

Deliverables:
- Decode server requests:
  - `item/commandExecution/requestApproval`
  - `item/fileChange/requestApproval`
  (registry: `codex/codex-rs/app-server-protocol/src/protocol/common.rs:465`)
- Route to `Codex.Approvals.Hook.review_command/3` and `review_file/3` (see `lib/codex/approvals/hook.ex:94`).
- Send JSON-RPC responses using `ApprovalDecision` (`codex/codex-rs/app-server-protocol/src/protocol/v2.rs:402-414`).
- Support the full decision surface for command execution approvals:
  - `AcceptForSession` (cached by core for the session) (`codex/codex-rs/app-server/src/bespoke_event_handling.rs:1136-1139`, `codex/codex-rs/core/src/tools/sandboxing.rs:52-77`)
  - `AcceptWithExecpolicyAmendment` (persists to execpolicy) (`codex/codex-rs/core/src/codex.rs:1767-1792`)
- Provide a manual response path for interactive UIs (subscribe + `Codex.AppServer.respond/3`), in addition to hook-based auto-approval.

Exit criteria:
- Turns that require approvals succeed under configured policy/hook.

## Phase 4 — App-server feature surface (skills/models/config/threads/review/account)

Goal: implement the remaining v2 app-server requests for parity.

Deliverables:
- `skills/list` + types (new pull):
  - method registry: `codex/codex-rs/app-server-protocol/src/protocol/common.rs:124`
  - types: `codex/codex-rs/app-server-protocol/src/protocol/v2.rs:976`
- `model/list`
- `config/read`, `config/value/write`, `config/batchWrite`
- `thread/list`, `thread/archive`, `thread/compact`
- `review/start`
- account endpoints + MCP OAuth endpoints (as-needed)

Exit criteria:
- All v2 app-server methods are available via Elixir APIs.

## Phase 5 — Close remaining “core-only” gaps (optional / upstream-dependent)

### `UserInput::Skill`

Blocked by upstream app-server protocol missing the variant:
- core has it: `codex/codex-rs/protocol/src/user_input.rs:25`
- app-server v2 does not: `codex/codex-rs/app-server-protocol/src/protocol/v2.rs:1289`

Options:
- Upstream change to app-server protocol (preferred for true parity)
- SDK emulation by reading skill bodies and injecting as text (behavioral parity, not protocol parity)
