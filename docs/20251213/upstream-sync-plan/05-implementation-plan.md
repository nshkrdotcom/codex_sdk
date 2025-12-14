# Implementation Plan

## Overview

This plan aligns the Elixir `codex_sdk` with the synced upstream states:
- `openai-agents-python` (`0d2d771..71fa12c`)
- `codex-rs` (`6eeaf46ac..a2c86e5d8`)

Several codex-rs features in this sync are **transport-dependent** (core/app-server protocol vs
`codex exec --experimental-json`). The plan starts by making that decision explicit.

---

## Phase 0: Transport Decision (Required)

**Goal**: Decide what the Elixir SDK targets for codex integration.

- Option A: keep **exec JSONL** (`codex exec --experimental-json`) as the only transport
- Option B: add **core protocol** and/or **app-server protocol** integration

This decision gates models/skills/config/review work.

---

## Phase 1: agents-python Parity (Actionable Now)

### 1.1 `auto_previous_response_id` API support

**Goal**: Add the option in the correct place (`Codex.RunConfig`) and keep behavior well-defined.

**Files to modify**:
- `lib/codex/run_config.ex` (add field + validation)
- `lib/codex/agent_runner.ex` (store/use last response id if/when available)

**Definition of done**:
- [ ] `Codex.RunConfig.new/1` accepts `auto_previous_response_id`
- [ ] Docs clearly state current backend limitation (no `response_id` in exec JSONL)
- [ ] Unit tests cover config parsing

---

## Phase 2: Observability Alignment (Mostly Docs)

### 2.1 Codex-rs OTEL configuration guidance

**Goal**: Document upstream OTEL export and avoid conflating it with Elixir OTLP export.

**Work items**:
- Document `~/.codex/config.toml` `[otel]` settings (link upstream `codex/docs/config.md`)
- Clarify the difference between:
  - `lib/codex/telemetry.ex` (Elixir-side OTLP export)
  - codex-rs OTEL export (subprocess-side, config.toml-driven)

**Optional implementation (only if needed)**:
- Add a `CODEX_HOME` override surface so the SDK can run codex with a generated config directory.

---

## Phase 3: codex-rs Features (Transport-Dependent)

Proceed only if Phase 0 chooses core/app-server protocol support.

### 3.1 Skills

**Goal**: Support upstream skill selection + surfacing discovery outcomes.

**Work items**:
- Encode `UserInput::Skill` (name + path)
- Decode `SessionConfiguredEvent.skill_load_outcome` (optional)

### 3.2 Remote models list

**Goal**: Surface a dynamic model list compatible with codex-rs `ModelsManager`.

**Work items**:
- Provide `Codex.Models.list_models/1` that integrates with the chosen transport
- Respect upstream TTL + ETag semantics where applicable

### 3.3 ConfigService integration (optional)

**Goal**: Expose config read/write operations with sha256 version strings.

### 3.4 Review mode (optional)

**Goal**: Support `Op::Review` and review lifecycle events.

---

## Phase 4: Deferred / Blocked Items

### 4.1 Chat Completions logprobs

Upstream preserved logprobs in agents-python (`df020d1`), but the Elixir SDK backend must surface
logprobs before an Elixir API can expose them. Revisit when the transport carries logprobs.

---

## Success Criteria

- Elixir docs and plans reflect the actual synced upstream commits
- Implemented requirements are transport-correct (no features assumed to exist on exec JSONL if they
  are only exposed via protocol/app-server)
- New SDK options are added where they belong (`Codex.RunConfig` for run-scoped options)
