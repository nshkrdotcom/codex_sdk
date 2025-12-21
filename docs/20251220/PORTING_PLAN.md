# Porting Plan: d7ae342ff..987dd7fde

## Executive Summary

This document provides a comprehensive plan for porting upstream codex-rs changes to the Elixir SDK. The changes span config system enhancements, protocol updates, model management refactoring, and various bug fixes.

---

## Phase 1: Critical Changes (Models + Constraints)

### 1.1 Models Manager Refactoring

**Upstream Change**: Renamed `openai_models/` to `models_manager/` with enhanced caching.

**Elixir Impact**: The Elixir SDK already has `Codex.Models` which is analogous. Review for any new functionality.

#### Changes Required in `lib/codex/models.ex`

1. **Add ModelsCache struct support** (if caching remote models):
   ```elixir
   @type models_cache :: %{
     etag: String.t() | nil,
     fetched_at: DateTime.t(),
     models: [model_info()]
   }
   ```

2. **Verify model presets match upstream** - Check `@local_presets` against:
   - `gpt-5.1-codex-max`: Priority now 1, has upgrade to `gpt-5.2-codex`
   - `gpt-5.1-codex-mini`: Visibility now `:hide`, priority 0
   - Ensure upgrade metadata aligns

3. **No API changes expected** - Internal refactoring only

**Files to Modify**:
- `lib/codex/models.ex` - Verify presets match upstream
- `priv/models.json` - Update bundled models if changed

---

### 1.2 Constraint System (Constrained<T>)

**Upstream Change**: New `Constrained<T>` wrapper type for validated configuration values.

**Elixir Implementation**: Create a new module for constrained values.

#### New Module: `lib/codex/config/constrained.ex`

```elixir
defmodule Codex.Config.Constrained do
  @moduledoc """
  Wrapper type for configuration values with validation constraints.

  Used for approval policies and sandbox policies that may be restricted
  by requirements.toml or managed_config.toml.
  """

  @type constraint(t) :: :any | {:only, [t]} | {:not, [t]}

  @type t(value_type) :: %__MODULE__{
    value: value_type,
    constraint: constraint(value_type)
  }

  defstruct [:value, constraint: :any]

  @doc "Create with no constraints (any value allowed)"
  def allow_any(value), do: %__MODULE__{value: value, constraint: :any}

  @doc "Create with only specific values allowed"
  def allow_only(value, allowed) when is_list(allowed) do
    %__MODULE__{value: value, constraint: {:only, allowed}}
  end

  @doc "Create with specific values disallowed"
  def allow_not(value, disallowed) when is_list(disallowed) do
    %__MODULE__{value: value, constraint: {:not, disallowed}}
  end

  @doc "Check if a value can be set (without mutating)"
  def can_set?(%__MODULE__{constraint: :any}, _candidate), do: true
  def can_set?(%__MODULE__{constraint: {:only, allowed}}, candidate) do
    candidate in allowed
  end
  def can_set?(%__MODULE__{constraint: {:not, disallowed}}, candidate) do
    candidate not in disallowed
  end

  @doc "Attempt to set a value, returning error if constrained"
  def set(%__MODULE__{} = constrained, candidate) do
    if can_set?(constrained, candidate) do
      {:ok, %{constrained | value: candidate}}
    else
      {:error, constraint_error(constrained.constraint, candidate)}
    end
  end

  defp constraint_error({:only, allowed}, candidate) do
    %Codex.Config.ConstraintError{
      type: :invalid_value,
      candidate: inspect(candidate),
      allowed: inspect(allowed)
    }
  end

  defp constraint_error({:not, disallowed}, candidate) do
    %Codex.Config.ConstraintError{
      type: :invalid_value,
      candidate: inspect(candidate),
      disallowed: inspect(disallowed)
    }
  end
end
```

#### New Module: `lib/codex/config/constraint_error.ex`

