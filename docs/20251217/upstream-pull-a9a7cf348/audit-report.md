# Independent Audit Report: Upstream Pull Analysis (5d77d4db6..a9a7cf348)

**Date**: 2025-12-17
**Auditor**: Independent verification agent
**Target**: `docs/20251217/upstream-pull-a9a7cf348/porting-notes.md`

---

## 1. Independent Upstream Change Summary

### Verified Upstream State

- **Current HEAD**: `a9a7cf3488ba9ecfecd2c58a41836f1d1598141d`
- **Previous HEAD**: `5d77d4db6be0e42d40dca60608bbe135b24173f4`
- **Commit count**: 72 commits
- **Files changed**: 184 files (~11k insertions / 2.3k deletions)

### Changes by Subsystem (Ranked by Port Risk)

#### CRITICAL (Breaking Protocol Changes)

| Change | Commit(s) | Upstream Files | Port Risk |
|--------|-----------|----------------|-----------|
| `thread/compact` API removed | `412dd3795` | `common.rs`, `v2.rs`, `codex_message_processor.rs` | **CRITICAL** |
| `mcpServers/list` → `mcpServerStatus/list` | `600d01b33`, `370279388` | `common.rs`, `v2.rs`, `codex_message_processor.rs`, `README.md` | **CRITICAL** |
| `ConfigLayerName` → `ConfigLayerSource` (tagged union) | `de3fa03e1` | `v2.rs` | **HIGH** |

#### HIGH (Protocol Additions / Behavior Changes)

| Change | Commit(s) | Upstream Files | Port Risk |
|--------|-----------|----------------|-----------|
| `SkillScope::Public` variant added | `4897efcce` | `v2.rs`, `protocol.rs` | **MEDIUM** |
| `experimental_raw_events` + `rawResponseItem/completed` | `70913effc` | `v2.rs`, `common.rs`, `codex_message_processor.rs` | **LOW** (opt-in) |
| `approval_policy` constrained via `admin_policy` | `9352c6b23` | `config/constraint.rs`, `config/mod.rs`, `codex.rs` | **MEDIUM** |
| `model/list` and `mcpServerStatus/list` now non-blocking | `df3518936`, `370279388` | `codex_message_processor.rs` | **LOW** (behavioral) |

#### MEDIUM (Config/Docs Surface Changes)

| Change | Commit(s) | Upstream Files | Port Risk |
|--------|-----------|----------------|-----------|
| Skills feature flag documented (`[features].skills = true`) | `7c6a47958` | `docs/skills.md`, `docs/config.md` | **LOW** |
| Ghost snapshot config keys added | `4274e6189`, `0d9801d44`, `3d92b443b` | `docs/config.md`, `ghost_commits.rs` | **LOW** |
| `.codex/` read-only in sandbox like `.git/` | `bef36f4ae` | `protocol.rs`, `seatbelt.rs`, `docs/config.md` | **LOW** |
| `xhigh` reasoning effort documented | (docs only) | `docs/config.md` | **NONE** (SDK already supports) |

#### LOW (Internal / No SDK Impact)

| Change | Commit(s) | Notes |
|--------|-----------|-------|
| `SkillsUpdateAvailable` event added | `4897efcce` | Explicitly ignored in exec JSONL output |
| `apply-patch` refactor + unicode scenarios | `e290d4826`, `a3b137d09`, `ae3793eb5` | Internal only |
| Parallel tool calls ordering fix | `d802b1871` | Behavioral; SDK uses pass-through |
| Windows sandbox packaging | multiple | CI/packaging only |

---

## 2. Port Impact Matrix

