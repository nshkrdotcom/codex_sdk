# Version Bump Instructions

## Version Determination

Based on the upstream changes:
- No breaking changes to existing APIs
- All changes are additive (new types, new enum values)
- Existing behavior unchanged

**Recommended Version**: `0.4.2`

If you consider `external_sandbox` a significant feature addition: `0.5.0`

---

## Files to Update

### 1. mix.exs

Change line 4:

```diff
- @version "0.4.1"
+ @version "0.4.2"
```

### 2. README.md

Update installation section (~line 37):

```diff
- {:codex_sdk, "~> 0.4.1"}
+ {:codex_sdk, "~> 0.4.2"}
```

Update Project Status section (~line 561):

```diff
- **Current Version**: 0.4.1 (Model registry port)
+ **Current Version**: 0.4.2 (Upstream sync: constraints, external sandbox)
```

### 3. CHANGELOG.md

Add new entry at top (after header, before [0.4.1]):

```markdown
## [0.4.2] - 2025-12-20

### Added

- `Codex.Config.Constrained` module for constrained configuration values with validation
- `Codex.Config.ConstraintError` exception for constraint violations
- `:external_sandbox` mode for containerized/external sandbox environments
- `{:external_sandbox, :enabled | :restricted}` tuple variant with network access control
- `:admin` scope for skills (reads from `/etc/codex`)
- `short_description` field support in skill metadata

### Changed

- Updated model presets to match upstream:
  - `gpt-5.1-codex-max`: priority 0 → 1, now upgrades to `gpt-5.2-codex`
  - `gpt-5.1-codex-mini`: visibility `:list` → `:hide`, priority 1 → 0

### Documentation

- Added `docs/20251220/` porting plan documentation
- Updated `docs/09-app-server-transport.md` with sandbox constraints
- Documented `allowed_sandbox_modes` in requirements.toml

### Internal

- Synced with upstream commits d7ae342ff..987dd7fde (32 commits)
```

---

## Complete CHANGELOG Entry

Here's the full entry to copy-paste:

```markdown
## [0.4.2] - 2025-12-20

### Added

- `Codex.Config.Constrained` module for wrapping configuration values with validation constraints
- `Codex.Config.ConstraintError` exception for reporting constraint violations
- `:external_sandbox` sandbox mode for containerized/external sandbox environments
- `{:external_sandbox, :enabled | :restricted}` tuple variant with explicit network access control
- `:admin` scope for skills (reads from `/etc/codex` in addition to user/repo/system)
- `short_description` optional field in skill metadata

### Changed

- Updated model presets to match upstream codex-rs:
  - `gpt-5.1-codex-max`: priority 0 → 1, now upgrades to `gpt-5.2-codex`
  - `gpt-5.1-codex-mini`: visibility `:list` → `:hide`, priority 1 → 0
- Updated bundled `priv/models.json` to latest upstream version

### Documentation

- Added `docs/20251220/` directory with comprehensive porting plan
- Updated `docs/09-app-server-transport.md` with sandbox constraints documentation
- Documented `allowed_sandbox_modes` for requirements.toml configuration

### Internal

- Synced with upstream codex-rs commits d7ae342ff..987dd7fde (32 commits)
- Added constraint system aligned with upstream `Constrained<T>` type
```

---

## Verification Commands

After updating, run:

```bash
# Format check
mix format --check-formatted

# Compile check
mix compile --warnings-as-errors

# Run tests
mix test

# Generate docs (verify version appears)
mix docs

# Verify version
mix run -e "IO.puts(Application.spec(:codex_sdk, :vsn))"
# Should output: 0.4.2
```

---

## Git Commit

After all changes:

```bash
git add -A
git commit -m "Release v0.4.2: Upstream sync (constraints, external sandbox, skills)

Port upstream codex-rs changes from d7ae342ff..987dd7fde:
- Add Constrained config wrapper and ConstraintError
- Add :external_sandbox mode with network access control
- Add :admin skill scope and short_description field
- Update model presets (priority, visibility, upgrades)
- Sync bundled models.json

Documentation:
- Add docs/20251220/ porting plan
- Update app-server transport docs

Internal: 32 upstream commits"
```

---

## Release Checklist

- [ ] All tests pass (`mix test`)
- [ ] Dialyzer clean (`MIX_ENV=dev mix dialyzer`)
- [ ] Credo clean (`mix credo --strict`)
- [ ] Format clean (`mix format --check-formatted`)
- [ ] Docs generate (`mix docs`)
- [ ] Version correct in mix.exs
- [ ] Version correct in README.md
- [ ] CHANGELOG.md updated
- [ ] Git committed
- [ ] Git pushed
- [ ] PR created (if using PRs)
- [ ] PR merged
- [ ] Tag created: `git tag v0.4.2`
- [ ] Tag pushed: `git push origin v0.4.2`
- [ ] Hex publish: `mix hex.publish` (if publishing to Hex)

---

## Alternative: Major Version (0.5.0)

If you prefer a minor version bump to signal the new sandbox mode:

**mix.exs**: `@version "0.5.0"`

**CHANGELOG.md header**: `## [0.5.0] - 2025-12-20`

**Commit message**:
```
Release v0.5.0: External sandbox support and constraint system
```

This signals to users that there's meaningful new functionality, though technically nothing is breaking.

---

## Rollback Instructions

If issues are discovered after release:

```bash
# Revert to previous version
git revert HEAD

# Create hotfix tag
git tag v0.4.2.1  # or v0.4.3

# Push
git push origin master --tags
```

---

## Post-Release

1. Update any downstream dependencies
2. Announce release (if applicable)
3. Monitor for issues
4. Close related GitHub issues
