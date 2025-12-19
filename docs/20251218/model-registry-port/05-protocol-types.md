# Protocol Types for Models

## File Location
`codex/codex-rs/protocol/src/openai_models.rs`

## Reasoning Effort

### ReasoningEffort Enum
```rust
#[derive(Debug, Serialize, Deserialize, Default, Clone, Copy, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum ReasoningEffort {
    None,
    Minimal,
    Low,
    #[default]
    Medium,
    High,
    XHigh,
}
```

### Elixir Equivalent
```elixir
@type reasoning_effort :: :none | :minimal | :low | :medium | :high | :xhigh
```

**Note**: The Elixir SDK currently omits `:none` - this should be added.

### ReasoningEffortPreset
```rust
pub struct ReasoningEffortPreset {
    pub effort: ReasoningEffort,
    pub description: String,
}
```

### Elixir Equivalent
```elixir
@type reasoning_effort_preset :: %{
  effort: reasoning_effort(),
  description: String.t()
}
```

## Model Upgrade

### ModelUpgrade Struct
```rust
pub struct ModelUpgrade {
    pub id: String,
    pub reasoning_effort_mapping: Option<HashMap<ReasoningEffort, ReasoningEffort>>,
    pub migration_config_key: String,
    pub model_link: Option<String>,
    pub upgrade_copy: Option<String>,
}
```

### Elixir Equivalent
```elixir
@type model_upgrade :: %{
  id: String.t(),
  reasoning_effort_mapping: %{reasoning_effort() => reasoning_effort()} | nil,
  migration_config_key: String.t(),
  model_link: String.t() | nil,
  upgrade_copy: String.t() | nil
}
```

## Model Preset

### ModelPreset Struct
```rust
pub struct ModelPreset {
    pub id: String,
    pub model: String,
    pub display_name: String,
    pub description: String,
    pub default_reasoning_effort: ReasoningEffort,
    pub supported_reasoning_efforts: Vec<ReasoningEffortPreset>,
    pub is_default: bool,
    pub upgrade: Option<ModelUpgrade>,
    pub show_in_picker: bool,
    pub supported_in_api: bool,
}
```

### Elixir Equivalent
```elixir
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

## Model Info (Remote/JSON)

### ModelInfo Struct
```rust
pub struct ModelInfo {
    pub slug: String,
    pub display_name: String,
    pub description: Option<String>,
    pub default_reasoning_level: ReasoningEffort,
    pub supported_reasoning_levels: Vec<ReasoningEffortPreset>,
    pub shell_type: ConfigShellToolType,
    pub visibility: ModelVisibility,
    pub minimal_client_version: ClientVersion,
    pub supported_in_api: bool,
    pub priority: i32,
    pub upgrade: Option<String>,
    pub base_instructions: Option<String>,
    pub supports_reasoning_summaries: bool,
    pub support_verbosity: bool,
    pub default_verbosity: Option<Verbosity>,
    pub apply_patch_tool_type: Option<ApplyPatchToolType>,
    pub truncation_policy: TruncationPolicyConfig,
    pub supports_parallel_tool_calls: bool,
    pub context_window: Option<i64>,
    pub reasoning_summary_format: ReasoningSummaryFormat,
    pub experimental_supported_tools: Vec<String>,
}
```

**Note**: `base_instructions` is populated in `models.json` and can override model prompts when remote models are enabled.

## Model Visibility

```rust
pub enum ModelVisibility {
    List,
    Hide,
    None,
}
```

### Elixir Equivalent
```elixir
@type model_visibility :: :list | :hide | :none
```

## Shell Tool Type

```rust
pub enum ConfigShellToolType {
    Default,
    Local,
    UnifiedExec,
    Disabled,
    ShellCommand,
}
```

### Elixir Equivalent
```elixir
@type shell_tool_type :: :default | :local | :unified_exec | :disabled | :shell_command
```

## Truncation Policy

```rust
pub struct TruncationPolicyConfig {
    pub mode: TruncationMode,  // bytes | tokens
    pub limit: i64,
}
```

### Elixir Equivalent
```elixir
@type truncation_policy :: %{
  mode: :bytes | :tokens,
  limit: non_neg_integer()
}
```

## Client Version

```rust
pub struct ClientVersion(pub i32, pub i32, pub i32);
```

### Elixir Equivalent
```elixir
@type client_version :: {non_neg_integer(), non_neg_integer(), non_neg_integer()}
```

## Models Response (from /models endpoint)

```rust
pub struct ModelsResponse {
    pub models: Vec<ModelInfo>,
    pub etag: String,
}
```

## Conversion: ModelInfo -> ModelPreset

```rust
impl From<ModelInfo> for ModelPreset {
    fn from(info: ModelInfo) -> Self {
        ModelPreset {
            id: info.slug.clone(),
            model: info.slug.clone(),
            display_name: info.display_name,
            description: info.description.unwrap_or_default(),
            default_reasoning_effort: info.default_reasoning_level,
            supported_reasoning_efforts: info.supported_reasoning_levels.clone(),
            is_default: false,
            upgrade: info.upgrade.as_ref().map(|upgrade_slug| ModelUpgrade {
                id: upgrade_slug.clone(),
                reasoning_effort_mapping: reasoning_effort_mapping_from_presets(
                    &info.supported_reasoning_levels,
                ),
                migration_config_key: info.slug.clone(),
                model_link: None,
                upgrade_copy: None,
            }),
            show_in_picker: info.visibility == ModelVisibility::List,
            supported_in_api: info.supported_in_api,
        }
    }
}
```

**Note**: `ModelPreset::from(ModelInfo)` does not set a default model. `ModelsManager` later picks the highest-priority visible model if none is marked default.

## App Server Protocol (v2)

The app-server exposes a simplified model list via JSON-RPC.

### Model (v2)
```rust
pub struct Model {
    pub id: String,
    pub model: String,
    pub display_name: String,
    pub description: String,
    pub supported_reasoning_efforts: Vec<ReasoningEffortOption>,
    pub default_reasoning_effort: ReasoningEffort,
    pub is_default: bool,
}

pub struct ReasoningEffortOption {
    pub reasoning_effort: ReasoningEffort,
    pub description: String,
}
```

### ModelListResponse (v2)
```rust
pub struct ModelListResponse {
    pub data: Vec<Model>,
    pub next_cursor: Option<String>,
}
```

This is the shape returned by the Codex app-server list models endpoint.
