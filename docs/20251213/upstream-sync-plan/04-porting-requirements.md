# Porting Requirements

## Overview

This document defines requirements for porting the **synced** upstream changes into the Elixir SDK.
Some upstream features are transport-dependent (they are only available via codex core/app-server
protocols, not via `codex exec --experimental-json`). Those requirements are explicitly marked.

---

## High Priority

### 1) Response Chaining Option (`auto_previous_response_id`)

**Source**: `openai-agents-python` commit `a9d95b4`

#### Requirements

**R1.1** Add `auto_previous_response_id` to `Codex.RunConfig`
- Type: `boolean`, default `false`
- Location: `lib/codex/run_config.ex`

**R1.2** Persist “last response id” when available
- If the backend provides an OpenAI `response_id`, surface it via the Elixir result struct and keep
  it in runner state for future chaining.

**R1.3** Wire chaining when the backend supports it
- When `auto_previous_response_id: true`, subsequent internal calls (or subsequent runs, depending
  on SDK semantics) should reuse the last response id as `previous_response_id`.

**R1.4** Document current backend limitation
- The current Elixir SDK transport (`codex exec --experimental-json`) does not expose an OpenAI
  `response_id`. If no `response_id` exists, auto-chaining cannot be fully implemented.

#### Tests

- Unit: `Codex.RunConfig.new/1` accepts and validates the new option.
- Integration/fixture: only possible once a backend exposes `response_id`.

---

### 2) Codex-rs OTEL Telemetry Export Guidance

**Source**: `codex-rs` commit `ad7b9d63c`

#### Requirements

**R2.1** Document codex-rs OTEL configuration
- Add guidance for enabling `[otel]` in `~/.codex/config.toml` (see upstream `codex/docs/config.md`).

**R2.2** Avoid conflating OTEL layers
- Clarify that `lib/codex/telemetry.ex` configures **Elixir-side** OTLP export.
- Codex-rs OTEL export is **config.toml-driven** and is independent.

**R2.3 (Optional)** Provide a `CODEX_HOME` override hook
- If the SDK needs programmatic control, allow running the subprocess with an isolated `CODEX_HOME`
  directory containing a generated `config.toml`.

#### Tests

- Unit: validate any new SDK option(s) for `CODEX_HOME`/env overrides.
- Existing `Codex.Exec` tests already cover env injection behavior.

---

## Medium Priority (Transport-Dependent)

These requirements assume the Elixir SDK adopts either the **core protocol**
(`codex-rs/protocol`) or the **app-server protocol** (`codex-rs/app-server-protocol`). They are not
actionable if the SDK remains on exec JSONL only.

### 3) Skills

**Source**: `codex-rs` commits `b36ecb6c3`, `60479a967`

#### Requirements

**R3.1** Encode `UserInput::Skill`
- Add an input type that can represent `{type: "skill", name, path}` as per
  `codex-rs/protocol/src/user_input.rs`.

**R3.2** Surface discovery outcomes (optional)
- Parse `SessionConfiguredEvent.skill_load_outcome` and expose it to callers (for UIs).

**R3.3** Preserve upstream semantics
- Skill discovery is recursive under `~/.codex/skills/**/SKILL.md` and `<repo_root>/.codex/skills/**/SKILL.md`.
- Name/description limits are **characters**, not bytes.

---

### 4) Remote Models (ModelsManager)

**Source**: `codex-rs` commits `00cc00ead`, `222a49157`, `53a486f7e`

#### Requirements

**R4.1** Expose a dynamic model list
- Provide an API to list models from upstream sources (app-server, direct API, or codex-managed cache).

**R4.2** Respect upstream cache behavior
- TTL is 5 minutes and cache is stored at `codex_home/models_cache.json`.

---

### 5) Config Layers + Versioned Writes (ConfigService)

**Source**: `codex-rs` commit `92098d36e`

#### Requirements

**R5.1** Layer awareness
- Preserve precedence: MDM > System > Session flags > User.

**R5.2** Version semantics
- Use sha256 version strings (e.g., `sha256:<hex>`) for optimistic concurrency (`expected_version`).

---

### 6) Review Mode Protocol

**Source**: `codex-rs` commit `4b78e2ab0`

#### Requirements

**R6.1** Encode `Op::Review`
- Support the `ReviewRequest` / `ReviewTarget` types as defined in `codex-rs/protocol/src/protocol.rs`.

**R6.2** Decode review lifecycle events
- Surface `EnteredReviewMode` and `ExitedReviewMode` events, including any structured review output.

---

## Low Priority / Blocked

### 7) Chat Completions Logprobs

**Source**: `openai-agents-python` commit `df020d1`

This requires the Elixir SDK backend to surface logprobs. Until codex output includes logprobs, the
Elixir SDK should avoid inventing new public types for it.

---

### 8) Shell Snapshotting

**Source**: `codex-rs` commits `7836aedda`, `29381ba5c`

Backend-internal; generally docs-only for the SDK.

---

### 9) AbsolutePathBuf Writable Roots

**Source**: `codex-rs` commit `642b7566d`

Only relevant if the Elixir SDK exposes writable roots (e.g., codex `--add-dir` equivalents). If
exposed, validate absolute paths (or mirror codex’s relative-path resolution semantics).

---

## Dependencies (Only If Needed)

```elixir
# mix.exs (optional)
defp deps do
  [
    # YAML frontmatter parsing (only if implementing Elixir-side SKILL.md parsing)
    {:yaml_elixir, "~> 2.9"},

    # TOML parsing (only if generating/parsing codex config.toml programmatically)
    {:toml, "~> 0.7"}
  ]
end
```
