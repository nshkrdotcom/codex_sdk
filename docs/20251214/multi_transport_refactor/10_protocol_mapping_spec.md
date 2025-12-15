# Protocol Mapping Specification

This document provides a complete method-by-method mapping from app-server protocol to Elixir implementation.

## Message Framing

**Upstream evidence**: `codex/codex-rs/app-server/README.md:17`

- Newline-delimited JSON objects over stdio
- `"jsonrpc":"2.0"` header is OMITTED (unlike standard JSON-RPC 2.0)
- No explicit Content-Length framing (unlike LSP)

### Implementation Requirements

1. **Line buffering**: Accumulate stdin/stdout until newline, then parse as JSON
2. **Partial line handling**: Buffer incomplete lines across `read()` calls
3. **No assumptions about message boundaries**: A single `read()` may contain multiple messages or partial messages

### Elixir Implementation Notes

```elixir
# Pseudocode for line buffering
defp decode_lines(buffer) do
  case String.split(buffer, "\n", parts: 2) do
    [complete, rest] ->
      {:ok, Jason.decode!(complete), rest}
    [incomplete] ->
      {:incomplete, incomplete}
  end
end
```

---

## Client Requests (Client → Server)

**Upstream evidence**: `codex/codex-rs/app-server-protocol/src/protocol/common.rs:96-203` (v2 request registry)

### Must Implement (Core Parity)

| Wire Method | Rust Variant | Params Type | Response Type | Elixir API | Priority |
|-------------|--------------|-------------|---------------|------------|----------|
| `initialize` | `Initialize` | `v1::InitializeParams` | `v1::InitializeResponse` | `Codex.AppServer.Connection.init/2` | P0 |
| `thread/start` | `ThreadStart` | `v2::ThreadStartParams` | `v2::ThreadStartResponse` | `Codex.AppServer.thread_start/2` | P0 |
| `thread/resume` | `ThreadResume` | `v2::ThreadResumeParams` | `v2::ThreadResumeResponse` | `Codex.AppServer.thread_resume/2` | P0 |
| `turn/start` | `TurnStart` | `v2::TurnStartParams` | `v2::TurnStartResponse` | `Codex.AppServer.turn_start/3` | P0 |
| `turn/interrupt` | `TurnInterrupt` | `v2::TurnInterruptParams` | `v2::TurnInterruptResponse` | `Codex.AppServer.turn_interrupt/3` | P1 |
| `thread/list` | `ThreadList` | `v2::ThreadListParams` | `v2::ThreadListResponse` | `Codex.AppServer.thread_list/2` | P1 |
| `thread/archive` | `ThreadArchive` | `v2::ThreadArchiveParams` | `v2::ThreadArchiveResponse` | `Codex.AppServer.thread_archive/2` | P2 |
| `thread/compact` | `ThreadCompact` | `v2::ThreadCompactParams` | `v2::ThreadCompactResponse` | `Codex.AppServer.thread_compact/2` | P2 |
| `skills/list` | `SkillsList` | `v2::SkillsListParams` | `v2::SkillsListResponse` | `Codex.AppServer.skills_list/2` | P1 |
| `model/list` | `ModelList` | `v2::ModelListParams` | `v2::ModelListResponse` | `Codex.AppServer.model_list/1` | P2 |
| `config/read` | `ConfigRead` | `v2::ConfigReadParams` | `v2::ConfigReadResponse` | `Codex.AppServer.config_read/2` | P2 |
| `config/value/write` | `ConfigValueWrite` | `v2::ConfigValueWriteParams` | `v2::ConfigWriteResponse` | `Codex.AppServer.config_write/3` | P3 |
| `config/batchWrite` | `ConfigBatchWrite` | `v2::ConfigBatchWriteParams` | `v2::ConfigWriteResponse` | `Codex.AppServer.config_batch_write/2` | P3 |
| `review/start` | `ReviewStart` | `v2::ReviewStartParams` | `v2::ReviewStartResponse` | `Codex.AppServer.review_start/3` | P2 |
| `command/exec` | `OneOffCommandExec` | `v2::CommandExecParams` | `v2::CommandExecResponse` | `Codex.AppServer.command_exec/3` | P2 |

### May Implement (Extended Functionality)

