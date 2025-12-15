# Technical Porting Plan: December 2025 Upstream Changes

## Executive Summary

The upstream pull (a2c86e5d8..5d77d4db6) introduces a **single major change**: reimplementation of skills loading using SkillsManager and skills/list operation.

**Impact Assessment**:
- Skills were already NOT implemented in Elixir
- New changes make skills MORE portable (request/response vs push)
- Requires an app-server transport to expose `skills/list` (exec JSONL does not expose app-server request/response methods)

**Update (Decision)**:
- Proceed with an app-server transport refactor (see `docs/20251214/multi_transport_refactor/README.md`)
- Then implement `skills/list` on that transport

## Changes Requiring Porting

### 1. SkillsManager & Skills System

**Priority**: Medium (unblocked once app-server transport exists)

**New Rust Components**:
```
codex-rs/core/src/skills/
├── manager.rs      # NEW - SkillsManager with caching
├── loader.rs       # Modified - roots-based loading
├── model.rs        # Modified - added SkillScope
├── injection.rs    # Unchanged
├── render.rs       # Unchanged
└── mod.rs          # Modified - export manager
```

**Recommended Elixir Work**:
- Do **not** reimplement `SkillsManager`/loader logic in Elixir.
- Keep skills discovery server-side (in the vendored `codex` runtime) and expose it via app-server `skills/list`.
- Port only the **data types** needed to represent the response (`SkillScope`, `SkillMetadata`, errors, list entries).

**Estimated Effort**: 150-300 lines (types + API wrapper), plus whatever app-server transport work is required (tracked in `docs/20251214/multi_transport_refactor/07_phased_implementation_plan.md`).

### 2. Protocol Types

**Priority**: Medium (blocked on app-server transport)

**New Rust Types**:
```rust
Op::ListSkills { cwds: Vec<PathBuf> }
EventMsg::ListSkillsResponse(ListSkillsResponseEvent)
SkillsListEntry { cwd, skills, errors }
SkillScope { User, Repo }
```

**Required Elixir Work (recommended path)**:
- Implement app-server `skills/list` (`codex/codex-rs/app-server-protocol/src/protocol/common.rs:124-127`) and decode its response types (`codex/codex-rs/app-server-protocol/src/protocol/v2.rs:976-1033`).
- (Optional) define Elixir structs mirroring:
  - `SkillScope`
  - `SkillMetadata`
  - `SkillErrorInfo`
  - `SkillsListEntry`
  - `SkillsListResponse` (with `data: [...]`)

**Estimated Effort**: 200-400 lines (types + decoding + `Codex.AppServer.skills_list/2`)

### 3. API Changes

**Priority**: N/A (if not using core protocol)

The Rust API changes (Codex::spawn signature, etc.) only matter if Elixir adopts core protocol. Current exec-based approach abstracts these.

## Porting Decision Matrix

| Component | Transport Required | Current Elixir | Action |
|-----------|-------------------|----------------|--------|
| SkillsManager | In-process (Rust) | exec JSONL | Do not port; use upstream runtime |
| Op::ListSkills | Core protocol | exec JSONL | Do not implement (not reachable); use app-server `skills/list` |
| ListSkillsResponse | Core protocol | exec JSONL | Do not implement as exec event; decode app-server `skills/list` response |
| SkillScope enum | Any | None | Port when skills added |
| SkillMetadata | Any | None | Port when skills added |

## Recommended Approach

### Option A: Implement App-Server `skills/list` (Recommended)

**Rationale**:
- Matches upstream external-client surface (app-server v2).
- Avoids duplicating skills discovery logic (which is non-trivial and already exists in Rust).
- Enables immediate UX wins: list skills + show per-cwd errors once app-server transport exists.

**Action**:
1. Complete app-server transport refactor (`docs/20251214/multi_transport_refactor/07_phased_implementation_plan.md`).
2. Add `Codex.AppServer.skills_list/2` and types.
3. (Optional) add thin client-side caching (ETS) on top of `skills_list/2` if needed for UX.

### Option B: Port Types Only (Not Recommended)

**Rationale**:
- Low-effort scaffolding.

**Downside**:
- Dead code until app-server transport ships.
- Higher drift risk than simply decoding the app-server schema.

### Option C: Implement Client-Side Discovery (Not Recommended)

**Rationale**:
- Could work without app-server.

**Downside**:
- Duplicates upstream loader/manager behavior and validation edge cases.
- Hard to keep in sync (paths, git-root discovery, error reporting, caching semantics).

## Implementation Plan (If Proceeding)

### Prerequisites

1. Complete the multi-transport refactor prerequisites:
   - transport abstraction in `Codex.Thread`
   - app-server connection + handshake
   - notification + item adapters
   (see `docs/20251214/multi_transport_refactor/07_phased_implementation_plan.md`)

### Phase 1: Types + `skills/list` API (1-2 days after app-server transport exists)

1. Add Elixir types mirroring the app-server schema (`codex/codex-rs/app-server-protocol/src/protocol/v2.rs:976-1033`).
2. Implement `Codex.AppServer.skills_list/2` (request/response).
3. Add minimal integration test(s) tagged `:integration` that call `skills_list/2` against a real `codex app-server` process.

### Phase 2: (Optional) Client-side caching (1 day)

If the UI calls `skills_list/2` frequently, add an ETS-backed cache keyed by `cwd` in Elixir. Keep it strictly an optimization layer; do not reimplement discovery logic.

## Testing Strategy

### Unit Tests

```elixir
# test/codex/skills/metadata_test.exs
describe "Metadata" do
  test "creates valid metadata" do
    meta = %Codex.Skills.Metadata{
      name: "test-skill",
      description: "A test skill",
      path: "/home/user/.codex/skills/test/SKILL.md",
      scope: :user
    }
    assert meta.name == "test-skill"
  end
end
```

### Integration Tests

```elixir
# test/codex/app_server/skills_test.exs
describe "Codex.AppServer.skills_list/2" do
  @tag :integration
  test "returns skills for cwd" do
    {:ok, opts} = Codex.Options.new(%{api_key: System.fetch_env!("CODEX_API_KEY")})
    {:ok, conn} = Codex.AppServer.connect(opts)
    {:ok, %{data: entries}} = Codex.AppServer.skills_list(conn, cwds: ["/project"])
    assert is_list(entries)
  end
end
```

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Transport incompatibility | Medium | High | Follow `docs/20251214/multi_transport_refactor/10_protocol_mapping_spec.md` and keep raw passthrough for unknown methods |
| Upstream changes | Medium | Low | Track upstream closely |
| Type drift | Low | Medium | Generate from spec |
| Caching mismatch | Low | Low | Prefer server-side behavior; keep Elixir caching optional and shallow |

## Timeline

| Phase | Duration | Dependencies |
|-------|----------|--------------|
| App-server transport refactor | Sprint scope | `docs/20251214/multi_transport_refactor/07_phased_implementation_plan.md` |
| Skills types + `skills/list` | 1-2 days | App-server transport exists |
| Optional caching | 1 day | Skills list exists |
| Testing | 1-2 days | Above |

**Total**: Driven primarily by the app-server transport refactor; skills list itself is small once transport exists.

## Conclusion

The December 2025 upstream changes primarily affect the skills system, which is **already identified as a gap** in the Elixir port. The new SkillsManager architecture actually makes future porting easier by:

1. Moving to request/response pattern (vs push)
2. Centralizing caching logic
3. Providing clear protocol types

**Recommendation**: Implement the app-server transport first, then expose `skills/list`. Treat `UserInput::Skill` support as upstream-dependent (app-server v2 does not expose it today).
