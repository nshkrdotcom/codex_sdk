# Upstream Changes Summary

## Commit Range: d7ae342ff..987dd7fde

This document summarizes all 32 commits in the upstream pull.

---

## Commits by Category

### Config System

| Commit | Title | Impact |
|--------|-------|--------|
| `dc61fc5f5` | feat: support allowed_sandbox_modes in requirements.toml | **High** - New constraint system |
| `a6974087e` | chore: ensure ConfigLayerStack has access to cwd | Medium - Config discovery |
| `3d4ced3ff` | chore: migrate to ConfigBuilder | Low - Internal |
| `7e5c343ef` | feat: make ConstraintError an enum | **High** - Error structure |

### Models & Auth

| Commit | Title | Impact |
|--------|-------|--------|
| `f0dc6fd3c` | Rename OpenAI models to models manager | **Critical** - Module rename |
| `e3d344574` | Update models.json | Medium - Model presets |
| `8f0b38362` | model list | Low - UI only |

### Protocol & API

| Commit | Title | Impact |
|--------|-------|--------|
| `3429de21b` | feat: introduce ExternalSandbox policy | **High** - New sandbox type |
| `46baedd7c` | fix: change sandbox-state/update to request | Medium - Protocol |
| `9fb9ed6ce` | Set exclude to true by default in app server | Low - Default change |

### Skills

| Commit | Title | Impact |
|--------|-------|--------|
| `8120c8765` | Support admin scope skills | Medium - New scope |
| `f4371d2f6` | Add short descriptions to system skills | Medium - Metadata |
| `358a5baba` | Support skills shortDescription | Medium - API field |
| `37071e7e5` | Update system skills from OSS repo | Low - Content |
| `1cd1cf17c` | Update system skills bundled | Low - Content |
| `339b052d6` | Fix admin skills | Low - Bug fix |
| `dcc01198e` | UI tweaks on skills popup | Low - UI only |
| `d35337227` | skills feature default on | Medium - Default |
| `ba835c3c3` | Fix tests | Low - Tests |
| `eeda6a500` | Revert "Keep skills OFF for windows" | Low - Revert |
| `6f94a9079` | Keep skills OFF for windows | Low - Reverted |

### Feature Flags

| Commit | Title | Impact |
|--------|-------|--------|
| `987dd7fde` | Chore: remove rmcp feature and exp flag | Medium - Cleanup |
| `2d9826098` | fix: remove duplicate shell_snapshot FeatureSpec | Low - Cleanup |

### TUI (Skip for SDK)

| Commit | Title | Impact |
|--------|-------|--------|
| `63942b883` | feat(tui2): tune scrolling input | Skip - TUI only |
| `1d4463ba8` | feat(tui2): coalesce transcript scroll redraws | Skip - TUI only |
| `6c76d1771` | feat: collapse "waiting" of unified_exec | Skip - TUI only |

### Bug Fixes

| Commit | Title | Impact |
|--------|-------|--------|
| `014235f53` | Fix: /undo destructively interacts with git staging | Medium - Behavior |
| `0a7021de7` | fix: enable resume_warning missing from mod.rs | Low - Tests |
| `53f53173a` | chore: upgrade rmcp 0.10.0 to 0.12.0 | Low - Dependency |

### Other

| Commit | Title | Impact |
|--------|-------|--------|
| `ec3738b47` | feat: move file name derivation into codex-file-search | Low - Internal |
| `797a68b9f` | bump cargo-deny-action ver | Skip - CI |
| `b15b5082c` | Fix link to contributing.md | Skip - Docs |

---

## Detailed Change Analysis

### 1. Constraint System (Critical)

**What Changed**:
- New `Constrained<T>` wrapper type for config values
- `ConstraintError` is now an enum with `InvalidValue` and `EmptyField` variants
- Config values can be locked to specific allowed values via requirements

**Why It Matters**:
- Enterprise deployments can restrict sandbox modes
- Prevents misconfiguration in managed environments

