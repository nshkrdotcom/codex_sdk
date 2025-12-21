# Validation Findings and Corrections

## Critical Issues Found During Review

### 1. Models JSON Priority/Visibility Mismatch

**Issue**: The bundled `priv/models.json` is out of sync with upstream.

**Specific Mismatches Found**:

| Model | Field | Current (Elixir) | Upstream | Action |
|-------|-------|------------------|----------|--------|
| gpt-5.1-codex-max | priority | 0 | 1 | Update |
| gpt-5.1-codex-max | upgrade | null | "gpt-5.2-codex" | Update |
| gpt-5.1-codex-max | description | "Latest Codex-optimized..." | "Codex-optimized..." | Update |
| gpt-5.1-codex-mini | priority | 2 | 3 | Update |
| gpt-5.1-codex | visibility | "list" | "hide" | Update |

**Fix Required**:
```bash
# Copy upstream models.json
cp codex/codex-rs/core/models.json priv/models.json
```

Also verify `@local_presets` in `lib/codex/models.ex` for hardcoded values that may need updating.

---

### 2. Missing Params.ex Sandbox Serialization

**Issue**: The porting plan mentions adding `:external_sandbox` type but doesn't show the serialization code for `lib/codex/app_server/params.ex`.

**Required Addition** to `lib/codex/app_server/params.ex`:

```elixir
# In the sandbox_mode/1 function (around line 22-34):
def sandbox_mode(:external_sandbox), do: "external-sandbox"
def sandbox_mode({:external_sandbox, :enabled}), do: %{"type" => "external-sandbox", "network_access" => "enabled"}
def sandbox_mode({:external_sandbox, :restricted}), do: %{"type" => "external-sandbox", "network_access" => "restricted"}
```

The serialization format depends on whether CLI expects string or struct:
- For CLI args: `"external-sandbox"` or `"external-sandbox --network-access=enabled"`
- For protocol: JSON object with type and network_access fields

---

### 3. Constrained Module Justification

**Question**: Is `Codex.Config.Constrained` for user-facing API or internal SDK validation?

**Clarification**: This is primarily for internal SDK validation when parsing config from `requirements.toml`. Since the Elixir SDK does NOT currently parse `requirements.toml` (this is done by the codex CLI), the Constrained module is:

1. **Nice to have** for future compatibility if SDK starts parsing config
2. **Documentstion purposes** to align type naming with upstream
3. **Low priority** unless SDK exposes config validation APIs

**Recommendation**: Create the module but mark it as `@moduledoc false` (internal) for now.

---

### 4. Protocol Type Location

**Issue**: The plan says to add types to `lib/codex/app_server/protocol.ex`, but that file is only 90 lines of JSON-RPC encoding/decoding.

**Correction**: Protocol types should go in:
- `lib/codex/items.ex` for item-related types (skills, etc.)
- `lib/codex/thread/options.ex` for thread options (sandbox, network_access)
- Create `lib/codex/app_server/types.ex` if needed for protocol-specific types

---

### 5. Missing Examples

**Issue**: No examples demonstrate new features.

**Recommended New Examples**:

1. **`examples/external_sandbox_mode.exs`**:
```elixir
# Demonstrate external sandbox usage in containerized environments
{:ok, opts} = Codex.Thread.Options.new(sandbox: {:external_sandbox, :enabled})
{:ok, thread} = Codex.start_thread(%Codex.Options{}, opts)
```

2. **Update existing examples** that use sandbox modes to include `:external_sandbox` as an option.

---

### 6. RMCP Feature Flag Status

**Finding**: Searched for "rmcp" in lib/ and test/ - no results found.

**Conclusion**: Phase 3.3 (RMCP removal) is **already complete** or was never implemented. Skip this task.

---

### 7. Documentation Updates

**Missing Documentation**:

1. **README.md** - Add external_sandbox to sandbox modes list
2. **docs/09-app-server-transport.md** - Add:
   - External sandbox mode description
   - Network access configuration
   - Admin skills (`/etc/codex`)

---

## Updated Implementation Checklist

Based on validation findings, update the checklist:

### Phase 1 - Critical (Updated)

- [ ] **Copy upstream models.json** to `priv/models.json`
  - `cp codex/codex-rs/core/models.json priv/models.json`
- [ ] **Verify `@local_presets`** in `lib/codex/models.ex` match upstream for:
  - Priority values
  - Upgrade references
  - Visibility settings
- [ ] **Add sandbox serialization** to `lib/codex/app_server/params.ex`:
  - Handle `:external_sandbox` atom
  - Handle `{:external_sandbox, network_access}` tuple
- [ ] **Add sandbox type** to `lib/codex/thread/options.ex`

### Phase 1.5 - Optional Modules

- [ ] Create `lib/codex/config/constrained.ex` (mark as internal with `@moduledoc false`)
- [ ] Create `lib/codex/config/constraint_error.ex`

### Phase 2 - High (Updated)

- [ ] Add types to correct locations:
  - `skill_scope: :admin` in items or wherever skills are defined
  - `network_access` type in thread/options or protocol types
  - `short_description` in skill metadata types

### Phase 3 - Medium (Updated)

- [x] ~~RMCP removal~~ - Already complete (not found in codebase)
- [ ] Add examples for external sandbox
- [ ] Update documentation

### Phase 4 - Testing (Updated)

- [ ] Add model preset regression test
- [ ] Add external sandbox serialization test
- [ ] Add integration test with both network modes

---

## Corrected Files List

### Must Modify

| File | Change |
|------|--------|
| `priv/models.json` | Replace with upstream copy |
| `lib/codex/models.ex` | Verify/update `@local_presets` |
| `lib/codex/thread/options.ex` | Add `:external_sandbox` type |
| `lib/codex/app_server/params.ex` | Add sandbox tuple serialization |
| `mix.exs` | Version bump |
| `README.md` | Version and sandbox docs |
| `CHANGELOG.md` | Release notes |

### Should Modify

| File | Change |
|------|--------|
| `lib/codex/items.ex` | Add skill short_description, admin scope |
| `docs/09-app-server-transport.md` | Sandbox constraints, external mode |

### Optional (Future)

| File | Change |
|------|--------|
| `lib/codex/config/constrained.ex` | Create (internal) |
| `lib/codex/config/constraint_error.ex` | Create |
| `examples/external_sandbox_mode.exs` | Create demo |

---

## Pre-Implementation Verification Checklist

Before starting implementation:

- [ ] Confirm `codex/codex-rs/core/models.json` is at commit `987dd7fde`
- [ ] Compare current `priv/models.json` with upstream (diff them)
- [ ] Identify all sandbox mode usages in codebase (grep for "sandbox")
- [ ] Confirm skill-related types are in `lib/codex/items.ex`
- [ ] Run `mix test` to establish baseline
