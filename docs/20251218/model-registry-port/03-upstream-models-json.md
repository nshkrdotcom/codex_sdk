# Upstream models.json Analysis

## File Location
`codex-rs/core/models.json`

## Purpose

The `models.json` file serves as a **static fallback** for model definitions. It's bundled with the Codex CLI and loaded when:
1. Remote model fetching is disabled
2. Network is unavailable
3. As initial data before remote refresh

## Models Defined

### Active Models (show in picker)

#### 1. codex-mini-latest
```json
{
  "slug": "codex-mini-latest",
  "display_name": "codex-mini-latest",
  "description": null,
  "default_reasoning_level": "medium",
  "supported_reasoning_levels": [
    { "effort": "medium", "description": "Dynamically adjusts reasoning based on the task" },
    { "effort": "high", "description": "Maximizes reasoning depth for complex or ambiguous problems" }
  ],
  "shell_type": "local",
  "visibility": "list",
  "minimal_client_version": [0, 1, 0],
  "supported_in_api": true,
  "priority": 1,
  "upgrade": "gpt-5.1-codex-max",
  "supports_reasoning_summaries": true,
  "support_verbosity": false,
  "apply_patch_tool_type": "freeform",
  "truncation_policy": { "mode": "tokens", "limit": 10000 },
  "supports_parallel_tool_calls": false,
  "context_window": 200000
}
```

#### 2. gpt-5.2
```json
{
  "slug": "gpt-5.2",
  "display_name": "gpt-5.2",
  "description": "Latest frontier model with improvements across knowledge, reasoning and coding",
  "default_reasoning_level": "medium",
  "supported_reasoning_levels": [
    { "effort": "low", "description": "Balances speed with some reasoning..." },
    { "effort": "medium", "description": "Provides a solid balance of reasoning depth and latency..." },
    { "effort": "high", "description": "Maximizes reasoning depth for complex or ambiguous problems" },
    { "effort": "xhigh", "description": "Extra high reasoning for complex problems" }
  ],
  "shell_type": "shell_command",
  "visibility": "list",
  "minimal_client_version": [0, 1, 0],
  "supported_in_api": true,
  "priority": 3,
  "upgrade": null,
  "supports_reasoning_summaries": true,
  "support_verbosity": true,
  "default_verbosity": "low",
  "apply_patch_tool_type": "freeform",
  "truncation_policy": { "mode": "bytes", "limit": 10000 },
  "supports_parallel_tool_calls": true,
  "context_window": 272000
}
```

#### 3. gpt-5.1
```json
{
  "slug": "gpt-5.1",
  "display_name": "gpt-5.1",
  "description": "Broad world knowledge with strong general reasoning.",
  "default_reasoning_level": "medium",
  "supported_reasoning_levels": [
    { "effort": "low", "description": "Balances speed with some reasoning..." },
    { "effort": "medium", "description": "Provides a solid balance of reasoning depth and latency..." },
    { "effort": "high", "description": "Maximizes reasoning depth for complex or ambiguous problems" }
  ],
  "shell_type": "shell_command",
  "visibility": "list",
  "supported_in_api": true,
  "priority": 4,
  "upgrade": "gpt-5.1-codex-max"
}
```

### Deprecated/Hidden Models

These models have `"visibility": "list"` but are older versions:

| Model | Priority | Upgrade To |
|-------|----------|------------|
| gpt-5 | 9 | gpt-5.1-codex-max |
| gpt-5-codex | 5 | gpt-5.1-codex-max |
| gpt-5-codex-mini | 6 | gpt-5.1-codex-max |
| gpt-5.1-codex | 7 | gpt-5.1-codex-max |
| gpt-5.1-codex-max | 8 | gpt-5.1-codex-max |
| gpt-5.1-codex-mini | 10 | gpt-5.1-codex-max |

## Model Metadata Fields

### Core Fields
| Field | Type | Description |
|-------|------|-------------|
| `slug` | string | Unique model identifier |
| `display_name` | string | UI display name |
| `description` | string? | Human-readable description |
| `default_reasoning_level` | string | Default reasoning effort |
| `supported_reasoning_levels` | array | Available effort options |

### Capability Fields
| Field | Type | Description |
|-------|------|-------------|
| `shell_type` | string | Shell tool type: "default", "local", "shell_command", "unified_exec" |
| `supports_reasoning_summaries` | bool | Can output reasoning summaries |
| `support_verbosity` | bool | Supports verbosity setting |
| `default_verbosity` | string? | Default verbosity level |
| `supports_parallel_tool_calls` | bool | Can make parallel tool calls |
| `apply_patch_tool_type` | string? | "freeform" or "function" |

### Resource Fields
| Field | Type | Description |
|-------|------|-------------|
| `context_window` | int | Max context tokens |
| `truncation_policy` | object | `{mode: "bytes"|"tokens", limit: int}` |

### Visibility/Auth Fields
| Field | Type | Description |
|-------|------|-------------|
| `visibility` | string | "list", "hide", "none" |
| `supported_in_api` | bool | Works with API key auth |
| `minimal_client_version` | array | Min client version [major, minor, patch] |
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

The file is embedded at compile time via `include_str!`.

## Important Notes

1. **gpt-5.2-codex is NOT in models.json** - It's only defined in `model_presets.rs`
2. The JSON acts as fallback data; remote models take precedence
3. Priority determines sort order in the model picker
4. Visibility controls whether model appears in UI
