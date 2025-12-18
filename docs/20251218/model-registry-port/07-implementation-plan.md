# Implementation Plan

## Phase 1: Update Type Definitions

### Step 1.1: Add new types to models.ex

```elixir
@type reasoning_effort_preset :: %{
  effort: reasoning_effort(),
  description: String.t()
}

@type model_upgrade :: %{
  id: String.t(),
  migration_config_key: String.t(),
  model_link: String.t() | nil,
  upgrade_copy: String.t() | nil
}
```

### Step 1.2: Update model type

```elixir
@type model :: %{
  id: String.t(),
  display_name: String.t(),
  description: String.t(),
  default_reasoning_effort: reasoning_effort(),
  supported_reasoning_efforts: [reasoning_effort_preset()],
  tool_enabled?: boolean(),
  default?: boolean(),
  show_in_picker: boolean(),
  supported_in_api: boolean(),
  upgrade: model_upgrade() | nil
}
```

### Step 1.3: Update reasoning_effort type

Add `:none` to the reasoning effort type:

```elixir
@type reasoning_effort :: :none | :minimal | :low | :medium | :high | :xhigh
@reasoning_efforts [:none, :minimal, :low, :medium, :high, :xhigh]
```

## Phase 2: Update Model Registry

### Step 2.1: Update @default_model

```elixir
@default_model "gpt-5.2-codex"
```

### Step 2.2: Add GPT-5.2-codex (new default)

```elixir
%{
  id: "gpt-5.2-codex",
  display_name: "gpt-5.2-codex",
  description: "Latest frontier agentic coding model.",
  default_reasoning_effort: :medium,
  supported_reasoning_efforts: [
    %{effort: :low, description: "Fast responses with lighter reasoning"},
    %{effort: :medium, description: "Balances speed and reasoning depth for everyday tasks"},
    %{effort: :high, description: "Greater reasoning depth for complex problems"},
    %{effort: :xhigh, description: "Extra high reasoning depth for complex problems"}
  ],
  tool_enabled?: true,
  default?: true,
  show_in_picker: true,
  supported_in_api: false,
  upgrade: nil
}
```

### Step 2.3: Add GPT-5.2

```elixir
%{
  id: "gpt-5.2",
  display_name: "gpt-5.2",
  description: "Latest frontier model with improvements across knowledge, reasoning and coding",
  default_reasoning_effort: :medium,
  supported_reasoning_efforts: [
    %{effort: :low, description: "Balances speed with some reasoning; useful for straightforward queries"},
    %{effort: :medium, description: "Provides a solid balance of reasoning depth and latency"},
    %{effort: :high, description: "Maximizes reasoning depth for complex or ambiguous problems"},
    %{effort: :xhigh, description: "Extra high reasoning for complex problems"}
  ],
  tool_enabled?: false,
  default?: false,
  show_in_picker: true,
  supported_in_api: true,
  upgrade: @gpt_52_codex_upgrade
}
```

### Step 2.4: Update existing models

Update all existing models with:
- `display_name` field
- `description` field
- `supported_reasoning_efforts` list
- `show_in_picker` field
- `supported_in_api` field
- `upgrade` field (pointing to gpt-5.2-codex)
- Set `default?: false` for gpt-5.1-codex-max

### Step 2.5: Add deprecated models

Add hidden models for backwards compatibility:
- `gpt-5-codex`
- `gpt-5-codex-mini`
- `gpt-5.1-codex`
- `gpt-5`
- `gpt-5.1`

## Phase 3: Add New Functions

### Step 3.1: Add list_visible/0

```elixir
@spec list_visible() :: [model()]
def list_visible do
  @models |> Enum.filter(& &1.show_in_picker)
end
```

### Step 3.2: Add get_upgrade/1

```elixir
@spec get_upgrade(String.t()) :: model_upgrade() | nil
def get_upgrade(model_id) do
  model_id
  |> normalize_model()
  |> find_model()
  |> Map.get(:upgrade)
end
```

### Step 3.3: Add supported_reasoning_efforts/1

```elixir
@spec supported_reasoning_efforts(String.t()) :: [reasoning_effort_preset()]
def supported_reasoning_efforts(model_id) do
  model_id
  |> normalize_model()
  |> find_model()
  |> Map.get(:supported_reasoning_efforts, [])
end
```

### Step 3.4: Add supported_in_api?/1

```elixir
@spec supported_in_api?(String.t()) :: boolean()
def supported_in_api?(model_id) do
  model_id
  |> normalize_model()
  |> find_model()
  |> Map.get(:supported_in_api, false)
end
```

### Step 3.5: Add description/1 and display_name/1

```elixir
@spec description(String.t()) :: String.t() | nil
def description(model_id) do
  model_id
  |> normalize_model()
  |> find_model()
  |> Map.get(:description)
end

@spec display_name(String.t()) :: String.t() | nil
def display_name(model_id) do
  model_id
  |> normalize_model()
  |> find_model()
  |> Map.get(:display_name)
end
```

## Phase 4: Update find_model/1

Update to return a more complete default for unknown models:

```elixir
defp find_model(model) do
  Enum.find(@models, fn m -> m.id == model end) ||
    %{
      id: model,
      display_name: model,
      description: nil,
      default_reasoning_effort: nil,
      supported_reasoning_efforts: [],
      tool_enabled?: false,
      default?: false,
      show_in_picker: false,
      supported_in_api: false,
      upgrade: nil
    }
end
```

## Phase 5: Define Shared Upgrade Module Attribute

```elixir
@gpt_52_codex_upgrade %{
  id: "gpt-5.2-codex",
  migration_config_key: "gpt-5.2-codex",
  model_link: "https://openai.com/index/introducing-gpt-5-2-codex",
  upgrade_copy: "Codex is now powered by gpt-5.2-codex, our latest frontier agentic coding model. It is smarter and faster than its predecessors and capable of long-running project-scale work."
}
```

## Testing Checklist

- [ ] `list/0` returns all models including new ones
- [ ] `list_visible/0` returns only models with `show_in_picker: true`
- [ ] `default_model/0` returns `"gpt-5.2-codex"` by default
- [ ] `default_model/0` respects environment variable overrides
- [ ] `default_reasoning_effort/1` works for all models
- [ ] `tool_enabled?/1` returns correct values
- [ ] `get_upgrade/1` returns upgrade info for models with upgrades
- [ ] `supported_reasoning_efforts/1` returns correct effort lists
- [ ] `supported_in_api?/1` returns `false` for `gpt-5.2-codex`
- [ ] `normalize_reasoning_effort/1` handles `:none`
- [ ] Unknown models return sensible defaults

## Breaking Changes

### Potentially Breaking
1. Default model changes from `gpt-5.1-codex-max` to `gpt-5.2-codex`
2. Model type now has required fields (`display_name`, `description`, etc.)

### Mitigations
1. Keep `@default_model` overridable via environment variables
2. Use `Map.get/3` with defaults when accessing new fields to maintain backwards compatibility
3. Add `list_visible/0` rather than changing `list/0` behavior

## Rollout Strategy

1. **Phase 1**: Add new types and fields (backwards compatible)
2. **Phase 2**: Add new models to registry
3. **Phase 3**: Add new helper functions
4. **Phase 4**: Update default model to `gpt-5.2-codex`
5. **Phase 5**: Update documentation and changelog
