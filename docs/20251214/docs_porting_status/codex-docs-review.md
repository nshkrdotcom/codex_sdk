# Codex Documentation Review & Porting Status

## Documentation Found

The Rust codex repository has documentation in two locations:
1. `codex-rs/docs/` - Technical documentation
2. `codex/docs/` - User-facing documentation (skills.md, etc.)

## Technical Documentation (codex-rs/docs/)

### 1. codex_mcp_interface.md

**Status**: Experimental MCP server interface documentation

**Contents**:
- MCP server binary info (`codex mcp-server`)
- JSON-RPC 2.0 over stdio transport
- Available operations:
  - Conversation Management (newConversation, sendUserMessage, etc.)
  - Configuration (getUserSavedConfig, setDefaultModel, etc.)
  - Authentication (account/read, login, logout, rateLimits)
  - Utilities (gitDiffToRemote, execOneOffCommand)
  - Approvals (applyPatchApproval, execCommandApproval)
  - Event streaming (codex/event notifications)

**Elixir Port Status**: NOT PORTED
- Elixir SDK does not implement MCP server interface
- Uses exec JSONL transport instead
- Different architecture (SDK vs MCP server)

**Porting Relevance**: Low priority - different use case

### 2. protocol_v1.md

**Status**: Core protocol specification

**Contents**:
- System terminology (Model, Codex, Session, Task, Turn)
- Queue-based communication (SQ/EQ)
- Session lifecycle and configuration
- Task/Turn execution model
- Event-driven architecture
- Transport options (IPC, stdio, TCP, HTTP2, gRPC)

**Key Concepts Documented**:

| Concept | Description | Elixir Port Status |
|---------|-------------|-------------------|
| Model | Responses REST API | ✅ Implemented |
| Codex | Core engine | ✅ Via exec binary |
| Session | Config + state container | ✅ Implemented |
| Task | Work unit from user input | ✅ Implemented |
| Turn | Single Model request cycle | ✅ Implemented |
| SQ/EQ | Submission/Event queues | ⚠️ Abstracted (exec) |

**Elixir Port Status**: PARTIALLY PORTED
- Core concepts implemented
- Queue abstraction hidden behind exec transport
- Missing: Direct protocol access

## User Documentation (codex/docs/)

### skills.md

**Status**: User-facing skills documentation

**Contents**:
- What skills are
- SKILL.md file format (YAML frontmatter)
- Discovery location documented: `~/.codex/skills/**/SKILL.md` (recursive)
- Loading and rendering behavior (`## Skills` section in runtime context)
- Validation and error reporting (TUI modal)
- Examples / setup walkthrough

**Elixir Port Status**: ⚠️ Pass-through only
- Skills are implemented in the upstream `codex` binary behind `features.skills` (default: false).
- `codex_sdk` can benefit from skills when they’re enabled via `$CODEX_HOME/config.toml` (or equivalent), but the SDK does not currently:
  - expose a first-class skills API (list, select, surface errors),
  - speak the app-server transport needed to call `skills/list` (or any other app-server request/response method).

**Upstream Doc vs Code Notes**:
- `codex/docs/skills.md` documents different validation limits (name ≤100, description ≤500), but `codex-rs/core/src/skills/loader.rs` enforces name ≤64 and description ≤1024.
- `codex/docs/skills.md` documents user-scope skills under `~/.codex/skills`, but the Rust implementation also discovers repo-scope skills under `<git_root>/.codex/skills`.

## What's Missing in Elixir

### Documentation Gaps

| Document | Rust | Elixir | Gap |
|----------|------|--------|-----|
| MCP Interface | ✅ | ❌ | Different architecture |
| Protocol v1 | ✅ | ⚠️ | Partially covered in code |
| Skills Guide | ✅ | ⚠️ | Pass-through via upstream binary; no SDK surface |

### Feature Gaps (Per Protocol Docs)

| Feature | Documented | Elixir Status |
|---------|-----------|---------------|
| Op::ConfigureSession | ✅ | ✅ Via exec opts |
| Op::UserInput | ✅ | ✅ Text only |
| Op::UserInput (Skill) | ✅ | ❌ Not implemented |
| Op::Interrupt | ✅ | ⚠️ Via process kill |
| Op::ListSkills | ✅ | ❌ Not implemented |
| Op::ExecApproval | ✅ | ✅ Implemented |
| EventMsg types | ✅ | ⚠️ Subset via exec |

### Transport Gaps

The protocol docs describe multiple transport options:

| Transport | Documented | Elixir Status |
|-----------|-----------|---------------|
| Cross-thread channels | ✅ | N/A (different lang) |
| IPC | ✅ | ❌ |
| stdin/stdout | ✅ | ✅ Via exec |
| TCP | ✅ | ❌ |
| HTTP2 | ✅ | ❌ |
| gRPC | ✅ | ❌ |

## Recommendations

### High Priority (Should Port)

1. **Core protocol concepts** - Document Elixir equivalents
2. **Event types mapping** - Map Rust events to Elixir structs
3. **Operation mapping** - Document supported operations

### Medium Priority (Consider)

1. **Skills documentation** - Once skills are implemented
2. **Transport options** - If adding more transports

### Low Priority (Optional)

1. **MCP interface** - Different architecture in Elixir
2. **Internal protocol details** - Abstracted by exec

## Existing Elixir Documentation

The Elixir SDK has its own documentation:

```
docs/20251213/upstream-sync-plan/
├── 01-initial-review.md
├── 02-codex-rs-changes.md
├── 03-elixir-port-gaps.md
├── 04-parity-checklist.md
└── 05-implementation-plan.md
```

These cover:
- Gap analysis between Rust and Elixir
- Implementation plan with phases
- Feature parity checklist
- Transport decision (Phase 0)

## Action Items

1. [ ] Create Elixir-specific protocol documentation
2. [ ] Document event type mappings
3. [ ] Add skills documentation when implemented
4. [ ] Keep gap analysis updated with new upstream changes