| Wire Method | Rust Variant | Params Type | Response Type | Elixir API | Priority |
|-------------|--------------|-------------|---------------|------------|----------|
| `account/login/start` | `LoginAccount` | `v2::LoginAccountParams` | `v2::LoginAccountResponse` | `Codex.AppServer.Account.login_start/2` | P3 |
| `account/login/cancel` | `CancelLoginAccount` | `v2::CancelLoginAccountParams` | `v2::CancelLoginAccountResponse` | `Codex.AppServer.Account.login_cancel/2` | P3 |
| `account/logout` | `LogoutAccount` | `Option<()>` | `v2::LogoutAccountResponse` | `Codex.AppServer.Account.logout/1` | P3 |
| `account/read` | `GetAccount` | `v2::GetAccountParams` | `v2::GetAccountResponse` | `Codex.AppServer.Account.read/2` | P3 |
| `account/rateLimits/read` | `GetAccountRateLimits` | `Option<()>` | `v2::GetAccountRateLimitsResponse` | `Codex.AppServer.Account.rate_limits/1` | P3 |
| `mcpServers/list` | `McpServersList` | `v2::ListMcpServersParams` | `v2::ListMcpServersResponse` | `Codex.AppServer.Mcp.list_servers/2` | P3 |
| `mcpServer/oauth/login` | `McpServerOauthLogin` | `v2::McpServerOauthLoginParams` | `v2::McpServerOauthLoginResponse` | `Codex.AppServer.Mcp.oauth_login/2` | P3 |
| `feedback/upload` | `FeedbackUpload` | `v2::FeedbackUploadParams` | `v2::FeedbackUploadResponse` | `Codex.AppServer.feedback_upload/2` | P3 |

### Will NOT Implement (Deprecated v1)

Deprecated v1 request methods are explicitly out of scope (see `docs/20251214/multi_transport_refactor/09_requirements_and_nongoals.md`).

| Wire Method | Reason |
|-------------|--------|
| `newConversation` | Use `thread/start` |
| `sendUserMessage` | Use `turn/start` |
| `sendUserTurn` | Use `turn/start` |
| `getConversationSummary` | Deprecated |
| `listConversations` | Use `thread/list` |
| `resumeConversation` | Use `thread/resume` |
| `archiveConversation` | Use `thread/archive` |
| `interruptConversation` | Use `turn/interrupt` |
| `loginApiKey` | Use `account/login/start` |
| `loginChatGpt` | Use `account/login/start` |
| `cancelLoginChatGpt` | Use `account/login/cancel` |
| `logoutChatGpt` | Use `account/logout` |
| `getAuthStatus` | Use `account/read` |
| All other v1 methods | Registry: `codex/codex-rs/app-server-protocol/src/protocol/common.rs:205-299` |

---

## Client Notifications (Client → Server)

**Upstream evidence**: `codex/codex-rs/app-server-protocol/src/protocol/common.rs:561-563`

| Wire Method | Description | When to Send |
|-------------|-------------|--------------|
| `initialized` | Signal handshake complete | After `initialize` response received |

### Implementation

```elixir
# After receiving initialize response
def send_initialized(conn) do
  send_notification(conn, "initialized")
end
```

---

## Server Notifications (Server → Client)

**Upstream evidence**: `codex/codex-rs/app-server-protocol/src/protocol/common.rs:521-559`

### Event Mapping Table

