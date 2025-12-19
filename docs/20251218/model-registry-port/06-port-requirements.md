# Port Requirements for Elixir SDK

## Overview

To fully port the upstream model registry, the Elixir SDK must account for **two data sources** and **auth-aware behavior**:

1. **Local presets** (`model_presets.rs`): used when `features.remote_models` is disabled (default upstream).
2. **Remote models** (`/models`, fallback `models.json`): used only when `features.remote_models` is enabled.

`gpt-5.2-codex` is only in local presets, so it must always be defined locally.

## Required Behavior

1. **Auth-aware defaults**
   - ChatGPT auth: default `gpt-5.2-codex`.
   - API key auth: default `gpt-5.1-codex-max`.
   - If remote models include `codex-auto-balanced` and ChatGPT auth is active, prefer it.

2. **Auth mode inference**
   - Prefer API key when `CODEX_API_KEY` is set.
   - Otherwise, if `auth.json` contains `openai_api_key`, use API key mode.
   - Otherwise, use ChatGPT mode (tokens in `auth.json`).
   - If both are present, `CODEX_API_KEY` wins.

3. **Remote model gating**
   - When `features.remote_models` is `false`, list models from local presets only.
   - When `true`, load remote models (fallback `models.json`) and merge with local presets.
   - Remote fetch is skipped for API key auth; use bundled `models.json` only in that case.

4. **Merge + filter**
   - Convert `ModelInfo` to `ModelPreset` (see `05-protocol-types.md`).
   - Remote presets override local presets with the same slug.
   - Append local presets for missing slugs (notably `gpt-5.2-codex`).
   - Filter to `show_in_picker` and, for API auth, `supported_in_api`.

5. **Default selection**
   - If no model is marked default after filtering, mark the first (lowest priority) entry as default.

6. **Upgrade mapping**
   - Local presets use `gpt_52_codex_upgrade()` (from `model_presets.rs`).
   - Remote presets use `upgrade` slug + `reasoning_effort_mapping_from_presets`.

## Type Definition Updates

### Reasoning Effort
```elixir
@type reasoning_effort :: :none | :minimal | :low | :medium | :high | :xhigh
```

### Presets and Upgrades
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

### Remote Model Info (if implementing remote models)
```elixir
@type model_info :: %{
  slug: String.t(),
  display_name: String.t(),
  description: String.t() | nil,
  default_reasoning_level: reasoning_effort(),
  supported_reasoning_levels: [reasoning_effort_preset()],
  shell_type: :default | :local | :unified_exec | :disabled | :shell_command,
  visibility: :list | :hide | :none,
  minimal_client_version: {non_neg_integer(), non_neg_integer(), non_neg_integer()},
  supported_in_api: boolean(),
  priority: integer(),
  upgrade: String.t() | nil,
  base_instructions: String.t() | nil,
  supports_reasoning_summaries: boolean(),
  support_verbosity: boolean(),
  default_verbosity: :low | :medium | :high | nil,
  apply_patch_tool_type: :freeform | :function | nil,
  truncation_policy: %{mode: :bytes | :tokens, limit: non_neg_integer()},
  supports_parallel_tool_calls: boolean(),
  context_window: non_neg_integer() | nil,
  reasoning_summary_format: :none | :experimental,
  experimental_supported_tools: [String.t()]
}
```

## Local Presets (Used When remote_models is Disabled)

These come from `codex/codex-rs/core/src/openai_models/model_presets.rs`.

