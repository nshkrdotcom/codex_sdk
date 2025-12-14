# App-Server Protocol Inventory (What `codex_sdk` Must Speak)

## Message framing

`codex app-server` speaks JSON-RPC-like messages over stdio:

- newline-delimited JSON objects
- `"jsonrpc":"2.0"` is **omitted** (upstream docs: `codex/codex-rs/app-server/README.md:17`)

### Shapes to handle

1. **Client request** (client → server)
   ```json
   { "id": 1, "method": "thread/start", "params": { ... } }
   ```

2. **Server response** (server → client)
   ```json
   { "id": 1, "result": { ... } }
   ```

3. **Server notification** (server → client, no id)
   ```json
   { "method": "item/agentMessage/delta", "params": { ... } }
   ```

4. **Server request** (server → client, requires response)
   ```json
   { "id": 7, "method": "item/commandExecution/requestApproval", "params": { ... } }
   ```

## Initialization handshake

Before any other method, clients must:

1. Send `initialize` request
2. Send `initialized` notification after successful response

Upstream docs: `codex/codex-rs/app-server/README.md:39`.

## Authoritative method registry

The complete registry lives in:

- `codex/codex-rs/app-server-protocol/src/protocol/common.rs:96` (client requests)
- `codex/codex-rs/app-server-protocol/src/protocol/common.rs:465` (server requests)
- `codex/codex-rs/app-server-protocol/src/protocol/common.rs:521` (server notifications)

### v2 client request methods (non-deprecated)

Declared explicitly with wire names in `codex/codex-rs/app-server-protocol/src/protocol/common.rs:102`:

- Thread lifecycle
  - `thread/start`
  - `thread/resume`
  - `thread/list`
  - `thread/archive`
  - `thread/compact`
- Turns
  - `turn/start`
  - `turn/interrupt`
- Review
  - `review/start`
- Skills
  - `skills/list`
- Models
  - `model/list`
- Config service
  - `config/read`
  - `config/value/write`
  - `config/batchWrite`
- One-off sandboxed command
  - `command/exec`
- Account + auth
  - `account/login/start`
  - `account/login/cancel`
  - `account/logout`
  - `account/read`
  - `account/rateLimits/read`
- MCP server management
  - `mcpServers/list`
  - `mcpServer/oauth/login`
- Feedback
  - `feedback/upload`

### Deprecated v1 client request methods

Still present in `codex/codex-rs/app-server-protocol/src/protocol/common.rs:205` for legacy clients, e.g.:

- `newConversation`
- `sendUserTurn`
- `applyPatchApproval` (server request)
- `execCommandApproval` (server request)

`codex_sdk` can choose to:
- implement only v2 for parity with “current” clients, or
- implement v1 too for full historical compatibility.

## Server requests (approvals)

v2 approval request methods are defined in `codex/codex-rs/app-server-protocol/src/protocol/common.rs:465`:

- `item/commandExecution/requestApproval`
- `item/fileChange/requestApproval`

These are the critical piece for parity with interactive app-server clients (VS Code extension): the server pauses progress until the client replies.

## Server notifications (streaming events)

Server notifications are defined in `codex/codex-rs/app-server-protocol/src/protocol/common.rs:521`.

### v2 notifications (non-deprecated)

- `error`
- Thread
  - `thread/started`
  - `thread/tokenUsage/updated`
  - `thread/compacted`
- Turn
  - `turn/started`
  - `turn/completed`
  - `turn/diff/updated`
  - `turn/plan/updated`
- Items
  - `item/started`
  - `item/completed`
  - `item/agentMessage/delta`
  - `item/reasoning/textDelta`
  - `item/reasoning/summaryTextDelta`
  - `item/reasoning/summaryPartAdded`
  - `item/commandExecution/outputDelta`
  - `item/commandExecution/terminalInteraction`
  - `item/fileChange/outputDelta`
  - `item/mcpToolCall/progress`
- MCP
  - `mcpServer/oauthLogin/completed`
- Account
  - `account/updated`
  - `account/rateLimits/updated`
  - `account/login/completed` (special-cased rename; see `codex/codex-rs/app-server-protocol/src/protocol/common.rs:548`)
- Platform
  - `windows/worldWritableWarning`

### Deprecated notifications

- `authStatusChange`
- `loginChatGptComplete`
- `sessionConfigured`

## Implications for `codex_sdk`

To support app-server parity, `codex_sdk` must:

1. Decode all 4 message shapes (request/response/notification/server-request).
2. Provide a stable internal mapping from app-server notification payloads into Elixir structs:
   - either extend `Codex.Events`/`Codex.Items` to model the full app-server payloads, or
   - preserve payloads as raw maps and standardize a smaller set of fields (thread_id/turn_id/item_id/etc).