**Elixir Implementation**:
```elixir
# New constrained value wrapper
%Codex.Config.Constrained{
  value: :workspace_write,
  constraint: {:only, [:workspace_write, :read_only]}
}
```

---

### 2. ExternalSandbox Policy (High)

**What Changed**:
- New `SandboxPolicy::ExternalSandbox` variant
- Takes `network_access: NetworkAccess` parameter
- Maps to `DangerFullAccess` filesystem behavior
- Designed for containerized/external sandbox environments

**Protocol Format**:
```json
{
  "sandboxPolicy": {
    "type": "external-sandbox",
    "network_access": "enabled"
  }
}
```

**CLI Format**:
```bash
codex exec --sandbox=external-sandbox
```

**Elixir Type**:
```elixir
:external_sandbox | {:external_sandbox, :enabled | :restricted}
```

---

### 3. Models Manager Refactor (Critical)

**What Changed**:
- Directory renamed: `openai_models/` → `models_manager/`
- Added `ModelsCache` struct for TTL-based caching
- New `model_presets.rs` with builtin presets
- Import paths changed in 32+ files

**Impact on Elixir**:
- `Codex.Models` module structure is fine (different naming)
- Verify preset values match (priority, upgrade, visibility)

**Key Preset Changes**:
| Model | Field | Old | New |
|-------|-------|-----|-----|
| gpt-5.1-codex-max | priority | 0 | 1 |
| gpt-5.1-codex-max | upgrade | null | gpt-5.2-codex |
| gpt-5.1-codex-mini | visibility | list | hide |
| gpt-5.1-codex-mini | priority | 1 | 0 |

---

### 4. Skills Enhancements (Medium)

**What Changed**:
1. New `SkillScope::Admin` (reads from `/etc/codex`)
2. Skills support `short_description` metadata field
3. Multiple skill content/script updates

**SKILL.md Format**:
```yaml
---
name: my-skill
description: Full multi-line description
metadata:
  short-description: One-line summary
---
```

**Elixir Type Update**:
```elixir
@type skill_scope :: :user | :repo | :system | :admin

@type skill_metadata :: %{
  name: String.t(),
  description: String.t(),
  short_description: String.t() | nil,  # NEW
  scope: skill_scope()
}
```

---

### 5. RMCP Feature Removal (Medium)

**What Changed**:
- Deleted `features.rmcp_client` flag
- Deleted `use_experimental_use_rmcp_client` check
- RMCP client is now always enabled (post-codesigning)

**Elixir Impact**:
- Remove any rmcp feature checks if present
- RMCP is now assumed to work everywhere

---

### 6. Git Undo Fix (Medium)

**What Changed**:
- Removed `--staged` flag from `git restore` in undo
- Working tree reverts but git staging area preserved
- Prevents data loss of staged changes

**Elixir Impact**:
- Pass-through behavior
- No SDK code changes needed
- Behavior inherits from CLI

---

### 7. Config CWD Threading (Low)

**What Changed**:
- `load_config_layers_state()` now accepts `cwd` parameter
- Searches for `.codex/config.toml` between cwd and project root
- `/config` endpoint in app-server handles optional cwd

**Elixir Impact**:
- When SDK passes `working_directory`, config discovery respects it
- No SDK code changes needed

---

### 8. TUI Scrolling (Skip)

**What Changed**:
- Extensive TUI2 scroll input normalization
- Per-terminal scroll event detection
- Auto wheel vs trackpad detection
- New config options under `[tui]`

**Elixir Impact**:
- SDK does not include TUI
- Users can configure via `~/.codex/config.toml`
- No SDK changes needed

---

## Summary Statistics

| Category | Commits | SDK Changes Needed |
|----------|---------|-------------------|
| Config/Constraints | 4 | Yes - new modules |
| Models | 3 | Verify presets |
| Protocol | 3 | Add types |
| Skills | 10 | Update types |
| Features | 2 | Maybe remove flag |
| TUI | 3 | None (skip) |
| Bug Fixes | 2 | None (CLI) |
| Other | 5 | None |
| **Total** | **32** | ~8 file changes |