| Upstream Change | Elixir Files Impacted | Impact Type |
|-----------------|----------------------|-------------|
| **`thread/compact` removed** | `lib/codex/app_server.ex:172-179` | BREAKING - function calls removed API |
| | `docs/09-app-server-transport.md:10` | Docs mention "threads list/archive/compact" |
| **`mcpServers/list` → `mcpServerStatus/list`** | `lib/codex/app_server/mcp.ex:16` | BREAKING - wrong method string |
| **`ConfigLayerSource` schema** | No code impact (pass-through) | Docs/tests if any check layer shape |
| **`SkillScope::Public`** | No code impact (pass-through) | Docs if any enumerate scopes |
| **`experimental_raw_events`** | `lib/codex/app_server.ex:70-107` (thread_start/resume) | Optional: add param support |
| | `lib/codex/app_server/notification_adapter.ex:139-145` | Already safe (fallback to AppServerNotification) |
| **approval_policy constraints** | `lib/codex/app_server/params.ex`, `lib/codex/thread/options.ex` | Consider validation/docs |
| **Skills feature flag** | `docs/09-app-server-transport.md:155-157` | Update docs with prerequisite |

---

## 3. Verification Table: Existing Porting Notes Review

### Section A1: `thread/compact` removed

| Claim | Status | Evidence |
|-------|--------|----------|
| Upstream removed `thread/compact` | ✅ Confirmed | `git show 412dd3795` removes it from `common.rs`, `v2.rs`, handler |
| Elixir `thread_compact/2` becomes incompatible | ✅ Confirmed | `lib/codex/app_server.ex:174` calls `"thread/compact"` |
| Recommendation: deprecate or return `{:error, :unsupported}` | ✅ Sound | Correct approach |

### Section A2: MCP method rename

| Claim | Status | Evidence |
|-------|--------|----------|
| Renamed to `mcpServerStatus/list` | ✅ Confirmed | `git show 600d01b33` shows rename in `common.rs` |
| Types renamed (`ListMcpServersParams` → `ListMcpServerStatusParams`, etc.) | ✅ Confirmed | Visible in `v2.rs` diff |
| Elixir `Mcp.list_servers/2` uses old method | ✅ Confirmed | `lib/codex/app_server/mcp.ex:16` |
| Recommendation: update method + optional fallback | ✅ Sound | Correct approach |

### Section A3: Config layer schema change

| Claim | Status | Evidence |
|-------|--------|----------|
| `ConfigLayerName` → `ConfigLayerSource` tagged union | ✅ Confirmed | `v2.rs` diff shows tagged union with `type` discriminator |
| Old shape: `{name: <string>, source: <string>}` | ✅ Confirmed | Was `ConfigLayerName` enum + separate `source: String` field |
| New shape: `{name: {type: "...", ...}, version: "..."}` | ✅ Confirmed | `ConfigLayerMetadata` loses `source` field, `name` is tagged union |
| SDK can stay pass-through | ✅ Confirmed | `config_read/2` returns raw maps |

### Section A4: Raw response items

| Claim | Status | Evidence |
|-------|--------|----------|
| `ThreadStartParams.experimental_raw_events` added | ✅ Confirmed | `v2.rs:869-876` |
| `rawResponseItem/completed` notification added | ✅ Confirmed | `common.rs:528-529` |
| SDK notification_adapter handles unknown methods safely | ✅ Confirmed | `notification_adapter.ex:139-145` - fallback to `AppServerNotification` |
| Notes mention streaming semantics check | ⚠️ Partially verified | Raw events can arrive any time; SDK's stream termination on `TurnCompleted` may miss them |

### Section B: Skills

| Claim | Status | Evidence |
|-------|--------|----------|
| `SkillScope::Public` added | ✅ Confirmed | `v2.rs:996` and `protocol.rs:1690` |
| Skills behind feature flag | ✅ Confirmed | `docs/skills.md:6-18` (upstream) |
| SDK docs need update | ⚠️ Minor | `docs/09-app-server-transport.md:155-157` mentions skills caveat but not feature flag prerequisite |

### Section C1: Approval policy constraints

| Claim | Status | Evidence |
|-------|--------|----------|
| `approval_policy` now constrained via `admin_policy` | ✅ Confirmed | `constraint.rs` + `config/mod.rs` changes |
| SDK allows arbitrary strings for forward compat | ✅ Confirmed | `lib/codex/app_server/params.ex` uses `Params.ask_for_approval/1` |
| Invalid values will hard-fail in newer codex | ✅ Confirmed | `Constrained<T>` rejects invalid values at config load time |

