# Upstream Model Presets Analysis

## File Location
`codex-rs/core/src/openai_models/model_presets.rs`

## Key Constants

```rust
pub const HIDE_GPT5_1_MIGRATION_PROMPT_CONFIG: &str = "hide_gpt5_1_migration_prompt";
pub const HIDE_GPT_5_1_CODEX_MAX_MIGRATION_PROMPT_CONFIG: &str =
    "hide_gpt-5.1-codex-max_migration_prompt";
```

## Model Presets (Static Registry)

### 1. gpt-5.2-codex (NEW DEFAULT)
```rust
ModelPreset {
    id: "gpt-5.2-codex",
    model: "gpt-5.2-codex",
    display_name: "gpt-5.2-codex",
    description: "Latest frontier agentic coding model.",
    default_reasoning_effort: ReasoningEffort::Medium,
    supported_reasoning_efforts: [
        { effort: Low, description: "Fast responses with lighter reasoning" },
        { effort: Medium, description: "Balances speed and reasoning depth for everyday tasks" },
        { effort: High, description: "Greater reasoning depth for complex problems" },
        { effort: XHigh, description: "Extra high reasoning depth for complex problems" },
    ],
    is_default: true,
    upgrade: None,
    show_in_picker: true,
    supported_in_api: false,  // ChatGPT auth only
}
```

### 2. gpt-5.1-codex-max
```rust
ModelPreset {
    id: "gpt-5.1-codex-max",
    model: "gpt-5.1-codex-max",
    display_name: "gpt-5.1-codex-max",
    description: "Codex-optimized flagship for deep and fast reasoning.",
    default_reasoning_effort: ReasoningEffort::Medium,
    supported_reasoning_efforts: [Low, Medium, High, XHigh],
    is_default: false,
    upgrade: Some(gpt_52_codex_upgrade()),
    show_in_picker: true,
    supported_in_api: true,
}
```

### 3. gpt-5.1-codex-mini
```rust
ModelPreset {
    id: "gpt-5.1-codex-mini",
    model: "gpt-5.1-codex-mini",
    display_name: "gpt-5.1-codex-mini",
    description: "Optimized for codex. Cheaper, faster, but less capable.",
    default_reasoning_effort: ReasoningEffort::Medium,
    supported_reasoning_efforts: [Medium, High],  // Limited options
    is_default: false,
    upgrade: Some(gpt_52_codex_upgrade()),
    show_in_picker: true,
    supported_in_api: true,
}
```

### 4. gpt-5.2 (NEW)
```rust
ModelPreset {
    id: "gpt-5.2",
    model: "gpt-5.2",
    display_name: "gpt-5.2",
    description: "Latest frontier model with improvements across knowledge, reasoning and coding",
    default_reasoning_effort: ReasoningEffort::Medium,
    supported_reasoning_efforts: [Low, Medium, High, XHigh],
    is_default: false,
    upgrade: Some(gpt_52_codex_upgrade()),
    show_in_picker: true,
    supported_in_api: true,
}
```

### Deprecated Models (Hidden from Picker)

All deprecated models have:
- `show_in_picker: false`
- `upgrade: Some(gpt_52_codex_upgrade())`
- `supported_in_api: true`

| Model | Description |
|-------|-------------|
| `gpt-5-codex` | Optimized for codex |
| `gpt-5-codex-mini` | Cheaper, faster, but less capable |
| `gpt-5.1-codex` | Optimized for codex |
| `gpt-5` | Broad world knowledge with strong general reasoning |
| `gpt-5.1` | Broad world knowledge with strong general reasoning |

## Upgrade Path Definition

```rust
fn gpt_52_codex_upgrade() -> ModelUpgrade {
    ModelUpgrade {
        id: "gpt-5.2-codex",
        reasoning_effort_mapping: None,
        migration_config_key: "gpt-5.2-codex",
        model_link: Some("https://openai.com/index/introducing-gpt-5-2-codex"),
        upgrade_copy: Some(
            "Codex is now powered by gpt-5.2-codex, our latest frontier agentic coding model. \
             It is smarter and faster than its predecessors and capable of long-running \
             project-scale work."
        ),
    }
}
```

## Reasoning Effort Descriptions by Model

### gpt-5.2-codex / gpt-5.1-codex-max
| Effort | Description |
|--------|-------------|
| Low | Fast responses with lighter reasoning |
| Medium | Balances speed and reasoning depth for everyday tasks |
| High | Greater reasoning depth for complex problems |
| XHigh | Extra high reasoning depth for complex problems |

### gpt-5.1-codex-mini / gpt-5-codex-mini
| Effort | Description |
|--------|-------------|
| Medium | Dynamically adjusts reasoning based on the task |
| High | Maximizes reasoning depth for complex or ambiguous problems |

### gpt-5 / gpt-5-codex / gpt-5.1-codex
| Effort | Description |
|--------|-------------|
| Low | Fastest responses with limited reasoning |
| Medium | Dynamically adjusts reasoning based on the task |
| High | Maximizes reasoning depth for complex or ambiguous problems |

### gpt-5 (base)
| Effort | Description |
|--------|-------------|
| Minimal | Fastest responses with little reasoning |
| Low | Balances speed with some reasoning |
| Medium | Solid balance of reasoning depth and latency |
| High | Maximizes reasoning depth for complex problems |

## Helper Function

```rust
pub(super) fn builtin_model_presets(_auth_mode: Option<AuthMode>) -> Vec<ModelPreset> {
    PRESETS
        .iter()
        .filter(|preset| preset.show_in_picker)  // Only visible models
        .cloned()
        .collect()
}
```
