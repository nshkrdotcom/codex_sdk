# Port Requirements for Elixir SDK

## Overview

This document specifies the exact changes needed to update `lib/codex/models.ex` to match upstream Codex model registry.

## Type Definition Updates

### Current Type
```elixir
@type model :: %{
  id: String.t(),
  default_reasoning_effort: reasoning_effort(),
  tool_enabled?: boolean(),
  default?: boolean()
}
```

### Updated Type
```elixir
@type reasoning_effort :: :none | :minimal | :low | :medium | :high | :xhigh

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

## Complete Model List

```elixir
@models [
  # === ACTIVE MODELS (show_in_picker: true) ===

  # NEW DEFAULT
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
    supported_in_api: false,  # ChatGPT auth only
    upgrade: nil
  },

  %{
    id: "gpt-5.1-codex-max",
    display_name: "gpt-5.1-codex-max",
    description: "Codex-optimized flagship for deep and fast reasoning.",
    default_reasoning_effort: :medium,
    supported_reasoning_efforts: [
      %{effort: :low, description: "Fast responses with lighter reasoning"},
      %{effort: :medium, description: "Balances speed and reasoning depth for everyday tasks"},
      %{effort: :high, description: "Greater reasoning depth for complex problems"},
      %{effort: :xhigh, description: "Extra high reasoning depth for complex problems"}
    ],
    tool_enabled?: true,
    default?: false,
    show_in_picker: true,
    supported_in_api: true,
    upgrade: %{
      id: "gpt-5.2-codex",
      migration_config_key: "gpt-5.2-codex",
      model_link: "https://openai.com/index/introducing-gpt-5-2-codex",
      upgrade_copy: "Codex is now powered by gpt-5.2-codex, our latest frontier agentic coding model. It is smarter and faster than its predecessors and capable of long-running project-scale work."
    }
  },

  %{
    id: "gpt-5.1-codex-mini",
    display_name: "gpt-5.1-codex-mini",
    description: "Optimized for codex. Cheaper, faster, but less capable.",
    default_reasoning_effort: :medium,
    supported_reasoning_efforts: [
      %{effort: :medium, description: "Dynamically adjusts reasoning based on the task"},
      %{effort: :high, description: "Maximizes reasoning depth for complex or ambiguous problems"}
    ],
    tool_enabled?: true,
    default?: false,
    show_in_picker: true,
    supported_in_api: true,
    upgrade: %{
      id: "gpt-5.2-codex",
      migration_config_key: "gpt-5.2-codex",
      model_link: "https://openai.com/index/introducing-gpt-5-2-codex",
      upgrade_copy: "Codex is now powered by gpt-5.2-codex, our latest frontier agentic coding model. It is smarter and faster than its predecessors and capable of long-running project-scale work."
    }
  },

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
    tool_enabled?: false,  # Base model, no tool support
    default?: false,
    show_in_picker: true,
    supported_in_api: true,
    upgrade: %{
      id: "gpt-5.2-codex",
      migration_config_key: "gpt-5.2-codex",
      model_link: "https://openai.com/index/introducing-gpt-5-2-codex",
      upgrade_copy: "Codex is now powered by gpt-5.2-codex, our latest frontier agentic coding model. It is smarter and faster than its predecessors and capable of long-running project-scale work."
    }
  },

  # === DEPRECATED MODELS (show_in_picker: false) ===

  %{
    id: "gpt-5-codex",
    display_name: "gpt-5-codex",
    description: "Optimized for codex.",
    default_reasoning_effort: :medium,
    supported_reasoning_efforts: [
      %{effort: :low, description: "Fastest responses with limited reasoning"},
      %{effort: :medium, description: "Dynamically adjusts reasoning based on the task"},
      %{effort: :high, description: "Maximizes reasoning depth for complex or ambiguous problems"}
    ],
    tool_enabled?: true,
    default?: false,
    show_in_picker: false,
    supported_in_api: true,
    upgrade: %{id: "gpt-5.2-codex", migration_config_key: "gpt-5.2-codex", model_link: "https://openai.com/index/introducing-gpt-5-2-codex", upgrade_copy: nil}
  },

  %{
    id: "gpt-5-codex-mini",
    display_name: "gpt-5-codex-mini",
    description: "Optimized for codex. Cheaper, faster, but less capable.",
    default_reasoning_effort: :medium,
    supported_reasoning_efforts: [
      %{effort: :medium, description: "Dynamically adjusts reasoning based on the task"},
      %{effort: :high, description: "Maximizes reasoning depth for complex or ambiguous problems"}
    ],
    tool_enabled?: true,
    default?: false,
    show_in_picker: false,
    supported_in_api: true,
    upgrade: %{id: "gpt-5.2-codex", migration_config_key: "gpt-5.2-codex", model_link: nil, upgrade_copy: nil}
  },

  %{
    id: "gpt-5.1-codex",
    display_name: "gpt-5.1-codex",
    description: "Optimized for codex.",
    default_reasoning_effort: :medium,
    supported_reasoning_efforts: [
      %{effort: :low, description: "Fastest responses with limited reasoning"},
      %{effort: :medium, description: "Dynamically adjusts reasoning based on the task"},
      %{effort: :high, description: "Maximizes reasoning depth for complex or ambiguous problems"}
    ],
    tool_enabled?: true,
    default?: false,
    show_in_picker: false,
    supported_in_api: true,
    upgrade: %{id: "gpt-5.2-codex", migration_config_key: "gpt-5.2-codex", model_link: nil, upgrade_copy: nil}
  },

  %{
    id: "gpt-5",
    display_name: "gpt-5",
    description: "Broad world knowledge with strong general reasoning.",
    default_reasoning_effort: :medium,
    supported_reasoning_efforts: [
      %{effort: :minimal, description: "Fastest responses with little reasoning"},
      %{effort: :low, description: "Balances speed with some reasoning"},
      %{effort: :medium, description: "Provides a solid balance of reasoning depth and latency"},
      %{effort: :high, description: "Maximizes reasoning depth for complex or ambiguous problems"}
    ],
    tool_enabled?: false,
    default?: false,
    show_in_picker: false,
    supported_in_api: true,
    upgrade: %{id: "gpt-5.2-codex", migration_config_key: "gpt-5.2-codex", model_link: nil, upgrade_copy: nil}
  },

  %{
    id: "gpt-5.1",
    display_name: "gpt-5.1",
    description: "Broad world knowledge with strong general reasoning.",
    default_reasoning_effort: :medium,
    supported_reasoning_efforts: [
      %{effort: :low, description: "Balances speed with some reasoning"},
      %{effort: :medium, description: "Provides a solid balance of reasoning depth and latency"},
      %{effort: :high, description: "Maximizes reasoning depth for complex or ambiguous problems"}
    ],
    tool_enabled?: false,
    default?: false,
    show_in_picker: false,
    supported_in_api: true,
    upgrade: %{id: "gpt-5.2-codex", migration_config_key: "gpt-5.2-codex", model_link: nil, upgrade_copy: nil}
  }
]
```

## Constant Updates

```elixir
# Update default model
@default_model "gpt-5.2-codex"

