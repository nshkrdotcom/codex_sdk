# Executive Summary: Design Review Findings

This document summarizes the critical findings from the design review of the multi-transport refactor proposal.

## Review Scope

Reviewed all documents in `docs/20251214/multi_transport_refactor/` against upstream evidence in:
- `codex/codex-rs/app-server-protocol/src/protocol/common.rs`
- `codex/codex-rs/app-server-protocol/src/protocol/v2.rs`
- `codex/codex-rs/app-server/README.md`
- `codex/codex-rs/exec/src/exec_events.rs`
- `codex/codex-rs/protocol/src/user_input.rs`
- `codex/codex-rs/tui/src/chatwidget.rs`
- `codex/codex-rs/core/src/skills/injection.rs`
- `codex/sdk/typescript/src/thread.ts`

---

## Top 5 Risks

### Risk 1: Approval Handling Complexity (HIGH)

**Issue**: The original proposal underspecified how app-server approval requests integrate with `Codex.Approvals.Hook`.

**Details**:
- App-server uses server-initiated JSON-RPC requests (not notifications)
- Client MUST respond with `ApprovalDecision` enum values (`codex/codex-rs/app-server-protocol/src/protocol/v2.rs:402-414`)
- Async hook patterns (`{:async, ref}`) require careful timeout and response correlation

**Mitigation**: Added `11_failure_modes_and_recovery.md` with explicit approval flow documentation and timeout handling.

### Risk 2: Event Schema Drift (MEDIUM)

**Issue**: App-server notifications have different structure than exec JSONL events.

**Details**:
- Exec uses snake_case with dot separators (`turn.completed`)
- App-server uses camelCase with slash separators (`turn/completed`)
- Some notifications exist only in app-server (e.g., `turn/plan/updated`, reasoning deltas)
- `Codex.Events.parse!/1` expects exec-style maps (`"type"` key + mostly snake_case keys), but already accepts some slash-style `"type"` variants (e.g. `thread/tokenUsage/updated`) (`lib/codex/events.ex:369-379`); app-server still requires a JSON-RPC envelope/key adapter (`{"method":...,"params":...}` → internal event map)

**Mitigation**: Added `10_protocol_mapping_spec.md` with explicit mapping tables. Recommended hybrid approach: typed events for P0/P1, raw maps for P2/P3.

### Risk 3: Connection State Management (MEDIUM)

**Issue**: Original proposal didn't specify what happens to threads when connections crash.

**Details**:
- Thread data persists server-side (rollout files)
- But active turn state, subscriptions, and in-flight requests are lost
- Threads referencing a dead connection become "orphaned"

**Mitigation**: Added `11_failure_modes_and_recovery.md` specifying that automatic reconnect is NOT implemented; threads survive but must be re-attached via `thread/resume` on new connection.

### Risk 4: Message Framing Edge Cases (LOW-MEDIUM)

**Issue**: Original proposal mentioned newline-delimited JSON but didn't address edge cases.

**Details**:
- Partial lines across read() calls
- Very large messages
- Interleaved stdout/stderr

**Mitigation**: Added explicit buffering requirements and limits in `10_protocol_mapping_spec.md` and `11_failure_modes_and_recovery.md`.

### Risk 5: Backwards Compatibility Surface Area (LOW)

**Issue**: Adding transport abstraction touches `Codex.Thread` core paths.

**Details**:
- Must not break existing exec-based tests
- Thread struct gains new fields (`transport`, `transport_ref`)
- Default must remain exec

**Mitigation**: Added `12_public_api_proposal.md` with explicit backwards compatibility guarantees and migration path.

---

## Top 5 Missing Requirements (Now Fixed)

### MR1: Explicit Parity Definition

**Was missing**: What exactly does "feature parity" mean?

**Fixed in**: `09_requirements_and_nongoals.md`

**Now specifies**:
- Definition 1: Exec JSONL Surface Parity (matches TS SDK)
- Definition 2: App-Server Surface Parity (all v2 methods)
- Definition 3: Core-Only Features (explicitly out of scope)

### MR2: Method-by-Method Implementation Checklist

**Was missing**: No actionable list of what methods need Elixir APIs.

**Fixed in**: `10_protocol_mapping_spec.md`

**Now specifies**:
- Every v2 client request with Elixir API name, params, response, priority
- Every server notification with mapping to `Codex.Events`
- Every server request (approval) with hook callback

### MR3: Approval Request/Response Payloads

**Was missing**: Exact JSON shapes for approval flows.

**Fixed in**: `10_protocol_mapping_spec.md` and `11_failure_modes_and_recovery.md`

**Now specifies**:
- `CommandExecutionRequestApprovalParams` fields (`codex/codex-rs/app-server-protocol/src/protocol/v2.rs:1714-1722`)
- `FileChangeRequestApprovalParams` fields (`codex/codex-rs/app-server-protocol/src/protocol/v2.rs:1734-1743`)
- `ApprovalDecision` enum values and Elixir mapping
- Hook integration flow with async handling

### MR4: Failure Mode Specifications

**Was missing**: What happens on timeout, crash, malformed message?

**Fixed in**: `11_failure_modes_and_recovery.md`

**Now specifies**:
- 24 failure scenarios with detection, recovery, and user-facing behavior
- Default timeouts for each operation
- Telemetry events for observability

