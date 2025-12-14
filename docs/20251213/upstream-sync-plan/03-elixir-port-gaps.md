# Elixir Port Gap Analysis

## Overview

This document audits the current Elixir `codex_sdk` implementation against the synced upstream
states:
- `openai-agents-python` (`0d2d771..71fa12c`)
- `codex` / `codex-rs` (`6eeaf46ac..a2c86e5d8`)

## Current Elixir Port State (0.2.3)

- **Version**: 0.2.3
- **Elixir Source Files**: 46 (`lib/*.ex` and `lib/codex/*.ex`)
- **Thread + runner APIs**:
  - `Codex.start_thread/2`, `Codex.resume_thread/3`
  - `Codex.Thread.run/3`, `Codex.Thread.run_stream/3`
  - `Codex.AgentRunner.run/3`, `Codex.AgentRunner.run_streamed/3`
- **Already implemented (relevant to upstream parity)**:
  - `Codex.RunConfig` includes `session_input_callback`, `nest_handoff_history`,
    `call_model_input_filter`, `conversation_id`, and `previous_response_id`
  - Unknown JSONL event types are ignored (logged + dropped) in `lib/codex/exec.ex`

---

## Gap Analysis

### A) agents-python Sync (`0d2d771..71fa12c`)

#### 1) Response chaining (`auto_previous_response_id`) — `a9d95b4`

| Aspect | Upstream | Elixir Port | Gap |
|--------|----------|-------------|-----|
| `previous_response_id` option | Supported | Present in `Codex.RunConfig` | **Implemented** (not wired to codex backend) |
| `auto_previous_response_id` option | Supported | Not present | **Missing** |
| “last response id” surface | `RunResult.last_response_id` | Not exposed | **Missing** (backend-dependent) |

Notes:
- The Elixir SDK models `previous_response_id` and `conversation_id`, but Codex CLI session
  continuation is performed via `thread_id` + `resume` (no `codex exec` flags for user-supplied
  chaining identifiers).
- The upstream agents-python feature relies on access to an OpenAI `response_id`; the Elixir SDK’s
  current `codex exec --experimental-json` transport does not provide one.

#### 2) Chat Completions logprobs preservation — `df020d1`

| Aspect | Upstream | Elixir Port | Gap |
|--------|----------|-------------|-----|
| Logprobs attached to output text | Supported | Not represented in `Codex.Items` | **Blocked** (backend-dependent) |

Notes:
- Upstream attaches logprobs to Responses-style output items even in chat-completions mode.
- The open-source codex exec JSONL event schema does not currently surface logprobs.

#### 3) Usage normalization — `509ddda`

| Aspect | Upstream | Elixir Port | Gap |
|--------|----------|-------------|-----|
| Nil token detail normalization | Supported | Usage is a flat numeric map | **N/A** for current transport |

Notes:
- The Elixir SDK merges numeric usage maps defensively; there are no nested token detail objects to
  normalize.

#### 4) Apply-patch context threading — `9f96338`

| Aspect | Upstream | Elixir Port | Gap |
|--------|----------|-------------|-----|
| Apply patch operation carries run context | Supported | Not explicitly modeled | **Potential** (depends on host patch hooks) |

Notes:
- Only relevant if the Elixir SDK exposes host-side “apply patch” tooling hooks and wants to supply
  run context to the callback.

---

### B) codex-rs Sync (`6eeaf46ac..a2c86e5d8`)

Many codex-rs features in this range are surfaced via the **core protocol** or **app-server**, not
via `codex exec --experimental-json`. Decide transport scope before implementing SDK support.

#### 1) OTEL telemetry export — `ad7b9d63c`

| Aspect | Upstream | Elixir Port | Gap |
|--------|----------|-------------|-----|
| Codex-rs OTEL export (`~/.codex/config.toml` `[otel]`) | Supported | Not managed by Elixir | **Docs + optional helper** |

Notes:
- The Elixir SDK already has its own OTLP exporter config (`lib/codex/telemetry.ex`), which is a
  separate concern from codex-rs OTEL export.

#### 2) Remote models (ModelsManager)

| Aspect | Upstream | Elixir Port | Gap |
|--------|----------|-------------|-----|
| Remote `/models` discovery + TTL/ETag caching | Supported | `Codex.Models` is hardcoded | **Missing** (transport-dependent) |

#### 3) Skills

| Aspect | Upstream | Elixir Port | Gap |
|--------|----------|-------------|-----|
| Skill discovery (`SKILL.md`) + runtime “## Skills” injection | Supported | Not exposed | **Missing** (transport-dependent) |
| Explicit skill selection (`UserInput::Skill`) | Supported | Input is string-only | **Missing** |

#### 4) Config loader + ConfigService

| Aspect | Upstream | Elixir Port | Gap |
|--------|----------|-------------|-----|
| Layered config loader + versioned write API | Supported | Not implemented | **Optional** (app-server integration) |

#### 5) Review mode / unified exec events

| Aspect | Upstream | Elixir Port | Gap |
|--------|----------|-------------|-----|
| Review protocol types (`ReviewRequest`, `EnteredReviewMode`, etc.) | Supported | Not surfaced | **Optional** (protocol transport) |

#### 6) AbsolutePathBuf sandbox config — `642b7566d`

| Aspect | Upstream | Elixir Port | Gap |
|--------|----------|-------------|-----|
| Absolute writable roots | Supported | SDK does not expose writable roots | **N/A** (until surfaced) |

---

## Gap Summary (Actionable Items)

| Feature | Priority | Complexity | Status |
|---------|----------|------------|--------|
| `auto_previous_response_id` option | Medium | Medium | Missing |
| Codex-rs OTEL config guidance | Medium | Low | Missing docs |
| Remote model discovery | Medium | High | Transport-dependent |
| Skills support | Medium | High | Transport-dependent |
| Chat-completions logprobs | Low | Medium | Blocked (backend-dependent) |
| Usage normalization | Low | Low | N/A (current transport) |

---

## Existing Module Impact Analysis

| Module | Notes |
|--------|-------|
| `lib/codex/run_config.ex` | Add `auto_previous_response_id` if implementing agents-python parity |
| `lib/codex/agent_runner.ex` | Persist/update last response id when/if surfaced by backend |
| `lib/codex/items.ex` | Only extend for logprobs if backend surfaces them |
| `lib/codex/exec.ex` | Transport-dependent: protocol/app-server integration would be new work |

---

## Backwards Compatibility

All proposed changes can remain backwards compatible:
- New config fields default to current behavior
- Unknown events are already ignored by the exec JSONL decoder

---

## Notes for Planning

- Many codex-rs “core” features (skills, review, config service) are **not available** via the
  exec JSONL event stream. Any plan that assumes they are available must include a transport change
  (core protocol or app-server integration).