### Section C2: Ghost snapshot config

| Claim | Status | Evidence |
|-------|--------|----------|
| New keys: `ghost_snapshot.disable_warnings`, `ignore_large_untracked_files/dirs` | ✅ Confirmed | `docs/config.md` diff |
| SDK likely doesn't need implementation | ✅ Correct | Runtime-internal to `codex` binary |

### Section C3: `.codex/` read-only in sandbox

| Claim | Status | Evidence |
|-------|--------|----------|
| `.codex/` treated like `.git/` under writable roots | ✅ Confirmed | `protocol.rs:464-472` adds `.codex` to read-only subpaths |
| Documented in upstream `docs/config.md` | ✅ Confirmed | Diff shows updated docs |

### Section C4: ConfigToml path semantics

| Claim | Status | Evidence |
|-------|--------|----------|
| `experimental_*_file` → `AbsolutePathBuf` | ✅ Confirmed | `1e9babe17` commit |
| Paths resolved relative to config.toml directory | ✅ Confirmed | Commit description + example-config.md change |

### Section D1: Parallel tool calls fixes

| Claim | Status | Evidence |
|-------|--------|----------|
| Upstream fixes ordering + diff emission timing | ✅ Confirmed | `d802b1871` - "fix parallel tool calls (#7956)" |
| Claim about turn-diff arriving after turn/completed | ❓ Unverifiable | Would require runtime testing to confirm timing |

### Section D2: apply-patch refactor

| Claim | Status | Evidence |
|-------|--------|----------|
| Invocation parsing moved to separate module | ✅ Confirmed | `invocation.rs` created, `lib.rs` reduced |
| Unicode + rejection scenarios added | ✅ Confirmed | Test fixtures show `019_unicode_simple` etc. |
| Only actionable if SDK implements apply_patch | ✅ Correct | SDK delegates via callbacks |

---

## 4. Missing Points in Existing Analysis

| Missing Item | Description | Priority |
|--------------|-------------|----------|
| **`xhigh` reasoning effort** | Notes say "SDK already supports it" but don't verify | ✅ **VERIFIED**: `lib/codex/models.ex:36,45` includes `:xhigh` |
| **`model/list` now non-blocking** | `df3518936` spawns task for `list_models` | LOW - behavioral, no SDK change needed |
| **`mcpServerStatus/list` now non-blocking** | `370279388` spawns task | LOW - behavioral, no SDK change needed |
| **exec JSONL: `SkillsUpdateAvailable` event** | Added to `EventMsg` but explicitly ignored in output | NONE - no SDK impact |
| **`skills/list` gets `force_reload` param** | `Op::ListSkills` gains `force_reload: bool` | LOW - optional enhancement |

---

## 5. Incorrect/Overstated Points in Existing Analysis

| Claim | Assessment |
|-------|------------|
| Section A4 mentions "drain for N ms" option | **Overstated** - Current implementation already has fallback to `AppServerNotification`; no crash risk |
| Section D1 mentions "review app-server streaming termination" | **Valid but low priority** - Turn/diff can be late but won't cause crashes |

---

## 6. Prioritized Port Plan

### P0: Critical / Breaking (Must Fix Before New Server Deployment)

1. **Update MCP method call** (`lib/codex/app_server/mcp.ex:16`)
   - Change `"mcpServers/list"` → `"mcpServerStatus/list"`
   - **Compatibility strategy**: Try new method first; on `-32601` (method not found), retry old method
   ```elixir
   # In list_servers/2:
   case Connection.request(conn, "mcpServerStatus/list", params, timeout_ms: 30_000) do
     {:error, %{code: -32601}} ->
       Connection.request(conn, "mcpServers/list", params, timeout_ms: 30_000)
     result -> result
   end
   ```

2. **Deprecate/Remove `thread_compact/2`** (`lib/codex/app_server.ex:172-179`)
   - Option A (recommended): Return `{:error, {:unsupported, "thread/compact removed in upstream; use auto-compaction"}}`
   - Option B: Keep attempting call but document it only works on older servers
   - Update `docs/09-app-server-transport.md:10` to remove "compact" from advertised features

