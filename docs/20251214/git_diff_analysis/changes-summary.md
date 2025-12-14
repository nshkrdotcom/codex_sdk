# Git Pull Changes Analysis (a2c86e5d8..5d77d4db6)

## Overview

This document analyzes the changes pulled from the upstream codex repository on 2025-12-14.

**Commit**: `5d77d4db6` - "Reimplement skills loading using SkillsManager + skills/list op. (#7914)"

## Summary

This is a **major architectural refactor** of the skills system, moving from static load-on-startup to dynamic, cacheable, manager-based loading.

## Files Modified (29 total)

### Core Changes
| File | Changes | Description |
|------|---------|-------------|
| `core/src/skills/loader.rs` | +51, -26 | Refactored for roots-based loading |
| `core/src/skills/manager.rs` | **NEW** +48 | New SkillsManager class |
| `core/src/skills/mod.rs` | +2 | Export manager |
| `core/src/skills/model.rs` | +3 | Added SkillScope to SkillMetadata |
| `core/src/codex.rs` | +128, -109 | Major refactor for skills manager |
| `core/src/conversation_manager.rs` | +38, -6 | New skills_manager field & methods |
| `core/src/auth.rs` | +13 | New test helper with custom codex_home |
| `core/src/state/service.rs` | +4, -1 | Field type change |

### Protocol Changes
| File | Changes | Description |
|------|---------|-------------|
| `protocol/src/protocol.rs` | +40, -18 | Op::ListSkills, ListSkillsResponseEvent |
| `app-server-protocol/common.rs` | +4 | Register `skills/list` request/response |
| `app-server-protocol/v2.rs` | +84 | skills/list types (params/response + skill metadata) |

### App-Server Changes
| File | Changes | Description |
|------|---------|-------------|
| `app-server/codex_message_processor.rs` | +67 | skills/list handler |
| `app-server/README.md` | +1 | Document new endpoint |

### UI Changes
| File | Changes | Description |
|------|---------|-------------|
| `tui/src/app.rs` | +33, -33 | ListSkillsResponse handling |
| `tui/src/chatwidget.rs` | +42, -19 | errors_for_cwd() helper |
| `tui2/src/app.rs` | +33, -33 | Same as tui |
| `tui2/src/chatwidget.rs` | +50, -28 | Same as tui |

### Test Changes
| File | Changes | Description |
|------|---------|-------------|
| `core/tests/suite/skills.rs` | +23, -5 | Updated for Op::ListSkills |
| `core/tests/common/test_codex.rs` | +7, -4 | codex_home parameter |
| `core/tests/suite/client.rs` | +34, -19 | Skills manager injection |

## New Features Introduced

### 1. SkillsManager Class

**Location**: `codex-rs/core/src/skills/manager.rs`

```rust
pub struct SkillsManager {
    codex_home: PathBuf,
    cache_by_cwd: RwLock<HashMap<PathBuf, SkillLoadOutcome>>,
}
```

**Purpose**: Centralized skills management with per-working-directory caching.

**Key Methods**:
- `new(codex_home: PathBuf)` - Constructor
- `skills_for_cwd(&self, cwd: &Path) -> SkillLoadOutcome` - Cached skill discovery

### 2. Op::ListSkills Operation

**Location**: `protocol/src/protocol.rs`

```rust
Op::ListSkills {
    cwds: Vec<PathBuf>,  // Empty = use session default
}
```

**Purpose**: Client-to-server request for skills discovery.

### 3. ListSkillsResponseEvent

```rust
pub struct ListSkillsResponseEvent {
    pub skills: Vec<SkillsListEntry>,
}

pub struct SkillsListEntry {
    pub cwd: PathBuf,
    pub skills: Vec<SkillMetadata>,
    pub errors: Vec<SkillErrorInfo>,
}
```

### 4. SkillScope Enum

```rust
pub enum SkillScope {
    User,  // From ~/.codex/skills
    Repo,  // From .codex/skills in git root
}
```

## API Breaking Changes

### Codex::spawn() Signature

**Before**:
```rust
pub async fn spawn(
    config: Config,
    auth_manager: Arc<AuthManager>,
    models_manager: Arc<ModelsManager>,
    conversation_history: InitialHistory,
    session_source: SessionSource,
) -> CodexResult<CodexSpawnOk>
```

**After**:
```rust
pub async fn spawn(
    config: Config,
    auth_manager: Arc<AuthManager>,
    models_manager: Arc<ModelsManager>,
    skills_manager: Arc<SkillsManager>,  // NEW PARAMETER
    conversation_history: InitialHistory,
    session_source: SessionSource,
) -> CodexResult<CodexSpawnOk>
```

### SessionServices Field

**Before**: `skills: Option<SkillLoadOutcome>`
**After**: `skills_manager: Arc<SkillsManager>`

### SessionConfiguredEvent

**Before**: Included `skill_load_outcome: Option<SkillLoadOutcomeInfo>`
**After**: Field removed - clients must use `Op::ListSkills`

## Behavioral Changes

| Aspect | Before | After |
|--------|--------|-------|
| Skills Loading | Static, once at session start | Dynamic, on-demand per-cwd |
| Caching | No caching | Per-cwd caching in SkillsManager |
| Architecture | Skills in SessionConfiguredEvent | Separate Op::ListSkills + response |
| Scope Tracking | No user/repo distinction | SkillScope enum distinguishes |
| Multiple CWDs | Not supported | ListSkills accepts Vec<PathBuf> |
| API Style | Event-driven push | RPC-style request/response |

## Porting Implications for Elixir

1. **New Protocol Types Required**:
   - `Op.ListSkills` operation
   - `ListSkillsResponseEvent` event
   - `SkillsListEntry` struct
   - `SkillScope` enum

2. **If Using Core Protocol**:
   - Must handle new event types
   - Must implement Op::ListSkills submission
   - Must update event handlers

3. **If Using Exec JSONL** (current):
   - Skills not exposed via exec transport
   - Would need transport change to support
