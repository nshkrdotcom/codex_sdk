# Implementation Plan

## Phase 1: Types and Enums

### Step 1.1: Extend reasoning effort type
```elixir
@type reasoning_effort :: :none | :minimal | :low | :medium | :high | :xhigh
@reasoning_efforts [:none, :minimal, :low, :medium, :high, :xhigh]
```

### Step 1.2: Add preset and upgrade types
```elixir
@type reasoning_effort_preset :: %{
  effort: reasoning_effort(),
  description: String.t()
}

@type model_upgrade :: %{
  id: String.t(),
  reasoning_effort_mapping: %{reasoning_effort() => reasoning_effort()} | nil,
  migration_config_key: String.t(),
  model_link: String.t() | nil,
  upgrade_copy: String.t() | nil
}

@type model_preset :: %{
  id: String.t(),
  model: String.t(),
  display_name: String.t(),
  description: String.t(),
  default_reasoning_effort: reasoning_effort(),
  supported_reasoning_efforts: [reasoning_effort_preset()],
  is_default: boolean(),
  upgrade: model_upgrade() | nil,
  show_in_picker: boolean(),
  supported_in_api: boolean()
}
```

### Step 1.3: Add ModelInfo type if remote models are implemented
Mirror `codex/codex-rs/protocol/src/openai_models.rs` (see `06-port-requirements.md`).

## Phase 2: Local Presets (Default Behavior)

### Step 2.1: Add local presets
Populate `@local_presets` using the 4 entries in `model_presets.rs`:
- `gpt-5.2-codex`
- `gpt-5.1-codex-max`
- `gpt-5.1-codex-mini`
- `gpt-5.2`

### Step 2.2: Add shared upgrade metadata
Define `@gpt_52_codex_upgrade` for reuse in local presets.

## Phase 3: Remote Models (Optional but Upstream-Complete)

### Step 3.1: Load `models.json`
Parse `codex/codex-rs/core/models.json` into `ModelInfo` structs.

### Step 3.2: Convert to ModelPreset
Implement `model_info_to_preset/1` following `ModelPreset::from(ModelInfo)`.

### Step 3.3: Gate by feature flag
Only use remote models when `features.remote_models` is enabled (default false upstream).
Skip the network fetch when auth mode is API key; keep bundled `models.json`.

## Phase 4: Merge, Filter, Defaults

### Step 4.0: Infer auth mode
Prefer API key when `CODEX_API_KEY` or `auth.json` `openai_api_key` is present; otherwise use ChatGPT tokens.

### Step 4.1: Merge remote + local
- Sort remote models by priority (ascending)
- Convert to presets
- Add local presets for missing slugs (notably `gpt-5.2-codex`)

### Step 4.2: Filter by visibility and auth
- `show_in_picker == true`
- API auth requires `supported_in_api == true`

### Step 4.3: Default selection
If no preset has `is_default`, mark the first model as default.

### Step 4.4: Auth-aware default model
Update `default_model/0` to select:
- ChatGPT auth -> `gpt-5.2-codex`
- API key auth -> `gpt-5.1-codex-max`
- Prefer `codex-auto-balanced` when remote models include it and ChatGPT auth is active

## Phase 5: Public Helpers

Add or update:
- `list_visible/1` (auth-aware filtering)
- `supported_reasoning_efforts/1`
- `supported_in_api?/1`
- `get_upgrade/1`
- `display_name/1` and `description/1`

## Phase 6: Tests

- Validate API vs ChatGPT `list_models` output (match upstream expectations)
- Confirm auth-aware default model selection
- Ensure `:none` reasoning effort is accepted
- Verify upgrade metadata and reasoning effort mapping

## Breaking Changes

1. Default model becomes auth-aware (ChatGPT vs API)
2. Model preset type gains additional required fields
3. Optional remote models introduce priority-based defaults and extra visible models

## Rollout Strategy

1. Add types + local presets (backwards compatible)
2. Introduce auth-aware defaults
3. Add remote models support (feature-flagged)
4. Expand helper APIs and tests