### P1: Protocol/Schema Updates

3. **Update docs for `config/read` layer shape**
   - Document new `ConfigLayerSource` tagged union in any place mentioning `include_layers: true`
   - SDK code can remain pass-through (maps)

4. **Update skills docs** (`docs/09-app-server-transport.md:155-157`)
   - Add feature flag prerequisite: `[features].skills = true` in config.toml
   - Document `scope: "Public"` as possible value

5. **Optional: Add `experimental_raw_events` support**
   - Add param to `thread_start/2` and `thread_resume/3` in `lib/codex/app_server.ex`
   - Document that `rawResponseItem/completed` arrives as `%AppServerNotification{}`

### P2: Documentation Alignment

6. **Update sandbox docs**
   - Note `.codex/` is now read-only under workspace-write (like `.git/`)

7. **Update approval policy docs**
   - Document that invalid values rejected by newer `codex` servers
   - List valid values: `:untrusted`, `:always`, `:unless_safe`

### P3: Behavioral Parity / Robustness (Optional)

8. **Consider streaming drain behavior**
   - If `experimental_raw_events` is used, raw events may arrive after `turn/completed`
   - Current impl safely wraps them but they won't reach stream consumers who stop on `TurnCompleted`

---

## 7. Validation Plan

### Unit Tests (`mix test`)

- Existing tests should pass
- Add test for `Mcp.list_servers/2` with fallback behavior (mock both methods)
- Add test for `thread_compact/2` returning deprecation error

### Live Smoke Tests (requires local `codex` install)

| Test | Command | Expected |
|------|---------|----------|
| MCP list | `mix run -e 'Codex.AppServer.Mcp.list_servers(conn)'` | Returns `{:ok, %{data: [%{name: _, tools: _, ...}]}}` |
| Config read layers | `mix run -e 'Codex.AppServer.config_read(conn, include_layers: true)'` | Returns layers with `name: %{type: "user", file: "..."}` shape |
| Skills list | `mix run -e 'Codex.AppServer.skills_list(conn, cwds: ["."])'` | Returns skills including `scope: "Public"` if any |
| Thread compact | `mix run -e 'Codex.AppServer.thread_compact(conn, "thr_xxx")'` | Returns `{:error, {:unsupported, _}}` |

### Live Example Scripts

- `examples/live_app_server_basic.exs` - should work
- `examples/live_app_server_streaming.exs` - should work
- `examples/live_app_server_approvals.exs` - should work

---

## 8. Unknowns Requiring Runtime Verification

| Unknown | Test Required |
|---------|---------------|
| Whether `rawResponseItem/completed` can arrive after `turn/completed` | Enable `experimental_raw_events`, trigger response items, observe timing |
| Whether `turn/diff/updated` can arrive after `turn/completed` | Run parallel tool calls, observe event ordering |
| Exact behavior when `approval_policy` constraint rejects a value | Set invalid value via `--config`, observe error message |

---

## 9. Audit Conclusion

The existing porting notes in `docs/20251217/upstream-pull-a9a7cf348/porting-notes.md` are **substantially correct** and comprehensive.

### Summary

| Category | Count |
|----------|-------|
| Confirmed correct claims | 25+ |
| Missing minor details | 5 |
| Incorrect claims | 0 |
| Overstated claims | 2 (minor) |

### Key Findings

- **All breaking changes correctly identified** (`thread/compact`, `mcpServers/list`, `ConfigLayerSource`)
- **Elixir file locations accurately mapped**
- **Recommendations are sound** (fallback strategy, deprecation approach)
- **SDK `xhigh` support verified** in `lib/codex/models.ex:36,45`

### Recommended Next Steps

Implement P0 items immediately before deploying with newer `codex` servers:

1. Update `lib/codex/app_server/mcp.ex:16` method string with fallback
2. Deprecate `lib/codex/app_server.ex:172-179` (`thread_compact/2`)
3. Update `docs/09-app-server-transport.md` to reflect changes
