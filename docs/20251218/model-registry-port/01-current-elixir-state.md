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
    tool_enabled?: false,  # <-- No tool support
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
1. `description` - Human-readable model description
2. `display_name` - UI display name
3. `supported_reasoning_efforts` - List of supported efforts with descriptions
4. `show_in_picker` - Whether to show in model selection
5. `supported_in_api` - Whether supported via API key auth
6. `upgrade` - Model upgrade path info

### Missing Models
1. `gpt-5.2-codex` - New default model
2. `gpt-5.2` - New frontier model
3. `codex-mini-latest` - Mini model variant
4. `gpt-5` - Base GPT-5 model
5. `gpt-5-codex` - Original codex model (deprecated)
6. `gpt-5-codex-mini` - Original mini (deprecated)

### Missing Functionality
1. Model upgrade/migration support
2. Per-model reasoning effort options with descriptions
3. Model visibility controls
4. Remote model fetching (future)