| Wire Method | Rust Variant | Params Type | Elixir Event | Mapping Notes |
|-------------|--------------|-------------|--------------|---------------|
| `error` | `Error` | `v2::ErrorNotification` | `%Codex.Events.Error{}` | Map `error.message` → `message`; consider extending event with `will_retry` (`codex/codex-rs/app-server-protocol/src/protocol/v2.rs:1170-1179`) |
| `thread/started` | `ThreadStarted` | `v2::ThreadStartedNotification` | `%Codex.Events.ThreadStarted{}` | `thread.id` → `thread_id`; store remaining thread fields in `metadata` |
| `thread/tokenUsage/updated` | `ThreadTokenUsageUpdated` | `v2::ThreadTokenUsageUpdatedNotification` | `%Codex.Events.ThreadTokenUsageUpdated{}` | Needs app-server adapter: `tokenUsage` snapshot (`codex/codex-rs/app-server-protocol/src/protocol/v2.rs:1092-1106`) → `usage`/`token_usage` (`lib/codex/events.ex:369-376`) |
| `thread/compacted` | `ContextCompacted` | `v2::ContextCompactedNotification` | `%Codex.Events.TurnCompaction{stage: :completed}` | Compatibility shim: map `thread/compacted` (`codex/codex-rs/app-server-protocol/src/protocol/v2.rs:1706-1709`) → `TurnCompaction` with empty `compaction` |
| `turn/started` | `TurnStarted` | `v2::TurnStartedNotification` | `%Codex.Events.TurnStarted{}` | `threadId`/`turn.id` → `thread_id`/`turn_id` |
| `turn/completed` | `TurnCompleted` | `v2::TurnCompletedNotification` | `%Codex.Events.TurnCompleted{}` | `turn.status` only; `turn.items` is `[]` except in `thread/resume` (`codex/codex-rs/app-server-protocol/src/protocol/v2.rs:1151-1154`), so compute `final_response` from `item/*` stream and attach usage from latest `thread/tokenUsage/updated` |
| `turn/diff/updated` | `TurnDiffUpdated` | `v2::TurnDiffUpdatedNotification` | `%Codex.Events.TurnDiffUpdated{}` | App-server `diff` is a unified diff string (`codex/codex-rs/app-server-protocol/src/protocol/v2.rs:1524-1530`); update `%Codex.Events.TurnDiffUpdated{diff: String.t()}` (or a backwards-compatible union) |
| `turn/plan/updated` | `TurnPlanUpdated` | `v2::TurnPlanUpdatedNotification` | **NEW: `%Codex.Events.TurnPlanUpdated{}`** | New event type needed |
| `item/started` | `ItemStarted` | `v2::ItemStartedNotification` | `%Codex.Events.ItemStarted{}` | Normalize `item` via Items adapter |
| `item/completed` | `ItemCompleted` | `v2::ItemCompletedNotification` | `%Codex.Events.ItemCompleted{}` | Normalize `item` via Items adapter |
| `item/agentMessage/delta` | `AgentMessageDelta` | `v2::AgentMessageDeltaNotification` | `%Codex.Events.ItemAgentMessageDelta{}` | Map delta fields |
| `item/reasoning/textDelta` | `ReasoningTextDelta` | `v2::ReasoningTextDeltaNotification` | **NEW or raw** | Reasoning delta event |
| `item/reasoning/summaryTextDelta` | `ReasoningSummaryTextDelta` | `v2::ReasoningSummaryTextDeltaNotification` | **NEW or raw** | Summary delta event |
| `item/reasoning/summaryPartAdded` | `ReasoningSummaryPartAdded` | `v2::ReasoningSummaryPartAddedNotification` | **NEW or raw** | Summary boundary event |
| `item/commandExecution/outputDelta` | `CommandExecutionOutputDelta` | `v2::CommandExecutionOutputDeltaNotification` | **NEW or raw** | Command output streaming |
| `item/commandExecution/terminalInteraction` | `TerminalInteraction` | `v2::TerminalInteractionNotification` | **NEW or raw** | PTY interaction event |
| `item/fileChange/outputDelta` | `FileChangeOutputDelta` | `v2::FileChangeOutputDeltaNotification` | **NEW or raw** | File change streaming |
| `item/mcpToolCall/progress` | `McpToolCallProgress` | `v2::McpToolCallProgressNotification` | **NEW or raw** | MCP progress event |
| `mcpServer/oauthLogin/completed` | `McpServerOauthLoginCompleted` | `v2::McpServerOauthLoginCompletedNotification` | **NEW or raw** | MCP auth completion |
| `account/updated` | `AccountUpdated` | `v2::AccountUpdatedNotification` | **NEW or raw** | Auth state change |
| `account/rateLimits/updated` | `AccountRateLimitsUpdated` | `v2::AccountRateLimitsUpdatedNotification` | **NEW or raw** | Rate limit update |
| `account/login/completed` | `AccountLoginCompleted` | `v2::AccountLoginCompletedNotification` | **NEW or raw** | Login completion |
| `windows/worldWritableWarning` | `WindowsWorldWritableWarning` | `v2::WindowsWorldWritableWarningNotification` | **Ignore or log** | Windows-specific |

### Normalization Strategy

All app-server notifications arrive as JSON-RPC envelopes:

```json
{"method":"turn/started","params":{...}}
```

To reuse `Codex.Events.parse!/1`, implement a notification adapter that:

1. Maps `method` → internal `"type"` string (either keep the slash form or remap to the existing dot+snake_case form)
2. Converts param keys from camelCase → snake_case (`threadId` → `thread_id`, etc.)
3. Normalizes nested `ThreadItem` payloads into `Codex.Items`-compatible maps/structs

**Option A: Extend `Codex.Events`** (Recommended for P0 events)
- Add new event structs for `TurnPlanUpdated`, reasoning deltas, command output deltas
- Maintains type safety and pattern matching

**Option B: Preserve as raw notifications** (Required for forward compatibility)
- Always preserve unknown/unhandled methods as raw (do not crash on drift).
- Emit raw notifications as `{:codex_notification, method, params}` (subscription API) and/or as a dedicated `Codex.Events` wrapper struct on the streamed events API.
- Consumers can pattern match on method string while waiting for typed support.

**Recommended hybrid**:
- P0/P1 notifications → typed `Codex.Events` structs
- P2/P3 notifications → start as raw notifications; add typed structs incrementally without breaking consumers

---

## Server Requests (Server → Client, Require Response)

**Upstream evidence**: `codex/codex-rs/app-server-protocol/src/protocol/common.rs:465-494`

### Approval Request Mapping

| Wire Method | Rust Variant | Params Type | Response Type | Hook Callback |
|-------------|--------------|-------------|---------------|---------------|
| `item/commandExecution/requestApproval` | `CommandExecutionRequestApproval` | `v2::CommandExecutionRequestApprovalParams` | `v2::CommandExecutionRequestApprovalResponse` | `Codex.Approvals.Hook.review_command/3` |
| `item/fileChange/requestApproval` | `FileChangeRequestApproval` | `v2::FileChangeRequestApprovalParams` | `v2::FileChangeRequestApprovalResponse` | `Codex.Approvals.Hook.review_file/3` |

### Approval Params (`codex/codex-rs/app-server-protocol/src/protocol/v2.rs:1714-1743`)

**CommandExecutionRequestApprovalParams**:
```json
{
  "threadId": "thr_123",
  "turnId": "turn_456",
  "itemId": "item_789",
  "reason": "Optional explanatory reason",
  "proposedExecpolicyAmendment": ["npm", "install"]
}
```

**FileChangeRequestApprovalParams**:
```json
{
  "threadId": "thr_123",
  "turnId": "turn_456",
  "itemId": "item_789",
  "reason": "Optional explanatory reason",
  "grantRoot": "/path/to/root"
}
```

### Approval Response (`codex/codex-rs/app-server-protocol/src/protocol/v2.rs:402-414`)

**ApprovalDecision enum values**:
- `Accept` (wire `"accept"`) → hook returns `:allow`
- `Decline` (wire `"decline"`) → hook returns `{:deny, reason}`
- `Cancel` (wire `"cancel"`) → treat as `{:deny, "cancelled"}` by default
- `AcceptForSession` (wire `"acceptForSession"`) and `AcceptWithExecpolicyAmendment` require either:
  - a backwards compatible extension to `Codex.Approvals.Hook` decision returns, or
  - an explicit user override API for approval requests

Recommended backwards-compatible hook decision extensions:
- `{:allow, for_session: true}` → `AcceptForSession`
- `{:allow, execpolicy_amendment: command_argv}` → `AcceptWithExecpolicyAmendment`
  - Wire shape (serde default enum encoding + camelCase): `"decision"` is an *externally tagged* enum:
    - `"acceptWithExecpolicyAmendment"` key
    - inner field name `execpolicyAmendment`
    - value is a JSON array of argv strings (`ExecPolicyAmendment` is `#[serde(transparent)]`)
  - Evidence: `ApprovalDecision::AcceptWithExecpolicyAmendment { execpolicy_amendment: ExecPolicyAmendment }` (`codex/codex-rs/app-server-protocol/src/protocol/v2.rs:405-414`) and `ExecPolicyAmendment` (`codex/codex-rs/app-server-protocol/src/protocol/v2.rs:481-486`)

**Important doc/code mismatch**:
- `codex/codex-rs/app-server/README.md:340` mentions an `acceptSettings` field, but the v2 protocol response structs only define `decision` (`codex/codex-rs/app-server-protocol/src/protocol/v2.rs:1727-1729`, `codex/codex-rs/app-server-protocol/src/protocol/v2.rs:1745-1749`).
- Implement against the protocol structs; do not rely on `acceptSettings`.

