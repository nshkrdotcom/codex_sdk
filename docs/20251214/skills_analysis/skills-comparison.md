# Skills Implementation Comparison: Rust vs Elixir

## Executive Summary

| Codebase | Skills Status | Implementation Level |
|----------|--------------|---------------------|
| Rust (codex-rs) | **Fully Implemented** | 583 lines, 6 files |
| Elixir (codex_sdk) | **Not Implemented** | 0 lines, 0 files |

**Answer to "Were skills already in the codebase?"**:
- **Rust**: Yes, skills existed before this pull. The new changes refactored them with SkillsManager.
- **Elixir**: No, skills have never been implemented in the Elixir port.

## What Are Skills?

Skills are reusable instruction bundles that extend Codex's capabilities:

- **Name**: Up to 64 characters, single line
- **Description**: Up to 1024 characters, single line
- **Path**: Location of `SKILL.md` file on disk
- **Scope**: User (global) or Repo (project-specific)

Skills are discovered from two locations:
1. **User Skills**: `~/.codex/skills/**/SKILL.md`
2. **Repo Skills**: `<git_root>/.codex/skills/**/SKILL.md`

> Note: `codex/docs/skills.md` currently documents only `~/.codex/skills` and different length limits; treat the Rust implementation as source-of-truth.

## Rust Implementation (Complete)

### File Structure

```
codex-rs/core/src/skills/
├── mod.rs           # Module exports
├── model.rs         # SkillMetadata, SkillLoadOutcome structs
├── loader.rs        # Discovery and parsing (378 lines)
├── manager.rs       # SkillsManager with caching (48 lines) - NEW
├── injection.rs     # Runtime injection (79 lines)
└── render.rs        # Markdown rendering (43 lines)
```

### Key Types

```rust
// Skill metadata returned from discovery
pub struct SkillMetadata {
    pub name: String,
    pub description: String,
    pub path: PathBuf,
    pub scope: SkillScope,  // User or Repo
}

// Discovery result with errors
pub struct SkillLoadOutcome {
    pub skills: Vec<SkillMetadata>,
    pub errors: Vec<SkillError>,
}

// NEW: Centralized manager with caching
pub struct SkillsManager {
    codex_home: PathBuf,
    cache_by_cwd: RwLock<HashMap<PathBuf, SkillLoadOutcome>>,
}
```

### Discovery Flow

1. **Loader** recursively scans skill directories
2. Finds all `SKILL.md` files (skips hidden, symlinks)
3. Parses YAML frontmatter for name/description
4. Validates field lengths
5. Returns `SkillLoadOutcome` with skills and errors

### Manager Flow (NEW)

1. **SkillsManager** holds per-cwd cache
2. On `skills_for_cwd(cwd)`:
   - Check cache for cwd
   - If cached, return immediately
   - Otherwise, discover user + repo skills
   - Cache and return result
3. Thread-safe via RwLock

### Protocol Integration

```rust
// Core protocol includes a skill selection input (used by the in-process TUI)
pub enum UserInput {
    Text { text: String },
    Image { image_url: String },
    LocalImage { path: PathBuf },
    Skill { name: String, path: PathBuf },  // Skill selection
}

// Client requests skill discovery
Op::ListSkills { cwds: Vec<PathBuf> }

// Server responds with per-cwd skills
EventMsg::ListSkillsResponse(ListSkillsResponseEvent {
    skills: Vec<SkillsListEntry>,
})
```

**Important**: External clients cannot currently send `UserInput::Skill`:
- App-server v2 `UserInput` union omits `Skill` (`codex/codex-rs/app-server-protocol/src/protocol/v2.rs:1289-1293`) and treats extra variants as unreachable (`codex/codex-rs/app-server-protocol/src/protocol/v2.rs:1311`).

### Test Coverage

```
codex-rs/core/tests/suite/skills.rs
- Valid skill loading
- Hidden file skipping
- Length enforcement
- Repo root loading
```

