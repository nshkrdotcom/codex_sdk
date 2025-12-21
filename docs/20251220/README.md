# Upstream Port: 2025-12-20

This document outlines the porting plan to bring the Elixir Codex SDK in sync with upstream codex-rs changes from commits `d7ae342ff..987dd7fde`.

## Overview

**Upstream Commit Range**: `d7ae342ff..987dd7fde` (32 commits)
**Target Version**: 0.5.0 (breaking changes) or 0.4.2 (additive only)
**Elixir Current Version**: 0.4.1

## Documents

1. [PORTING_PLAN.md](./PORTING_PLAN.md) - Complete porting plan with priorities
2. [CHANGES_SUMMARY.md](./CHANGES_SUMMARY.md) - Summary of upstream changes
3. [IMPLEMENTATION_CHECKLIST.md](./IMPLEMENTATION_CHECKLIST.md) - Task checklist
4. [VERSION_BUMP.md](./VERSION_BUMP.md) - Version bump and changelog instructions

## Quick Stats

| Category | Count | Priority |
|----------|-------|----------|
| Config Changes | 4 | Critical/High |
| Protocol Changes | 3 | High |
| Model Changes | 2 | Critical |
| Feature Flags | 1 | Medium |
| Skills Updates | 3 | Medium |
| Bug Fixes | 2 | Medium |
| TUI-Only | 2 | Skip |

## Recommended Approach

1. **Phase 1 (Critical)**: Models Manager + Constraint System + SandboxPolicy
2. **Phase 2 (High)**: Config Requirements + Protocol Updates
3. **Phase 3 (Medium)**: Skills + Feature Flags + Bug Fixes
4. **Phase 4 (Low)**: File Search + Documentation Sync
