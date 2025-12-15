# Requirements & Non-Goals

This document provides an unambiguous definition of "feature parity" and explicitly scopes what is in and out of scope for the multi-transport refactor.

## Parity Definitions

### Definition 1: Exec JSONL Surface Parity

**Goal**: `codex_sdk` with exec transport produces the same behavior as the upstream TypeScript SDK.

**Upstream reference**: `codex/sdk/typescript/src/thread.ts:28-36`

The upstream TS SDK supports only:
- `type: "text"` (text prompt)
- `type: "local_image"` (local image path)

The TS SDK does NOT support:
- `UserInput::Skill` (not exposed)
- App-server RPC methods (uses exec only)

**Elixir current state**: Already at parity. `codex_sdk` uses the exec JSONL surface (`codex exec --experimental-json` today) and supports text + local images via `Codex.Exec`.

### Definition 2: App-Server Surface Parity

**Goal**: `codex_sdk` with app-server transport can invoke all v2 client request methods and handle all server notifications/requests defined in the protocol.

**Upstream reference**: `codex/codex-rs/app-server-protocol/src/protocol/common.rs:96-299`

This includes:
- Thread lifecycle: `thread/start`, `thread/resume`, `thread/list`, `thread/archive`, `thread/compact`
- Turns: `turn/start`, `turn/interrupt`
- Skills: `skills/list`
- Models: `model/list`
- Config: `config/read`, `config/value/write`, `config/batchWrite`
- Review: `review/start`
- One-off command: `command/exec`
- Account/auth: `account/login/start`, `account/login/cancel`, `account/logout`, `account/read`, `account/rateLimits/read`
- MCP: `mcpServers/list`, `mcpServer/oauth/login`
- Feedback: `feedback/upload`

And handling:
- All v2 server notifications (see `codex/codex-rs/app-server-protocol/src/protocol/common.rs:521-559`)
- All v2 server requests (approvals) (see `codex/codex-rs/app-server-protocol/src/protocol/common.rs:465-494`)

### Definition 3: Core-Only Features (TUI-Only)

**These are NOT achievable via any external transport today**:

| Feature | Evidence | Status |
|---------|----------|--------|
| `UserInput::Skill` selection | `codex/codex-rs/app-server-protocol/src/protocol/v2.rs:1289-1293` defines UserInput with only Text/Image/LocalImage; `codex/codex-rs/app-server-protocol/src/protocol/v2.rs:1311` treats other variants as `unreachable!()` | **Blocked upstream** |

The TUI constructs `UserInput::Skill` in-process (`codex/codex-rs/tui/src/chatwidget.rs:1754-1758`) and core processes it (`codex/codex-rs/core/src/skills/injection.rs:69`), but this path is not exposed to external clients.

## Requirements (MUST)

### R1: Transport Abstraction

- `codex_sdk` MUST support both exec and app-server transports
- Transport MUST be selectable per-thread (default: exec for backwards compatibility)
- Transport behavior MUST NOT leak into the public API beyond transport selection

### R2: App-Server Connection Lifecycle

- MUST implement the initialize/initialized handshake
  - Evidence: `codex/codex-rs/app-server/README.md:39-47`
- MUST handle all 4 message shapes:
  1. Client request (client → server): `{ "id": N, "method": "...", "params": {...} }`
  2. Server response (server → client): `{ "id": N, "result": {...} }` or `{ "id": N, "error": {...} }`
  3. Server notification (server → client, no id): `{ "method": "...", "params": {...} }`
  4. Server request (server → client, requires response): `{ "id": N, "method": "...", "params": {...} }`
  - Evidence: `codex/codex-rs/app-server-protocol/src/jsonrpc_lite.rs:21-71`
- MUST correlate responses to in-flight requests by `id`
- MUST handle interleaved notifications while requests are pending

### R3: Approval Handling

- MUST handle server requests for approvals:
  - `item/commandExecution/requestApproval` (`codex/codex-rs/app-server-protocol/src/protocol/common.rs:469-472`)
  - `item/fileChange/requestApproval` (`codex/codex-rs/app-server-protocol/src/protocol/common.rs:476-479`)
- MUST integrate with existing `Codex.Approvals.Hook` callbacks
- MUST respond with `ApprovalDecision` enum values:
  - `Accept`, `AcceptForSession`, `AcceptWithExecpolicyAmendment`, `Decline`, `Cancel`
  - Evidence: `codex/codex-rs/app-server-protocol/src/protocol/v2.rs:402-414`
  - Note: supporting `AcceptForSession` / `AcceptWithExecpolicyAmendment` likely requires a backwards-compatible extension to `Codex.Approvals.Hook` decision return values (or an explicit manual-approval API), since the current hook decision surface is primarily allow/deny.