```elixir
defmodule Codex.Config.ConstraintError do
  @moduledoc """
  Error raised when a configuration constraint is violated.
  """

  @type t :: %__MODULE__{
    type: :invalid_value | :empty_field,
    candidate: String.t() | nil,
    allowed: String.t() | nil,
    disallowed: String.t() | nil,
    field_name: String.t() | nil
  }

  defexception [:type, :candidate, :allowed, :disallowed, :field_name]

  @impl true
  def message(%{type: :invalid_value, candidate: candidate, allowed: allowed}) do
    "Invalid value #{candidate}; allowed values: #{allowed}"
  end

  def message(%{type: :empty_field, field_name: field}) do
    "Field #{field} cannot be empty"
  end
end
```

**Files to Create**:
- `lib/codex/config/constrained.ex`
- `lib/codex/config/constraint_error.ex`

**Files to Modify**:
- `lib/codex/thread/options.ex` - Use Constrained for sandbox/approval policies

---

### 1.3 ExternalSandbox Policy

**Upstream Change**: New `SandboxPolicy::ExternalSandbox` variant for containerized environments.

**Elixir Implementation**: Add new sandbox mode.

#### Update `lib/codex/thread/options.ex`

Add to sandbox type:
```elixir
@type sandbox ::
  :default |
  :strict |
  :permissive |
  :read_only |
  :workspace_write |
  :danger_full_access |
  :external_sandbox |
  {:external_sandbox, network_access :: :enabled | :restricted}
```

#### Update Sandbox Mode Mapping

Wherever sandbox modes are converted to CLI args or protocol values:

```elixir
defp sandbox_to_arg(:external_sandbox), do: "--sandbox=external-sandbox"
defp sandbox_to_arg({:external_sandbox, :enabled}), do: "--sandbox=external-sandbox --network-access=enabled"
defp sandbox_to_arg({:external_sandbox, :restricted}), do: "--sandbox=external-sandbox"
```

**Files to Modify**:
- `lib/codex/thread/options.ex` - Add type
- `lib/codex/exec/options.ex` - Handle new mode
- `lib/codex/app_server/params.ex` - Serialize for protocol

---

## Phase 2: High Priority Changes (Config + Protocol)

### 2.1 ConfigRequirements (allowed_sandbox_modes)

**Upstream Change**: New `allowed_sandbox_modes` field in `requirements.toml`.

**Elixir Implementation**: If SDK parses requirements.toml (unlikely), add support. Otherwise document for users.

#### Documentation Update

Add to `docs/09-app-server-transport.md`:

```markdown
### Sandbox Mode Constraints

Administrators can restrict available sandbox modes via `requirements.toml`:

```toml
allowed_sandbox_modes = ["workspace-write", "read-only"]
```

When constrained, attempts to use disallowed modes will fail with a constraint error.
```

**Files to Modify**:
- `docs/09-app-server-transport.md` - Document constraint
- If SDK reads requirements: `lib/codex/config/requirements.ex` (new)

---

### 2.2 Protocol V2 Updates

**Upstream Changes**:
1. `NetworkAccess` enum moved to protocol
2. New `SkillScope::Admin` variant
3. Skills support `short_description` field

#### Update Protocol Types

In `lib/codex/app_server/protocol.ex` or relevant module:

```elixir
@type network_access :: :restricted | :enabled

@type skill_scope :: :user | :repo | :system | :admin

@type skill_metadata :: %{
  name: String.t(),
  description: String.t(),
  short_description: String.t() | nil,
  scope: skill_scope()
}
```

**Files to Modify**:
- `lib/codex/app_server/protocol.ex` - Add types
- `lib/codex/items.ex` - If skills surfaced as items

---

### 2.3 TUI Scrolling Configuration

**Upstream Change**: Extensive TUI2 scrolling config options.

**Elixir Impact**: **SKIP** - SDK does not include TUI. Document for users who configure `~/.codex/config.toml`.

**Documentation Only**: Add to a config reference if maintained.

---

## Phase 3: Medium Priority Changes

### 3.1 Skills Short Description

**Upstream Change**: Skills YAML now supports `short-description` metadata field.

**Elixir Implementation**: Update skill parsing if SDK reads SKILL.md files.

```elixir
@type skill :: %{
  name: String.t(),
  description: String.t(),
  short_description: String.t() | nil,  # NEW
  scope: skill_scope()
}
```

**Files to Modify**:
- Any skill parsing code (likely pass-through from CLI)
- Type definitions if skills are structured