## Elixir Implementation (None)

### Current State

- **Zero skills-related code**
- No module in `lib/codex/skills/`
- No skill types in protocol definitions
- No skill discovery logic
- Not even placeholder stubs

### Why Missing?

From gap analysis (`docs/20251213/upstream-sync-plan/03-elixir-port-gaps.md`):

> Skills are listed as "Transport-dependent" - blocked on transport decision.

In this upstream pull, `SessionConfiguredEvent.skill_load_outcome` was removed; clients must explicitly request skills via `Op::ListSkills` (core) or `skills/list` (app-server).

The Elixir SDK currently uses **exec JSONL transport**, which does NOT expose:
- `Op::ListSkills` operation
- `EventMsg::ListSkillsResponse`
- `UserInput::Skill` variant
- Skill metadata/error types and per-cwd skill results

### What Elixir Has Instead

| Component | Status |
|-----------|--------|
| Tools | Fully implemented (different from Skills) |
| Handoffs | Fully implemented |
| Approvals | Fully implemented |
| Guardrails | Fully implemented |
| Events | Fully implemented (no skill events) |

**Note**: "Tools" in Elixir are function invocations, not skill bundles. They serve different purposes.

## Transport Blocker Analysis

### Exec JSONL Events (Current Elixir Transport)

```
thread.started
turn.started
item.started
item.updated
item.completed
turn.completed
turn.failed
error
```

**Missing**: All skill-related events and operations.

### App-Server `skills/list` (Recommended for Elixir)

App-server exposes skills discovery as a request/response method:
- `skills/list` is a v2 client request (`codex/codex-rs/app-server-protocol/src/protocol/common.rs:124-127`)
- Response carries per-cwd skill metadata + errors (`codex/codex-rs/app-server-protocol/src/protocol/v2.rs:976-1033`)

### Porting Path

To add skills to Elixir, would need either:

1. **Add an app-server transport** (recommended)
   - Speak app-server JSON-RPC over stdio
   - Implement `skills/list` and decode the response
   - Expose a first-class Elixir API for listing skills + surfacing per-cwd errors

2. **Extend exec JSONL** (unlikely)
   - Would require upstream changes to codex binary
   - Not recommended approach

## Porting Requirements (If Proceeding)

### Required New Modules (Recommended)

Keep discovery server-side; implement only types + API wrapper:

```elixir
# lib/codex/skills/
├── scope.ex         # :user | :repo
├── metadata.ex      # SkillMetadata
├── error_info.ex    # SkillErrorInfo (mirrors upstream)
├── list_entry.ex    # SkillsListEntry
└── list_response.ex # SkillsListResponse (data: [SkillsListEntry])
```

### Required Protocol Updates

```elixir
defmodule Codex.AppServer do
  # New method wrapper (app-server transport only)
  def skills_list(conn, opts \\ []) do
    # send {"method":"skills/list","params":{"cwds":[...]}}
    # decode {"result":{"data":[...]}}
  end
end
```

### Estimated Effort

| Task | Lines | Complexity |
|------|-------|------------|
| Type structs | ~150 | Low |
| App-server request/response | ~150 | Medium |
| Tests | ~200 | Medium |
| **Total** | ~500 | Medium |

## Recommendation

Skills implementation in Elixir depends on transport:

- If staying exec-only: skills remain “pass-through only” (no list/select surface).
- If adopting app-server: implement `skills/list` after the app-server transport refactor (see `docs/20251214/multi_transport_refactor/README.md`).

If proceeding with app-server:
1. First complete the app-server transport refactor (`docs/20251214/multi_transport_refactor/README.md`)
2. Then implement `skills/list` + types on that transport
3. Discovery remains server-side (Elixir just decodes response)

The new SkillsManager refactor in Rust actually makes porting easier - skills are now request/response based rather than push-on-startup.
