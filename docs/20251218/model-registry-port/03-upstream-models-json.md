# Upstream models.json Analysis

## File Location
`codex/codex-rs/core/models.json`

## Purpose

`models.json` is a bundled fallback for remote model metadata. It is embedded into the binary and used when `features.remote_models` is enabled (default `false`), either as:

1. Fallback data when the `/models` fetch is skipped or fails.
2. Initial data before remote refresh.

When the feature is disabled, the models list uses local presets only (see `02-upstream-model-presets.md`).

## Inventory (Sorted by Priority)

`models.json` defines **9** models. `gpt-5.2-codex` is **not** present.

| Slug | Visibility | Supported in API | Priority | Upgrade | Shell Type | Apply Patch | Truncation | Parallel Tools | Verbosity | Default Verbosity | Context Window | Min Client | Reasoning Summary |
|------|------------|------------------|----------|---------|------------|-------------|------------|----------------|-----------|-------------------|----------------|------------|-------------------|
| gpt-5.1-codex-max | list | true | 0 | null | shell_command | freeform | tokens:10000 | false | false | null | 272000 | 0.62.0 | experimental |
| gpt-5.1-codex | list | true | 1 | gpt-5.1-codex-max | shell_command | freeform | tokens:10000 | false | false | null | 272000 | 0.60.0 | experimental |
| gpt-5.1-codex-mini | list | true | 2 | gpt-5.1-codex-max | shell_command | freeform | tokens:10000 | false | false | null | 272000 | 0.60.0 | experimental |
| gpt-5.2 | list | true | 3 | null | shell_command | freeform | bytes:10000 | true | true | low | 272000 | 0.60.0 | none |
| gpt-5.1 | list | true | 4 | gpt-5.1-codex-max | shell_command | freeform | bytes:10000 | true | true | low | 272000 | 0.60.0 | none |
| gpt-5-codex-mini | hide | true | 5 | gpt-5.1-codex-mini | shell_command | freeform | tokens:10000 | false | false | null | 272000 | 0.60.0 | experimental |
| gpt-5-codex | hide | true | 6 | gpt-5.1-codex-max | shell_command | freeform | tokens:10000 | false | false | null | 272000 | 0.60.0 | experimental |
| gpt-5 | hide | true | 7 | gpt-5.1-codex-max | default | null | bytes:10000 | false | true | null | 272000 | 0.60.0 | none |
| codex-mini-latest | hide | true | 8 | null | local | null | bytes:10000 | false | false | null | 200000 | 0.60.0 | experimental |

## Descriptions (models.json)

| Slug | Description |
|------|-------------|
| gpt-5.1-codex-max | Latest Codex-optimized flagship for deep and fast reasoning. |
| gpt-5.1-codex | Optimized for codex. |
| gpt-5.1-codex-mini | Optimized for codex. Cheaper, faster, but less capable. |
| gpt-5.2 | Latest frontier model with improvements across knowledge, reasoning and coding |
| gpt-5.1 | Broad world knowledge with strong general reasoning. |
| gpt-5-codex-mini | Optimized for codex. Cheaper, faster, but less capable. |
| gpt-5-codex | Optimized for codex. |
| gpt-5 | Broad world knowledge with strong general reasoning. |
| codex-mini-latest | Legacy Codex mini model. |

## Reasoning Effort Presets (Exact Strings)

### gpt-5.1-codex-max
- low: Fast responses with lighter reasoning
- medium: Balances speed and reasoning depth for everyday tasks
- high: Greater reasoning depth for complex problems
- xhigh: Extra high reasoning depth for complex problems

### gpt-5.1-codex
- low: Fastest responses with limited reasoning
- medium: Dynamically adjusts reasoning based on the task
- high: Maximizes reasoning depth for complex or ambiguous problems

### gpt-5.1-codex-mini
- medium: Dynamically adjusts reasoning based on the task
- high: Maximizes reasoning depth for complex or ambiguous problems