---

### 3.2 Skills Admin Scope

**Upstream Change**: New admin-level skill scope reading from `/etc/codex`.

**Elixir Impact**: Pass-through; SDK doesn't directly read skill directories.

**Documentation**: Note that admin skills are now supported.

---

### 3.3 RMCP Feature Flag Removal

**Upstream Change**: Removed `features.rmcp_client` flag; RMCP is now default.

**Elixir Impact**: If SDK has rmcp feature gating, remove it.

**Files to Check**:
- Search for `rmcp` in codebase
- Remove any feature flag checks

---

### 3.4 Git Undo Staging Fix

**Upstream Change**: `/undo` no longer clears git staging area.

**Elixir Impact**: Pass-through behavior from CLI. No SDK changes needed.

**Testing**: Verify via CLI that staging is preserved.

---

## Phase 4: Low Priority Changes

### 4.1 File Search Centralization

**Upstream Change**: File name derivation moved to `codex-file-search` crate.

**Elixir Impact**: None - internal Rust refactoring.

---

### 4.2 ConfigLayerStack CWD Threading

**Upstream Change**: Config loading now respects per-thread cwd for `.codex/config.toml` discovery.

**Elixir Impact**: If SDK invokes CLI with cwd, behavior should inherit automatically.

**Documentation**: Note that working_directory affects config discovery.

---

## Implementation Checklist

### Critical (Do First)
- [ ] Verify `Codex.Models` presets match upstream
- [ ] Update `priv/models.json` if needed
- [ ] Create `Codex.Config.Constrained` module
- [ ] Create `Codex.Config.ConstraintError` module
- [ ] Add `:external_sandbox` to sandbox types
- [ ] Update sandbox mode serialization

### High Priority
- [ ] Add `network_access` type to protocol
- [ ] Add `skill_scope: :admin` variant
- [ ] Add `short_description` to skill types
- [ ] Document `allowed_sandbox_modes` in requirements

### Medium Priority
- [ ] Remove rmcp feature flag references (if any)
- [ ] Update skill metadata types
- [ ] Add test for external_sandbox mode

### Low Priority
- [ ] Document cwd-aware config discovery
- [ ] Review file search for any exposed APIs

---

## Breaking Changes Assessment

**Potentially Breaking**:
1. New `:external_sandbox` value in sandbox enum - **Additive, not breaking**
2. Constrained wrapper type - **New module, not breaking**
3. Skills short_description - **Optional field, not breaking**
4. Admin skill scope - **New enum value, not breaking**

**Recommendation**: Release as **0.4.2** (patch) since all changes are additive.

---

## Testing Strategy

### Unit Tests

1. **Constrained module tests**:
   - `allow_any/1` allows all values
   - `allow_only/2` rejects non-listed values
   - `set/2` returns error for constrained violations

2. **Sandbox mode tests**:
   - `:external_sandbox` serializes correctly
   - `{:external_sandbox, :enabled}` includes network flag

3. **Protocol type tests**:
   - Skill metadata parses `short_description`
   - `skill_scope: :admin` round-trips

### Integration Tests

1. Run with `--sandbox=external-sandbox` (if CLI supports)
2. Verify skill listing includes `short_description`

### Live Tests

1. Test admin skills if `/etc/codex` is configured
2. Verify git undo preserves staging

---

## Files Summary

### New Files
- `lib/codex/config/constrained.ex`
- `lib/codex/config/constraint_error.ex`
- `test/codex/config/constrained_test.exs`
- `docs/20251220/*.md` (this documentation)

### Modified Files
- `lib/codex/models.ex` - Verify presets
- `lib/codex/thread/options.ex` - Add external_sandbox
- `lib/codex/exec/options.ex` - Handle new sandbox
- `lib/codex/app_server/params.ex` - Serialize sandbox
- `lib/codex/app_server/protocol.ex` - Protocol types
- `priv/models.json` - Update if needed
- `mix.exs` - Version bump
- `README.md` - Version in docs
- `CHANGELOG.md` - Release notes

### Documentation Updates
- `docs/09-app-server-transport.md` - Sandbox constraints
- `README.md` - Version badge update
