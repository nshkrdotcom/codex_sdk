# Model Family Configuration

## File Location
`codex-rs/core/src/openai_models/model_family.rs`

## Purpose

Model families define per-model capabilities and behavior configurations that affect how Codex interacts with each model type.

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

## Model Family Definitions

### gpt-5.2-codex (NEW)
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
    context_window: Some(272_000),
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
    supports_parallel_tool_calls: false,  // Note: different from 5.2-codex
    support_verbosity: false,
    truncation_policy: TruncationPolicy::Tokens(10_000),
    context_window: Some(272_000),
)
```

### gpt-5.2 (Base)
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
    context_window: Some(272_000),
)
```

### gpt-5.1 / gpt-5.1-codex / gpt-5-codex (Older)
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
    context_window: Some(272_000),
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
    Default,      // Standard shell
    Local,        // Local-only execution
    UnifiedExec,  // Unified PTY-backed exec
    Disabled,     // No shell access
    ShellCommand, // Shell command tool
}
```

### Apply Patch Tool Types
```rust
pub enum ApplyPatchToolType {
    Freeform,  // Flexible patch format
    Function,  // Structured function call
}
```

### Reasoning Summary Formats
```rust
pub enum ReasoningSummaryFormat {
    None,         // No summaries
    Experimental, // Experimental format
}
```

### Truncation Policies
```rust
pub enum TruncationPolicy {
    Bytes(i64),   // Truncate by bytes
    Tokens(i64),  // Truncate by tokens
}
```

## Model Instructions Files

Different model families use different instruction prompts:

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
| codex-mini-latest | 200,000 |
| gpt-4.1 | 1,047,576 |
| gpt-4o | 128,000 |
| gpt-3.5 | 16,385 |

## Elixir Implications

For the Elixir SDK, we may want to track:
1. `context_window` - For token limit calculations
2. `supports_parallel_tool_calls` - For tool execution
3. `shell_type` - If implementing shell tools
4. `apply_patch_tool_type` - If implementing patching

Most of the model family configuration is internal to the Codex runtime and doesn't directly affect the SDK API surface, but knowing these details helps understand model capabilities.
