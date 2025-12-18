# Model Registry Port Documentation

This directory contains comprehensive documentation for porting the upstream Codex model registry changes to the Elixir SDK (`lib/codex/models.ex`).

## Overview

The upstream Codex CLI (Rust) has undergone significant model registry changes between commits `a9a7cf348` and `d7ae342ff`, most notably:

1. **New default model**: `gpt-5.2-codex` is now the default model
2. **New models.json file**: Static model definitions bundled with the CLI
3. **Enhanced ModelPreset structure**: Richer metadata per model
4. **Model upgrade paths**: Automatic migration prompts for older models
5. **Model family configurations**: Per-model capability settings

## Documentation Structure

| File | Description |
|------|-------------|
| [01-current-elixir-state.md](./01-current-elixir-state.md) | Current Elixir models.ex implementation |
| [02-upstream-model-presets.md](./02-upstream-model-presets.md) | Rust model_presets.rs analysis |
| [03-upstream-models-json.md](./03-upstream-models-json.md) | Static models.json fallback data |
| [04-model-family-config.md](./04-model-family-config.md) | Model family capabilities |
| [05-protocol-types.md](./05-protocol-types.md) | Protocol types for models |
| [06-port-requirements.md](./06-port-requirements.md) | Specific porting requirements |
| [07-implementation-plan.md](./07-implementation-plan.md) | Step-by-step implementation plan |

## Key Changes Summary

### New Default Model
- **Before**: `gpt-5.1-codex-max`
- **After**: `gpt-5.2-codex`

### Model Upgrade Paths
All older models now have an upgrade path to `gpt-5.2-codex` with:
- Migration config key
- Optional model link
- Upgrade copy text

### New Models to Add
- `gpt-5.2-codex` (new default, supports Low/Medium/High/XHigh reasoning)
- `gpt-5.2` (frontier model, supports Low/Medium/High/XHigh reasoning)

### Model Visibility
Models now have visibility controls:
- `show_in_picker`: Whether to show in model selection UI
- `supported_in_api`: Whether supported via API key auth
- Deprecated models (gpt-5-codex, gpt-5-codex-mini, gpt-5.1-codex, gpt-5, gpt-5.1) are hidden from picker

## Quick Reference

### Elixir Models to Update

```elixir
@models [
  # NEW DEFAULT
  %{
    id: "gpt-5.2-codex",
    description: "Latest frontier agentic coding model.",
    default_reasoning_effort: :medium,
    supported_reasoning_efforts: [:low, :medium, :high, :xhigh],
    tool_enabled?: true,
    default?: true,
    show_in_picker: true,
    supported_in_api: false  # ChatGPT auth only initially
  },

  # KEEP (with upgrade path)
  %{
    id: "gpt-5.1-codex-max",
    description: "Codex-optimized flagship for deep and fast reasoning.",
    default_reasoning_effort: :medium,
    supported_reasoning_efforts: [:low, :medium, :high, :xhigh],
    tool_enabled?: true,
    default?: false,
    show_in_picker: true,
    supported_in_api: true,
    upgrade: %{id: "gpt-5.2-codex", migration_key: "gpt-5.2-codex"}
  },

  # ... see full list in 06-port-requirements.md
]
```

## Related Files

### Upstream (Rust)
- `codex-rs/core/models.json` - Static model definitions
- `codex-rs/core/src/openai_models/model_presets.rs` - Model presets
- `codex-rs/core/src/openai_models/models_manager.rs` - Model management
- `codex-rs/core/src/openai_models/model_family.rs` - Model family configs
- `codex-rs/protocol/src/openai_models.rs` - Protocol types

### Elixir SDK
- `lib/codex/models.ex` - Current implementation to update
- `lib/codex/model_settings.ex` - Model tuning parameters

## Commit Reference

Upstream commits: `a9a7cf348..d7ae342ff`

Key commits:
- `927a6acbe` - Load models from static file (#8153)
- `774bd9e43` - feat: model picker (#8209)