```elixir
@local_presets [
  %{
    id: "gpt-5.2-codex",
    model: "gpt-5.2-codex",
    display_name: "gpt-5.2-codex",
    description: "Latest frontier agentic coding model.",
    default_reasoning_effort: :medium,
    supported_reasoning_efforts: [
      %{effort: :low, description: "Fast responses with lighter reasoning"},
      %{effort: :medium, description: "Balances speed and reasoning depth for everyday tasks"},
      %{effort: :high, description: "Greater reasoning depth for complex problems"},
      %{effort: :xhigh, description: "Extra high reasoning depth for complex problems"}
    ],
    is_default: true,
    show_in_picker: true,
    supported_in_api: false,
    upgrade: nil
  },
  %{
    id: "gpt-5.1-codex-max",
    model: "gpt-5.1-codex-max",
    display_name: "gpt-5.1-codex-max",
    description: "Codex-optimized flagship for deep and fast reasoning.",
    default_reasoning_effort: :medium,
    supported_reasoning_efforts: [
      %{effort: :low, description: "Fast responses with lighter reasoning"},
      %{effort: :medium, description: "Balances speed and reasoning depth for everyday tasks"},
      %{effort: :high, description: "Greater reasoning depth for complex problems"},
      %{effort: :xhigh, description: "Extra high reasoning depth for complex problems"}
    ],
    is_default: false,
    show_in_picker: true,
    supported_in_api: true,
    upgrade: @gpt_52_codex_upgrade
  },
  %{
    id: "gpt-5.1-codex-mini",
    model: "gpt-5.1-codex-mini",
    display_name: "gpt-5.1-codex-mini",
    description: "Optimized for codex. Cheaper, faster, but less capable.",
    default_reasoning_effort: :medium,
    supported_reasoning_efforts: [
      %{effort: :medium, description: "Dynamically adjusts reasoning based on the task"},
      %{effort: :high, description: "Maximizes reasoning depth for complex or ambiguous problems"}
    ],
    is_default: false,
    show_in_picker: true,
    supported_in_api: true,
    upgrade: @gpt_52_codex_upgrade
  },
  %{
    id: "gpt-5.2",
    model: "gpt-5.2",
    display_name: "gpt-5.2",
    description: "Latest frontier model with improvements across knowledge, reasoning and coding",
    default_reasoning_effort: :medium,
    supported_reasoning_efforts: [
      %{effort: :low, description: "Balances speed with some reasoning; useful for straightforward queries and short explanations"},
      %{effort: :medium, description: "Provides a solid balance of reasoning depth and latency for general-purpose tasks"},
      %{effort: :high, description: "Maximizes reasoning depth for complex or ambiguous problems"},
      %{effort: :xhigh, description: "Extra high reasoning for complex problems"}
    ],
    is_default: false,
    show_in_picker: true,
    supported_in_api: true,
    upgrade: @gpt_52_codex_upgrade
  }
]
```

### Shared Upgrade Definition
```elixir
@gpt_52_codex_upgrade %{
  id: "gpt-5.2-codex",
  reasoning_effort_mapping: nil,
  migration_config_key: "gpt-5.2-codex",
  model_link: "https://openai.com/index/introducing-gpt-5-2-codex",
  upgrade_copy: "Codex is now powered by gpt-5.2-codex, our latest frontier agentic coding model. It is smarter and faster than its predecessors and capable of long-running project-scale work."
}
```

## Remote Models Fallback (models.json)

If you implement remote models, load `codex/codex-rs/core/models.json` into `ModelInfo` structs and convert them to `ModelPreset`. The complete inventory, priorities, and effort strings are documented in `03-upstream-models-json.md`.

## Tool Support Mapping

`tool_enabled?` is not part of upstream models. If the Elixir SDK keeps it:

- Prefer deriving it from `shell_type` (`:disabled` -> false; all other values -> true).
- This makes base GPT-5.x models tool-capable, matching upstream configuration.

## Constants and Aliases

```elixir
@reasoning_efforts [:none, :minimal, :low, :medium, :high, :xhigh]

@reasoning_effort_aliases %{
  "none" => :none,
  "extra_high" => :xhigh,
  "extra-high" => :xhigh,
  "minimal" => :minimal,
  "low" => :low,
  "medium" => :medium,
  "high" => :high,
  "xhigh" => :xhigh
}
```

## New Functions to Add or Update

```elixir
@doc """
Returns models visible in the model picker.
If auth_mode is :api, only include supported_in_api models.
"""
@spec list_visible(:api | :chatgpt) :: [model_preset()]
def list_visible(auth_mode \\ :api) do
  @models
  |> Enum.filter(fn model ->
    model.show_in_picker && (auth_mode == :chatgpt || model.supported_in_api)
  end)
end

@doc """
Returns the upgrade information for a model, if available.
"""
@spec get_upgrade(String.t()) :: model_upgrade() | nil
def get_upgrade(model_id) do
  case find_model(model_id) do
    %{upgrade: upgrade} -> upgrade
    _ -> nil
  end
end

@doc """
Returns the supported reasoning efforts for a model.
"""
@spec supported_reasoning_efforts(String.t()) :: [reasoning_effort_preset()]
def supported_reasoning_efforts(model_id) do
  case find_model(model_id) do
    %{supported_reasoning_efforts: efforts} -> efforts
    _ -> []
  end
end

@doc """
Returns true if a model is supported via API key authentication.
"""
@spec supported_in_api?(String.t()) :: boolean()
def supported_in_api?(model_id) do
  case find_model(model_id) do
    %{supported_in_api: supported} -> supported
    _ -> false
  end
end
```

## Migration Notes

1. **Default model becomes auth-aware** (ChatGPT -> `gpt-5.2-codex`, API -> `gpt-5.1-codex-max`).
2. **Remote model support is optional** but required to match upstream behavior when `features.remote_models` is enabled.
3. **Backwards compatibility**: keep older models (including hidden ones) for explicit use even if they are not in the picker.