**Decision semantics (so the SDK can expose the full surface correctly)**:
- For **command execution approvals**, app-server maps:
  - `AcceptForSession` → `ReviewDecision::ApprovedForSession` (`codex/codex-rs/app-server/src/bespoke_event_handling.rs:1136-1139`), which core caches for the session (`codex/codex-rs/core/src/tools/sandboxing.rs:52-77`).
  - `AcceptWithExecpolicyAmendment` → `ReviewDecision::ApprovedExecpolicyAmendment { .. }` (`codex/codex-rs/app-server/src/bespoke_event_handling.rs:1139-1146`), which core persists to execpolicy (`codex/codex-rs/core/src/codex.rs:1767-1792`).
- For **file change approvals**, app-server currently treats `Accept`, `AcceptForSession`, and `AcceptWithExecpolicyAmendment` equivalently (all approved) (`codex/codex-rs/app-server/src/bespoke_event_handling.rs:1064-1076`).

**Concrete wire examples** (server request `id` echoed back):
```json
{"id":7,"result":{"decision":"accept"}}
{"id":7,"result":{"decision":"acceptForSession"}}
{"id":7,"result":{"decision":{"acceptWithExecpolicyAmendment":{"execpolicyAmendment":["npm","install"]}}}}
{"id":7,"result":{"decision":"decline"}}
{"id":7,"result":{"decision":"cancel"}}
```

### Hook Integration Flow

```
Server Request → Connection GenServer → Approval Event
                                       ↓
                              Hook.review_command/3 or Hook.review_file/3
                                       ↓
                              :allow | {:deny, reason} | {:async, ref}
                                       ↓
                              JSON-RPC Response → Server
```

**Async approval handling**:
1. Hook returns `{:async, ref}`
2. Connection stores pending approval state: `{request_id, ref, timeout_ref}`
3. External system calls back with decision
4. Connection sends JSON-RPC response
5. If timeout fires first, send `Decline` response

---

## ThreadItem Normalization (App-Server → Elixir)

**Upstream evidence**: `codex/codex-rs/app-server-protocol/src/protocol/v2.rs:1320-1392` (ThreadItem union)

### App-Server ThreadItem Types

| App-Server Type | Elixir Type | Key Field Mappings |
|-----------------|-------------|-------------------|
| `userMessage` | **NEW: `%Codex.Items.UserMessage{}`** | `content` → list of `UserInput` blocks |
| `agentMessage` | `%Codex.Items.AgentMessage{}` | `text` → `text` |
| `reasoning` | `%Codex.Items.Reasoning{}` | `summary`, `content` → `text` (join) |
| `commandExecution` | `%Codex.Items.CommandExecution{}` (extend) | Add `cwd`, `process_id`, `command_actions`, `duration_ms`; `aggregated_output` is optional (`codex/codex-rs/app-server-protocol/src/protocol/v2.rs:1338-1358`) |
| `fileChange` | `%Codex.Items.FileChange{}` (extend) | Preserve `diff` (and `move_path` for update renames) from `changes` (`codex/codex-rs/app-server-protocol/src/protocol/v2.rs:1361-1461`) |
| `mcpToolCall` | `%Codex.Items.McpToolCall{}` (extend) | Add `duration_ms`; `result.content` is MCP content blocks (`codex/codex-rs/app-server-protocol/src/protocol/v2.rs:1368-1478`) |
| `webSearch` | `%Codex.Items.WebSearch{}` | `query` |
| `imageView` | **NEW: `%Codex.Items.ImageView{}`** | `path` |
| `enteredReviewMode` | `%Codex.Items.ReviewMode{}` | `entered: true`, `review` |
| `exitedReviewMode` | `%Codex.Items.ReviewMode{}` | `entered: false`, `review` |

### Case Conversion

App-server uses camelCase; Elixir uses snake_case:
- `threadId` → `thread_id`
- `turnId` → `turn_id`
- `itemId` → `item_id`
- `commandActions` → `command_actions`
- `aggregatedOutput` → `aggregated_output`
- `exitCode` → `exit_code`
- `durationMs` → `duration_ms`

### Status Normalization

App-server enum values serialize as lower camel-case strings (e.g. `InProgress` → `"inProgress"`).

