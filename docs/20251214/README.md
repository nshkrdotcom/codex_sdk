# Upstream Sync Analysis - December 14, 2025

## Git Pull Summary

**Commit Range**: `a2c86e5d8..5d77d4db6`
**Primary Change**: Reimplement skills loading using SkillsManager + skills/list operation

## Documentation Index

### 1. Git Diff Analysis
- [`git_diff_analysis/changes-summary.md`](./git_diff_analysis/changes-summary.md)
  - Complete list of 29 modified files
  - New features introduced (SkillsManager, Op::ListSkills, etc.)
  - API breaking changes
  - Behavioral changes

### 2. Skills Analysis
- [`skills_analysis/skills-comparison.md`](./skills_analysis/skills-comparison.md)
  - **Key Finding**: Skills were already in Rust codebase, NOT in Elixir
  - Rust implementation: 583 lines, 6 files, fully featured
  - Elixir implementation: no first-class skills API today; `skills/list` is blocked on the missing app-server transport (see multi-transport refactor doc set)
  - Detailed comparison and porting requirements

### 3. Protocol Changes
- [`protocol_changes/new-protocol-types.md`](./protocol_changes/new-protocol-types.md)
  - New Op::ListSkills operation
  - New ListSkillsResponseEvent
  - SkillScope enum
  - Wire format examples

### 4. Documentation Porting Status
- [`docs_porting_status/codex-docs-review.md`](./docs_porting_status/codex-docs-review.md)
  - Technical documentation review (protocol_v1.md, mcp_interface.md)
  - What's covered vs missing

- [`docs_porting_status/full-docs-porting-matrix.md`](./docs_porting_status/full-docs-porting-matrix.md)
  - Complete matrix of all 24 upstream docs
  - Feature coverage analysis
  - Configuration comparison
  - Event coverage comparison

### 5. Technical Porting Plan
- [`technical_plan/porting-plan.md`](./technical_plan/porting-plan.md)
  - Decision matrix (defer vs implement)
  - Implementation phases if proceeding
  - Risk assessment
  - Timeline estimates

### 6. Multi-Transport Refactor (Exec + App-Server)
- [`multi_transport_refactor/README.md`](./multi_transport_refactor/README.md)
  - Upstream surface map (TUI vs exec vs app-server)
  - Why `skills/list` is app-server-only
  - `UserInput::Skill` exposure status (core vs app-server vs SDKs)
  - Target Elixir architecture for full parity

## Key Findings

### Were Skills Already in the Codebase?

| Codebase | Answer | Details |
|----------|--------|---------|
| **Rust (codex-rs)** | ✅ Yes | Skills existed before this pull. The new changes refactored them with SkillsManager for better caching and added skills/list operation. |
| **Elixir (codex_sdk)** | ❌ No (first-class API) | Upstream `codex` supports skills behind `features.skills`; the SDK does not expose skills list/selection as Elixir APIs. |

### Upstream Changes Summary

1. **New SkillsManager** - Centralized skills management with per-cwd caching
2. **Op::ListSkills** - New protocol operation for skills discovery
3. **ListSkillsResponseEvent** - Server response with per-cwd skills
4. **SkillScope enum** - Distinguishes User vs Repo skills
5. **API Changes** - Codex::spawn() now requires SkillsManager parameter
6. **Removed** - skill_load_outcome from SessionConfiguredEvent (now via ListSkills)

### Porting Recommendation

**Decision: proceed with an app-server transport refactor** (while keeping exec as default):
- Implement app-server JSON-RPC transport first (see `docs/20251214/multi_transport_refactor/README.md`)
- Then expose `skills/list` via app-server types (`SkillScope`, `SkillMetadata`, etc.)
- Note: `UserInput::Skill` is still core-only today (not exposed in app-server v2 input union)

## Related Documentation

- Previous sync: [`docs/20251213/upstream-sync-plan/`](../20251213/upstream-sync-plan/)
- Gap analysis: [`03-elixir-port-gaps.md`](../20251213/upstream-sync-plan/03-elixir-port-gaps.md)
- Implementation plan: [`05-implementation-plan.md`](../20251213/upstream-sync-plan/05-implementation-plan.md)