### R4: Event Normalization

- App-server notifications MUST be surfaced **losslessly** to Elixir consumers (at minimum: `{method, params}`).
- For a defined “core” subset of notifications (P0/P1), notifications MUST be mapped into typed `Codex.Events` structs for ergonomic pattern matching.
- Unknown/unhandled notification methods MUST NOT crash the connection process; they MUST be forwarded as a raw notification event (forward compatibility).
- Where app-server provides strictly more information than exec, either:
  - extend `Codex.Events`/`Codex.Items` to carry the extra fields, or
  - preserve the extra payload under a `raw` field alongside normalized common fields.
- ThreadItem unions (camelCase in app-server) MUST normalize to `Codex.Items` structs (snake_case) when possible; unknown item types MUST be preserved as raw.
- `turn/diff/updated` MUST treat `diff` as a unified diff string (`codex/codex-rs/app-server-protocol/src/protocol/v2.rs:1524-1530`).

### R5: Skills Discovery

- MUST implement `skills/list` once app-server transport exists
- Types: `SkillsListParams`, `SkillsListResponse`, `SkillMetadata`, `SkillScope`, `SkillErrorInfo`
  - Evidence: `codex/codex-rs/app-server-protocol/src/protocol/v2.rs:976-1030`

### R6: Backwards Compatibility

- Default transport MUST remain exec
- Existing `Codex.Thread` public API MUST continue to work unchanged
- New app-server capabilities MUST be opt-in

## Non-Goals (MUST NOT / WILL NOT)

### NG1: v1 Deprecated API Support

The following deprecated v1 methods (`codex/codex-rs/app-server-protocol/src/protocol/common.rs:205-299`) are explicitly OUT OF SCOPE:
- `newConversation`, `sendUserMessage`, `sendUserTurn`
- `getConversationSummary`, `listConversations`, `resumeConversation`, `archiveConversation`
- `interruptConversation`
- Legacy auth: `loginApiKey`, `loginChatGpt`, `cancelLoginChatGpt`, `logoutChatGpt`, `getAuthStatus`
- `applyPatchApproval`, `execCommandApproval` (v1 approval requests)

Rationale: v2 provides equivalent functionality with cleaner semantics. v1 exists only for legacy client compatibility.

### NG2: `UserInput::Skill` Wire Protocol Exposure

Until upstream adds `Skill` to the app-server `UserInput` enum (`codex/codex-rs/app-server-protocol/src/protocol/v2.rs:1289`), `codex_sdk` WILL NOT:
- Claim to support skill selection as a first-class input
- Attempt to hack around the protocol limitation in ways that break if upstream changes

### NG3: Modifying Upstream `codex/`

The `codex/` directory is treated as a third-party dependency. No modifications.

### NG4: TUI Feature Parity

Features that exist only in the TUI (in-process core access) are not targets for this refactor unless upstream exposes them via app-server.

## Nice-to-Have (MAY)

### NH1: SDK-Level Skill Emulation

`codex_sdk` MAY implement an emulation path for skill selection:
- Read the `SKILL.md` file content
- Inject it as part of the prompt text or system instructions

This provides behavioral parity (the skill content reaches the model) but NOT protocol parity (the upstream wouldn't see it as a `UserInput::Skill`).

**Tradeoffs**:
- Pro: Users get skill functionality without waiting for upstream
- Con: Injection semantics may differ from core's `build_skill_injections` (`codex/codex-rs/core/src/skills/injection.rs:16-59`)
- Con: Cannot leverage any future upstream skill-specific handling

Decision: Implement as opt-in, clearly documented as "emulation mode".

### NH2: MCP and Account Endpoints

MCP server management and account/auth flows are lower priority than core thread/turn/skills functionality. MAY defer to a later phase.

## Success Criteria

1. All existing exec-based tests continue to pass
2. A new test suite demonstrates:
   - App-server connection lifecycle (init → ready → shutdown)
   - Thread start/resume/list/archive/compact via app-server
   - Turn execution with streaming events
   - Approval request handling (accept/decline flows)
   - `skills/list` returning skill metadata
3. Documentation clearly states what is achievable via each transport
4. Breaking changes (if any) are documented with migration path