# Add reasoning effort (none was missing)
@reasoning_efforts [:none, :minimal, :low, :medium, :high, :xhigh]

# Update aliases
@reasoning_effort_aliases %{
  "none" => :none,
  "extra_high" => :xhigh,
  "extra-high" => :xhigh,
  "minimal" => :minimal,
  "low" => :low,
  "medium" => :medium,
  "high" => :high,
  "xhigh" => :xhigh
}
```

## New Functions to Add

```elixir
@doc """
Returns models visible in the model picker.
"""
@spec list_visible() :: [model()]
def list_visible do
  @models |> Enum.filter(& &1.show_in_picker)
end

@doc """
Returns the upgrade information for a model, if available.
"""
@spec get_upgrade(String.t()) :: model_upgrade() | nil
def get_upgrade(model_id) do
  case find_model(model_id) do
    %{upgrade: upgrade} -> upgrade
    _ -> nil
  end
end

@doc """
Returns the supported reasoning efforts for a model.
"""
@spec supported_reasoning_efforts(String.t()) :: [reasoning_effort_preset()]
def supported_reasoning_efforts(model_id) do
  case find_model(model_id) do
    %{supported_reasoning_efforts: efforts} -> efforts
    _ -> []
  end
end

@doc """
Returns true if a model is supported via API key authentication.
"""
@spec supported_in_api?(String.t()) :: boolean()
def supported_in_api?(model_id) do
  case find_model(model_id) do
    %{supported_in_api: supported} -> supported
    _ -> false
  end
end

@doc """
Returns the display name for a model.
"""
@spec display_name(String.t()) :: String.t() | nil
def display_name(model_id) do
  case find_model(model_id) do
    %{display_name: name} -> name
    _ -> nil
  end
end

@doc """
Returns the description for a model.
"""
@spec description(String.t()) :: String.t() | nil
def description(model_id) do
  case find_model(model_id) do
    %{description: desc} -> desc
    _ -> nil
  end
end
```

## Migration Notes

1. **Default Model Change**: The default model changes from `gpt-5.1-codex-max` to `gpt-5.2-codex`. Existing users may need notification.

2. **API vs ChatGPT Auth**: `gpt-5.2-codex` is `supported_in_api: false`, meaning it's only available via ChatGPT authentication initially. The SDK should handle this appropriately.

3. **Backwards Compatibility**: All existing models are preserved (hidden from picker but functional). Existing code using `gpt-5.1-codex-max` will continue to work.

4. **Environment Override**: The existing env var override logic (`CODEX_MODEL`, `OPENAI_DEFAULT_MODEL`, `CODEX_MODEL_DEFAULT`) should continue to work.