### gpt-5.2
- low: Balances speed with some reasoning; useful for straightforward queries and short explanations
- medium: Provides a solid balance of reasoning depth and latency for general-purpose tasks
- high: Maximizes reasoning depth for complex or ambiguous problems
- xhigh: Extra high reasoning for complex problems

### gpt-5.1
- low: Balances speed with some reasoning; useful for straightforward queries and short explanations
- medium: Provides a solid balance of reasoning depth and latency for general-purpose tasks
- high: Maximizes reasoning depth for complex or ambiguous problems

### gpt-5-codex
- low: Fastest responses with limited reasoning
- medium: Dynamically adjusts reasoning based on the task
- high: Maximizes reasoning depth for complex or ambiguous problems

### gpt-5-codex-mini
- medium: Dynamically adjusts reasoning based on the task
- high: Maximizes reasoning depth for complex or ambiguous problems

### gpt-5
- minimal: Fastest responses with little reasoning
- low: Balances speed with some reasoning; useful for straightforward queries and short explanations
- medium: Provides a solid balance of reasoning depth and latency for general-purpose tasks
- high: Maximizes reasoning depth for complex or ambiguous problems

### codex-mini-latest
- minimal: Fastest responses with little reasoning
- low: Balances speed with some reasoning; useful for straightforward queries and short explanations
- medium: Provides a solid balance of reasoning depth and latency for general-purpose tasks

## Model Metadata Fields

### Core Fields
| Field | Type | Description |
|-------|------|-------------|
| `slug` | string | Unique model identifier |
| `display_name` | string | UI display name |
| `description` | string | Human-readable description |
| `default_reasoning_level` | string | Default reasoning effort |
| `supported_reasoning_levels` | array | Available effort options |

### Capability Fields
| Field | Type | Description |
|-------|------|-------------|
| `shell_type` | string | Shell tool type: `default`, `local`, `shell_command` |
| `supports_reasoning_summaries` | bool | Can output reasoning summaries |
| `support_verbosity` | bool | Supports verbosity setting |
| `default_verbosity` | string? | Default verbosity level (`low` for `gpt-5.2` and `gpt-5.1`) |
| `supports_parallel_tool_calls` | bool | Can make parallel tool calls |
| `apply_patch_tool_type` | string? | `freeform` or null |
| `reasoning_summary_format` | string | `experimental` for codex families, `none` for base GPT-5.x |
| `experimental_supported_tools` | array | Empty list for all bundled models |

### Resource Fields
| Field | Type | Description |
|-------|------|-------------|
| `context_window` | int | Max context tokens |
| `truncation_policy` | object | `{mode: "bytes"|"tokens", limit: int}` |
| `base_instructions` | string | Full prompt text (non-null for all bundled models) |

### Visibility/Auth Fields
| Field | Type | Description |
|-------|------|-------------|
| `visibility` | string | `list` or `hide` (maps to show_in_picker) |
| `supported_in_api` | bool | Works with API key auth |
| `minimal_client_version` | array | Min client version `[major, minor, patch]` |
| `priority` | int | Sort order (lower = higher priority) |

### Upgrade Fields
| Field | Type | Description |
|-------|------|-------------|
| `upgrade` | string? | Target model slug for upgrade |

## Loading Mechanism

```rust
fn load_remote_models_from_file() -> Result<Vec<ModelInfo>, std::io::Error> {
    let file_contents = include_str!("../../models.json");
    let response: ModelsResponse = serde_json::from_str(file_contents)?;
    Ok(response.models)
}
```

## Important Notes

1. `gpt-5.2-codex` is not in `models.json`; it only exists in `model_presets.rs`.
2. When `features.remote_models` is disabled (default), `models.json` is ignored.
3. When enabled, `models.json` is converted to `ModelPreset` entries and merged with local presets.
4. `base_instructions` is large, non-null for all bundled models, and is used to override prompt text in `ModelFamily` when remote models are enabled.
