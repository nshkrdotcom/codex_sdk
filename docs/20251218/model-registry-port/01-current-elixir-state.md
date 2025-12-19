# Current Elixir Models.ex State

## File Location
`lib/codex/models.ex`

## Current Implementation

### Model Type Definition
```elixir
@type reasoning_effort :: :minimal | :low | :medium | :high | :xhigh
@type model :: %{
  id: String.t(),
  default_reasoning_effort: reasoning_effort(),
  tool_enabled?: boolean(),
  default?: boolean()
}
```

### Current Model List
```elixir
@models [
  %{
    id: "gpt-5.1-codex-max",
    default_reasoning_effort: :medium,
    tool_enabled?: true,
    default?: true  # <-- Currently the default
  },
  %{
    id: "gpt-5.1-codex",
    default_reasoning_effort: :medium,
    tool_enabled?: true,
    default?: false
  },
  %{
    id: "gpt-5.1-codex-mini",
    default_reasoning_effort: :medium,
    tool_enabled?: true,
    default?: false
  },
  %{
    id: "gpt-5.1",
    default_reasoning_effort: :medium,
    tool_enabled?: false,
    default?: false
  }
]
```

### Current Default Model
```elixir
@default_model "gpt-5.1-codex-max"
```

### Reasoning Efforts
```elixir
@reasoning_efforts [:minimal, :low, :medium, :high, :xhigh]

@reasoning_effort_aliases %{
  "extra_high" => :xhigh,
  "extra-high" => :xhigh,
  "minimal" => :minimal,
  "low" => :low,
  "medium" => :medium,
  "high" => :high,
  "xhigh" => :xhigh
}
```

### Key Functions

| Function | Description |
|----------|-------------|
| `list/0` | Returns all available models |
| `default_model/0` | Returns SDK default, with env override support |
| `default_reasoning_effort/1` | Gets default reasoning effort for a model |
| `tool_enabled?/1` | Checks if model supports tool execution |
| `normalize_reasoning_effort/1` | Parses reasoning effort values |
| `reasoning_efforts/0` | Lists valid reasoning effort values |
| `reasoning_effort_to_string/1` | Converts effort atom to string |

### Environment Variable Overrides
```elixir
def default_model do
  System.get_env("CODEX_MODEL") ||
    System.get_env("OPENAI_DEFAULT_MODEL") ||
    System.get_env("CODEX_MODEL_DEFAULT") ||
    @default_model
end
```

## What's Missing vs Upstream

### Missing Fields Per Model

1. `display_name` and `description`
2. `supported_reasoning_efforts` (and per-effort descriptions)
3. `show_in_picker` and `supported_in_api`
4. `upgrade` metadata with `reasoning_effort_mapping`
5. Remote-model metadata fields (`visibility`, `priority`, `shell_type`, `truncation_policy`, etc.)

### Missing Models

1. `gpt-5.2-codex`
2. `gpt-5.2`
3. `gpt-5-codex`
4. `gpt-5-codex-mini`
5. `gpt-5`
6. `codex-mini-latest`

### Missing Behavior

1. `ReasoningEffort::None` (Elixir omits `:none`)
2. Auth-aware defaults (API key vs ChatGPT) and `codex-auto-balanced` override
3. Auth mode inference (prefer `CODEX_API_KEY` or `auth.json` `openai_api_key`, else ChatGPT tokens)
4. Remote model list (`/models`) with `models.json` fallback and caching
5. Feature gating for remote models (`features.remote_models`, default `false` upstream)
6. Priority-based default selection and show_in_picker filtering
7. Remote overrides applied to model family config (base instructions, shell type, context window, etc.)

### Potential Mismatches

- `gpt-5.1` is marked `tool_enabled?: false`, but upstream model families configure shell tools for base GPT-5.x models. If the SDK wants to reflect upstream capability, `tool_enabled?` likely needs to be derived from `shell_type` instead of hard-coded.
