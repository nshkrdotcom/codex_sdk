# Model Family Configuration

## File Location
`codex/codex-rs/core/src/openai_models/model_family.rs`

## Purpose

Model families define per-model capabilities and behavior configurations that affect how Codex interacts with each model type. These defaults can be overridden by remote model metadata (see below).

## ModelFamily Struct

```rust
pub struct ModelFamily {
    pub slug: String,
    pub family: String,
    pub needs_special_apply_patch_instructions: bool,
    pub context_window: Option<i64>,
    auto_compact_token_limit: Option<i64>,
    pub supports_reasoning_summaries: bool,
    pub default_reasoning_effort: Option<ReasoningEffort>,
    pub reasoning_summary_format: ReasoningSummaryFormat,
    pub supports_parallel_tool_calls: bool,
    pub apply_patch_tool_type: Option<ApplyPatchToolType>,
    pub base_instructions: String,
    pub experimental_supported_tools: Vec<String>,
    pub effective_context_window_percent: i64,
    pub support_verbosity: bool,
    pub default_verbosity: Option<Verbosity>,
    pub shell_type: ConfigShellToolType,
    pub truncation_policy: TruncationPolicy,
}
```

## Remote Overrides

`ModelFamily::with_remote_overrides` applies remote `ModelInfo` fields when `features.remote_models` is enabled, including:

- `default_reasoning_effort`
- `shell_type`
- `base_instructions`
- `supports_reasoning_summaries`
- `support_verbosity` / `default_verbosity`
- `apply_patch_tool_type`
- `truncation_policy`
- `supports_parallel_tool_calls`
- `context_window`
- `reasoning_summary_format`
- `experimental_supported_tools`

## Model Family Definitions

### gpt-5.2-codex
```rust
model_family!(
    slug, slug,
    supports_reasoning_summaries: true,
    reasoning_summary_format: ReasoningSummaryFormat::Experimental,
    base_instructions: GPT_5_2_CODEX_INSTRUCTIONS.to_string(),
    apply_patch_tool_type: Some(ApplyPatchToolType::Freeform),
    shell_type: ConfigShellToolType::ShellCommand,
    supports_parallel_tool_calls: true,
    support_verbosity: false,
    truncation_policy: TruncationPolicy::Tokens(10_000),
    context_window: Some(CONTEXT_WINDOW_272K),
)
```

### gpt-5.1-codex-max
```rust
model_family!(
    slug, slug,
    supports_reasoning_summaries: true,
    reasoning_summary_format: ReasoningSummaryFormat::Experimental,
    base_instructions: GPT_5_1_CODEX_MAX_INSTRUCTIONS.to_string(),
    apply_patch_tool_type: Some(ApplyPatchToolType::Freeform),
    shell_type: ConfigShellToolType::ShellCommand,
    supports_parallel_tool_calls: false,
    support_verbosity: false,
    truncation_policy: TruncationPolicy::Tokens(10_000),
    context_window: Some(CONTEXT_WINDOW_272K),
)
```

### gpt-5-codex / gpt-5.1-codex / codex-* (legacy codex family)
```rust
model_family!(
    slug, slug,
    supports_reasoning_summaries: true,
    reasoning_summary_format: ReasoningSummaryFormat::Experimental,
    base_instructions: GPT_5_CODEX_INSTRUCTIONS.to_string(),
    apply_patch_tool_type: Some(ApplyPatchToolType::Freeform),
    shell_type: ConfigShellToolType::ShellCommand,
    supports_parallel_tool_calls: false,
    support_verbosity: false,
    truncation_policy: TruncationPolicy::Tokens(10_000),
    context_window: Some(CONTEXT_WINDOW_272K),
)
```

### gpt-5.2 (base)
```rust
model_family!(
    slug, slug,
    supports_reasoning_summaries: true,
    apply_patch_tool_type: Some(ApplyPatchToolType::Freeform),
    support_verbosity: true,
    default_verbosity: Some(Verbosity::Low),
    base_instructions: GPT_5_2_INSTRUCTIONS.to_string(),
    default_reasoning_effort: Some(ReasoningEffort::Medium),
    truncation_policy: TruncationPolicy::Bytes(10_000),
    shell_type: ConfigShellToolType::ShellCommand,
    supports_parallel_tool_calls: true,
    context_window: Some(CONTEXT_WINDOW_272K),
)
```

### gpt-5.1 (base)
```rust
model_family!(
    slug, "gpt-5.1",
    supports_reasoning_summaries: true,
    apply_patch_tool_type: Some(ApplyPatchToolType::Freeform),
    support_verbosity: true,
    default_verbosity: Some(Verbosity::Low),
    base_instructions: GPT_5_1_INSTRUCTIONS.to_string(),
    default_reasoning_effort: Some(ReasoningEffort::Medium),
    truncation_policy: TruncationPolicy::Bytes(10_000),
    shell_type: ConfigShellToolType::ShellCommand,
    supports_parallel_tool_calls: true,
    context_window: Some(CONTEXT_WINDOW_272K),
)
```

### gpt-5 (base)
```rust
model_family!(
    slug, "gpt-5",
    supports_reasoning_summaries: true,
    needs_special_apply_patch_instructions: true,
    shell_type: ConfigShellToolType::Default,
    support_verbosity: true,
    truncation_policy: TruncationPolicy::Bytes(10_000),
    context_window: Some(CONTEXT_WINDOW_272K),
)
```

### codex-mini-latest
```rust
model_family!(
    slug, "codex-mini-latest",
    supports_reasoning_summaries: true,
    needs_special_apply_patch_instructions: true,
    shell_type: ConfigShellToolType::Local,
    context_window: Some(200_000),
)
```

## Key Configuration Options

### Shell Tool Types
```rust
pub enum ConfigShellToolType {
    Default,
    Local,
    UnifiedExec,
    Disabled,
    ShellCommand,
}
```

### Apply Patch Tool Types
```rust
pub enum ApplyPatchToolType {
    Freeform,
    Function,
}
```

### Reasoning Summary Formats
```rust
pub enum ReasoningSummaryFormat {
    None,
    Experimental,
}
```

### Truncation Policies
```rust
pub enum TruncationPolicy {
    Bytes(i64),
    Tokens(i64),
}
```

## Model Instructions Files

| Model Family | Instructions File |
|--------------|-------------------|
| gpt-5.2-codex | `gpt-5.2-codex_prompt.md` |
| gpt-5.1-codex-max | `gpt-5.1-codex-max_prompt.md` |
| gpt-5.2 | `gpt_5_2_prompt.md` |
| gpt-5.1 | `gpt_5_1_prompt.md` |
| gpt-5-codex family | `gpt_5_codex_prompt.md` |
| Default | `prompt.md` |

## Context Windows

| Model | Context Window |
|-------|----------------|
| gpt-5.2-codex | 272,000 |
| gpt-5.1-codex-max | 272,000 |
| gpt-5.2 | 272,000 |
| gpt-5.1 | 272,000 |
| gpt-5 | 272,000 |
| codex-mini-latest | 200,000 |
| gpt-4.1 | 1,047,576 |
| gpt-4o | 128,000 |
| gpt-3.5 | 16,385 |

## Elixir Implications

If the Elixir SDK mirrors model capabilities, it should track:

1. `context_window` (token limits)
2. `supports_parallel_tool_calls`
3. `shell_type` and `apply_patch_tool_type`
4. `support_verbosity` / `default_verbosity`
5. `base_instructions` and `reasoning_summary_format` if remote overrides are used
