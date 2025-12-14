# Technical Porting Plan: December 2025 Upstream Changes

## Executive Summary

The upstream pull (a2c86e5d8..5d77d4db6) introduces a **single major change**: reimplementation of skills loading using SkillsManager and skills/list operation.

**Impact Assessment**:
- Skills were already NOT implemented in Elixir
- New changes make skills MORE portable (request/response vs push)
- Requires an app-server transport (exec JSONL does not expose `Op::ListSkills` / `skills/list`)

**Update (Decision)**:
- Proceed with an app-server transport refactor (see `docs/20251214/multi_transport_refactor/README.md`)
- Then implement `skills/list` on that transport

## Changes Requiring Porting

### 1. SkillsManager & Skills System

**Priority**: Medium (blocked on transport)

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

**Required Elixir Work** (if proceeding):
```
lib/codex/skills/
├── manager.ex      # GenServer with ETS caching
├── metadata.ex     # SkillMetadata struct
├── error.ex        # SkillError struct
├── scope.ex        # :user | :repo type
├── load_outcome.ex # SkillLoadOutcome struct
└── list_entry.ex   # SkillsListEntry struct
```

**Estimated Effort**: 500-800 lines

### 2. Protocol Types

**Priority**: Medium (blocked on transport)

**New Rust Types**:
```rust
Op::ListSkills { cwds: Vec<PathBuf> }
EventMsg::ListSkillsResponse(ListSkillsResponseEvent)
SkillsListEntry { cwd, skills, errors }
SkillScope { User, Repo }
```

**Required Elixir Work**:
```elixir
# In operations module
def list_skills(cwds \\ [])

# In events.ex
defmodule Codex.Events.ListSkillsResponse

# In skills/
defmodule Codex.Skills.Scope
defmodule Codex.Skills.Metadata
defmodule Codex.Skills.ListEntry
```

**Estimated Effort**: 200-300 lines

### 3. API Changes

**Priority**: N/A (if not using core protocol)

The Rust API changes (Codex::spawn signature, etc.) only matter if Elixir adopts core protocol. Current exec-based approach abstracts these.

## Porting Decision Matrix

| Component | Transport Required | Current Elixir | Action |
|-----------|-------------------|----------------|--------|
| SkillsManager | Core protocol | exec JSONL | Implement via app-server-backed skills/list |
| Op::ListSkills | Core protocol | exec JSONL | Prefer app-server `skills/list` endpoint |
| ListSkillsResponse | Core protocol | exec JSONL | Prefer app-server response types |
| SkillScope enum | Any | None | Port when skills added |
| SkillMetadata | Any | None | Port when skills added |

## Recommended Approach

### Option A: Defer All Skills Work (Recommended)

**Rationale**:
1. Skills require core protocol transport
2. Transport decision is Phase 0 of existing plan
3. No value in partial implementation

**Action**:
- Document the gap
- Wait for Phase 0 transport decision
- Port skills after transport is resolved

### Option B: Port Types Only

**Rationale**:
- Get type definitions in place
- Easier integration later

**Downside**:
- Dead code until transport change
- May drift from upstream

**Not Recommended**

### Option C: Implement Client-Side Discovery

**Rationale**:
- Elixir discovers skills itself (no protocol needed)
- Independent of transport

**Downside**:
- Duplicates Rust logic
- Different caching strategy
- Maintenance burden

**Not Recommended**

## Implementation Plan (If Proceeding)

### Prerequisites

1. Complete Phase 0 transport decision
2. If adopting core/app-server protocol:
   - Implement protocol encoding/decoding
   - Add event stream handling
   - Test protocol compatibility

### Phase 1: Type Definitions (Day 1)

```elixir
# Create lib/codex/skills/ directory
# Add basic structs without behavior

defmodule Codex.Skills.Scope do
  @type t :: :user | :repo
end

defmodule Codex.Skills.Metadata do
  use TypedStruct
  typedstruct do
    field :name, String.t(), enforce: true
    field :description, String.t(), enforce: true
    field :path, String.t(), enforce: true
    field :scope, Codex.Skills.Scope.t(), enforce: true
  end
end

defmodule Codex.Skills.Error do
  use TypedStruct
  typedstruct do
    field :path, String.t(), enforce: true
    field :message, String.t(), enforce: true
  end
end

defmodule Codex.Skills.LoadOutcome do
  use TypedStruct
  typedstruct do
    field :skills, [Codex.Skills.Metadata.t()], default: []
    field :errors, [Codex.Skills.Error.t()], default: []
  end
end

defmodule Codex.Skills.ListEntry do
  use TypedStruct
  typedstruct do
    field :cwd, String.t(), enforce: true
    field :skills, [Codex.Skills.Metadata.t()], default: []
    field :errors, [Codex.Skills.Error.t()], default: []
  end
end
```

### Phase 2: Event Handling (Day 2)

```elixir
# Add to events.ex
defmodule Codex.Events.ListSkillsResponse do
  use TypedStruct
  typedstruct do
    field :skills, [Codex.Skills.ListEntry.t()], default: []
  end
end

# Add event parsing in event handler
def parse_event(%{"type" => "list_skills_response"} = data) do
  %Codex.Events.ListSkillsResponse{
    skills: parse_list_entries(data["skills"])
  }
end
```

### Phase 3: Operation Support (Day 3)

```elixir
# Add to thread.ex or new skills module
def list_skills(thread, cwds \\ []) do
  # Submit Op::ListSkills via protocol
  # Wait for ListSkillsResponse event
  # Return skills
end
```

### Phase 4: Manager (Optional, Day 4-5)

```elixir
# GenServer with ETS caching (if client-side caching desired)
defmodule Codex.Skills.Manager do
  use GenServer

  def skills_for_cwd(cwd) do
    GenServer.call(__MODULE__, {:skills_for_cwd, cwd})
  end

  # ... ETS caching implementation
end
```

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
# test/codex/skills_test.exs
describe "list_skills/2" do
  @tag :integration
  test "returns skills for cwd" do
    # Requires core protocol connection
    {:ok, thread} = Codex.start_thread()
    {:ok, response} = Codex.Skills.list_skills(thread)
    assert is_list(response.skills)
  end
end
```

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Transport incompatibility | High | High | Wait for Phase 0 |
| Upstream changes | Medium | Low | Track upstream closely |
| Type drift | Low | Medium | Generate from spec |
| Caching mismatch | Low | Low | Match Rust behavior |

## Timeline

| Phase | Duration | Dependencies |
|-------|----------|--------------|
| Phase 0 (Transport) | TBD | Business decision |
| Phase 1 (Types) | 1 day | Phase 0 complete |
| Phase 2 (Events) | 1 day | Phase 1 |
| Phase 3 (Operations) | 1 day | Phase 2 |
| Phase 4 (Manager) | 2 days | Phase 3 (optional) |
| Testing | 2 days | All phases |

**Total**: ~7 days after Phase 0 decision

## Conclusion

The December 2025 upstream changes primarily affect the skills system, which is **already identified as a gap** in the Elixir port. The new SkillsManager architecture actually makes future porting easier by:

1. Moving to request/response pattern (vs push)
2. Centralizing caching logic
3. Providing clear protocol types

**Recommendation**: Implement the app-server transport first, then expose `skills/list`. Treat `UserInput::Skill` support as upstream-dependent (app-server v2 does not expose it today).