### MR5: Public API Proposal

**Was missing**: Concrete Elixir module/function signatures.

**Fixed in**: `12_public_api_proposal.md`

**Now specifies**:
- `Codex.Transport` behaviour
- `Codex.AppServer` module with all public functions
- `Codex.AppServer.Error` and `ConnectionError` types
- Configuration options
- Backwards compatibility guarantees

---

## What Is Blocked Upstream vs Implementable Now

### Blocked Upstream

| Feature | Blocker | Evidence |
|---------|---------|----------|
| `UserInput::Skill` selection | App-server v2 `UserInput` enum missing `Skill` variant | `codex/codex-rs/app-server-protocol/src/protocol/v2.rs:1289-1293`, `codex/codex-rs/app-server-protocol/src/protocol/v2.rs:1311` (`unreachable!()`) |

**Options**:
1. **Wait for upstream** to add `Skill` variant to app-server protocol
2. **SDK emulation** (read SKILL.md, inject as text) - behavioral parity but not protocol parity

Recommendation: Implement emulation as opt-in, document clearly as "emulation mode".

### Implementable Now (Once App-Server Transport Exists)

| Feature | App-Server Method | Evidence |
|---------|-------------------|----------|
| Skills discovery | `skills/list` | `codex/codex-rs/app-server-protocol/src/protocol/common.rs:124-127`, `codex/codex-rs/app-server-protocol/src/protocol/v2.rs:976-1033` |
| Thread history | `thread/list` | `codex/codex-rs/app-server-protocol/src/protocol/common.rs:116-119` |
| Thread management | `thread/archive`, `thread/compact` | `codex/codex-rs/app-server-protocol/src/protocol/common.rs:112-123` |
| Model listing | `model/list` | `codex/codex-rs/app-server-protocol/src/protocol/common.rs:141-144` |
| Config read/write | `config/read`, `config/value/write`, `config/batchWrite` | `codex/codex-rs/app-server-protocol/src/protocol/common.rs:187-198` |
| Code review | `review/start` | `codex/codex-rs/app-server-protocol/src/protocol/common.rs:136-139` |
| Turn interruption | `turn/interrupt` | `codex/codex-rs/app-server-protocol/src/protocol/common.rs:132-135` |
| Sandboxed command | `command/exec` | `codex/codex-rs/app-server-protocol/src/protocol/common.rs:181-185` |
| Account/auth | `account/*` | `codex/codex-rs/app-server-protocol/src/protocol/common.rs:156-203` |
| MCP servers | `mcpServers/list`, `mcpServer/oauth/login` | `codex/codex-rs/app-server-protocol/src/protocol/common.rs:146-154` |

---

## Implementation Priority Recommendation

### Phase 0: Transport Abstraction (1-2 days)
- Introduce `Codex.Transport` behaviour
- Wrap existing `Codex.Exec` as `Codex.Transport.ExecJsonl`
- Ensure all existing tests pass

### Phase 1: App-Server Connection (2-3 days)
- `Codex.AppServer.Connection` GenServer
- Initialize/initialized handshake
- Request ID correlation
- Basic `thread/start`, `turn/start`

### Phase 2: Event Normalization (2-3 days)
- Notification → `Codex.Events` adapter
- ThreadItem → `Codex.Items` adapter
- Handle all P0 notification types

### Phase 3: Approvals (1-2 days)
- Server request handling
- Hook integration
- Async approval support with timeouts

### Phase 4: Feature Surface (3-5 days)
- `skills/list`, `model/list`, `config/*`
- `thread/list`, `thread/archive`, `thread/compact`
- `turn/interrupt`, `review/start`

### Phase 5 (Optional): Extended Features (2-3 days)
- Account/auth endpoints
- MCP server management
- Skill emulation mode

---

## Acceptance Criteria

1. **Backwards compatibility**: All existing tests pass with default (exec) transport
2. **App-server handshake**: Can connect, initialize, and disconnect cleanly
3. **Thread lifecycle**: Can start, resume, list, archive threads via app-server
4. **Turn execution**: Can run turns with streaming events
5. **Approvals**: Can handle approval requests with allow/deny
6. **Skills**: Can list skills via `skills/list`
7. **Documentation**: All public APIs documented with examples
8. **Error handling**: All failure modes from `11_failure_modes_and_recovery.md` handled

---

## Documents Created/Modified

### Created
- `09_requirements_and_nongoals.md` - Explicit scope and parity definitions
- `10_protocol_mapping_spec.md` - Method-by-method implementation guide
- `11_failure_modes_and_recovery.md` - Error handling specifications
- `12_public_api_proposal.md` - Elixir API design
- `13_executive_summary.md` - This document

### Modified
- `README.md` - Updated index with new documents
- `05_app_server_protocol_inventory.md` - Fixed line number citations
- `06_parity_matrix.md` - Added TS SDK scope and cross-references

---

## Reviewer Sign-Off Checklist

- [ ] Parity definitions are unambiguous
- [ ] All v2 methods have planned Elixir API
- [ ] Approval flow is fully specified
- [ ] Failure modes are comprehensive
- [ ] Backwards compatibility is guaranteed
- [ ] Blockers are clearly identified
- [ ] Implementation phases are realistic