- Turn status (`codex/codex-rs/app-server-protocol/src/protocol/v2.rs:1184-1189`): `inProgress`, `completed`, `interrupted`, `failed`
- Command execution status (`codex/codex-rs/app-server-protocol/src/protocol/v2.rs:1424-1432`): `inProgress`, `completed`, `failed`, `declined`
- File change status (`codex/codex-rs/app-server-protocol/src/protocol/v2.rs:1453-1461`): `inProgress`, `completed`, `failed`, `declined`
- MCP tool call status (`codex/codex-rs/app-server-protocol/src/protocol/v2.rs:1463-1470`): `inProgress`, `completed`, `failed`

---

## Example Message Flows

### Handshake

```
Client → Server:
{"id":0,"method":"initialize","params":{"clientInfo":{"name":"codex_sdk","version":"0.2.5"}}}

Server → Client:
{"id":0,"result":{"userAgent":"codex/0.1.0"}}

Client → Server:
{"method":"initialized"}
```

### Thread Start + Turn

```
Client → Server:
{"id":1,"method":"thread/start","params":{"cwd":"/project"}}

Server → Client:
{"id":1,"result":{"thread":{"id":"thr_abc","preview":"","modelProvider":"openai","createdAt":1734200000,...},"model":"...","modelProvider":"openai","cwd":"/project",...}}

Server → Client (notification):
{"method":"thread/started","params":{"thread":{"id":"thr_abc",...}}}

Client → Server:
{"id":2,"method":"turn/start","params":{"threadId":"thr_abc","input":[{"type":"text","text":"Hello"}]}}

Server → Client:
{"id":2,"result":{"turn":{"id":"turn_xyz","status":"inProgress","items":[],"error":null}}}

Server → Client (notifications):
{"method":"turn/started","params":{"threadId":"thr_abc","turn":{"id":"turn_xyz",...}}}
{"method":"item/started","params":{"threadId":"thr_abc","turnId":"turn_xyz","item":{"type":"agentMessage","id":"msg_1","text":""}}}
{"method":"item/agentMessage/delta","params":{"threadId":"thr_abc","turnId":"turn_xyz","itemId":"msg_1","delta":"Hi there!"}}
{"method":"item/completed","params":{"threadId":"thr_abc","turnId":"turn_xyz","item":{"type":"agentMessage","id":"msg_1","text":"Hi there!"}}}
{"method":"thread/tokenUsage/updated","params":{"threadId":"thr_abc","turnId":"turn_xyz","tokenUsage":{...}}}
{"method":"turn/completed","params":{"threadId":"thr_abc","turn":{"id":"turn_xyz","status":"completed","items":[],"error":null}}}
```

### Approval Flow

```
Server → Client (request, has id):
{"id":7,"method":"item/commandExecution/requestApproval","params":{"threadId":"thr_abc","turnId":"turn_xyz","itemId":"cmd_1","reason":"Network access required"}}

Client → Server (response):
{"id":7,"result":{"decision":"accept"}}
```

---

## New Elixir Types Required

### Events (extend `Codex.Events`)

```elixir
defmodule Codex.Events.TurnPlanUpdated do
  defstruct thread_id: nil, turn_id: nil, explanation: nil, plan: []
  # plan: [%{step: String.t(), status: :pending | :in_progress | :completed}]
end

defmodule Codex.Events.CommandOutputDelta do
  defstruct thread_id: nil, turn_id: nil, item_id: nil, delta: ""
end

defmodule Codex.Events.ReasoningDelta do
  defstruct thread_id: nil, turn_id: nil, item_id: nil, delta: "", content_index: nil
end

defmodule Codex.Events.ReasoningSummaryDelta do
  defstruct thread_id: nil, turn_id: nil, item_id: nil, delta: "", summary_index: nil
end
```

### Items (extend `Codex.Items`)

```elixir
defmodule Codex.Items.UserMessage do
  defstruct id: nil, type: :user_message, content: []
end

defmodule Codex.Items.ImageView do
  defstruct id: nil, type: :image_view, path: nil
end

defmodule Codex.Items.ReviewMode do
  defstruct id: nil, type: :review_mode, entered: true, review: ""
end
```

### Approvals (new structs)

```elixir
defmodule Codex.AppServer.ApprovalRequest do
  defstruct request_id: nil,
            thread_id: nil,
            turn_id: nil,
            item_id: nil,
            type: nil,  # :command | :file_change
            reason: nil,
            proposed_amendment: nil,  # for commands
            grant_root: nil           # for file changes
end
```
