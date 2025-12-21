# Implementation Checklist

## Pre-Implementation

- [ ] Pull latest upstream codex (already done: d7ae342ff..987dd7fde)
- [ ] Review this documentation
- [ ] Create feature branch: `git checkout -b feat/upstream-port-20251220`

---

## Phase 1: Critical (Constraint System + Sandbox)

### 1.1 Create Constraint Modules

- [ ] Create `lib/codex/config/constrained.ex`
  - [ ] Define `Codex.Config.Constrained` struct
  - [ ] Implement `allow_any/1`
  - [ ] Implement `allow_only/2`
  - [ ] Implement `allow_not/2`
  - [ ] Implement `can_set?/2`
  - [ ] Implement `set/2`

- [ ] Create `lib/codex/config/constraint_error.ex`
  - [ ] Define exception struct
  - [ ] Implement `:invalid_value` message
  - [ ] Implement `:empty_field` message

- [ ] Create `test/codex/config/constrained_test.exs`
  - [ ] Test `allow_any/1`
  - [ ] Test `allow_only/2` accepts valid values
  - [ ] Test `allow_only/2` rejects invalid values
  - [ ] Test `set/2` returns `{:ok, _}` for valid
  - [ ] Test `set/2` returns `{:error, _}` for invalid

### 1.2 Add ExternalSandbox Mode

- [ ] Update `lib/codex/thread/options.ex`
  - [ ] Add `:external_sandbox` to `@type sandbox`
  - [ ] Add `{:external_sandbox, network_access}` tuple variant
  - [ ] Update typespec documentation

- [ ] Update `lib/codex/exec/options.ex`
  - [ ] Handle `:external_sandbox` in sandbox_to_args
  - [ ] Handle network_access parameter

- [ ] Update `lib/codex/app_server/params.ex`
  - [ ] Serialize `:external_sandbox` for protocol
  - [ ] Include network_access in payload

- [ ] Create test for external_sandbox
  - [ ] Test CLI arg generation
  - [ ] Test protocol serialization

### 1.3 Verify Models

- [ ] Compare `lib/codex/models.ex` presets with upstream
  - [ ] Check gpt-5.1-codex-max priority (should be 1)
  - [ ] Check gpt-5.1-codex-max upgrade (should be gpt-5.2-codex)
  - [ ] Check gpt-5.1-codex-mini visibility (should be :hide)

- [ ] Update `priv/models.json` if changed
  - [ ] Download latest from codex-rs/core/models.json
  - [ ] Verify JSON parses correctly

---

## Phase 2: High Priority (Protocol + Config)

### 2.1 Protocol Updates

- [ ] Update `lib/codex/app_server/protocol.ex`
  - [ ] Add `@type network_access :: :restricted | :enabled`
  - [ ] Add `:admin` to skill_scope type
  - [ ] Add `short_description` to skill metadata type

- [ ] Update any skill parsing code
  - [ ] Handle `short_description` field (optional)
  - [ ] Handle `:admin` scope

### 2.2 Documentation Updates

- [ ] Update `docs/09-app-server-transport.md`
  - [ ] Document `allowed_sandbox_modes` in requirements.toml
  - [ ] Document external_sandbox mode
  - [ ] Document admin skills scope

---

## Phase 3: Medium Priority

### 3.1 Feature Flag Cleanup

- [ ] Search codebase for "rmcp"
  - [ ] `grep -r "rmcp" lib/`
  - [ ] `grep -r "rmcp" test/`
  - [ ] Remove any feature flag checks

### 3.2 Skills Types

- [ ] Update skill-related types for short_description
- [ ] Verify admin scope handling

### 3.3 Tests

- [ ] Add test for external_sandbox mode
- [ ] Add test for skill short_description parsing
- [ ] Run full test suite: `mix test`

---

## Phase 4: Low Priority

### 4.1 Documentation

- [ ] Document cwd-aware config discovery in working_directory docs
- [ ] Review file_search API (if exposed)

---

## Release Preparation

### Version Bump

- [ ] Update `mix.exs` version: `@version "0.4.2"` (or 0.5.0 if breaking)
- [ ] Update `README.md` installation section
- [ ] Update `README.md` version badges if hardcoded

### Changelog

- [ ] Add CHANGELOG.md entry for 2025-12-20
- [ ] List all new features
- [ ] List all breaking changes (if any)
- [ ] Note upstream commit range

### Quality Checks

- [ ] Run `mix format`
- [ ] Run `mix credo --strict`
- [ ] Run `MIX_ENV=dev mix dialyzer`
- [ ] Run `mix test`
- [ ] Run `CODEX_TEST_LIVE=true mix test --include live` (optional)
- [ ] Run `mix codex.verify`

### Documentation Build

- [ ] Run `mix docs`
- [ ] Review generated docs
- [ ] Verify new modules appear

### Git

- [ ] Stage all changes
- [ ] Commit with descriptive message
- [ ] Push feature branch
- [ ] Create PR

---

## Verification Checklist

### Functional Tests

- [ ] Basic thread creation works
- [ ] External sandbox mode accepted
- [ ] Model defaults unchanged for API auth
- [ ] Model defaults unchanged for ChatGPT auth

### Integration Tests

- [ ] App-server transport works
- [ ] Skills list includes short_description
- [ ] Constraint errors have proper messages

### Live Tests (Optional)

- [ ] Test with real CLI
- [ ] Verify external-sandbox if environment supports

---

## Rollback Plan

If issues discovered:
1. Revert commit: `git revert <commit>`
2. Publish hotfix version (e.g., 0.4.3)
3. Document issue in GitHub

---

## Notes

### Files Changed Summary

**New Files** (4):
```
lib/codex/config/constrained.ex
lib/codex/config/constraint_error.ex
test/codex/config/constrained_test.exs
docs/20251220/*.md
```

**Modified Files** (~10):
```
lib/codex/models.ex
lib/codex/thread/options.ex
lib/codex/exec/options.ex
lib/codex/app_server/params.ex
lib/codex/app_server/protocol.ex
priv/models.json (if needed)
mix.exs
README.md
CHANGELOG.md
docs/09-app-server-transport.md
```
