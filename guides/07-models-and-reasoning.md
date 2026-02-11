# Models and Reasoning Configuration

This guide explains how model selection and reasoning-effort levels work in the
Codex SDK, where canonical defaults live, and how to override them at every
layer of the configuration stack.

## Quick Reference

```elixir
# Use the SDK default model (currently gpt-5.3-codex)
{:ok, opts} = Codex.Options.new(%{})

# Explicitly choose a model
{:ok, opts} = Codex.Options.new(%{model: "gpt-5.1-codex-mini"})

# Override reasoning effort
{:ok, opts} = Codex.Options.new(%{model: "gpt-5.2", reasoning_effort: :high})

# Use the realtime default model
agent = %Codex.Realtime.Agent{model: Codex.Realtime.Agent.default_model()}
```

## Model Defaults

The SDK defines default models in `Codex.Models`:

| Context | Default | Source |
|---------|---------|--------|
| API auth mode | `Codex.Models.default_model(:api)` | `@default_api_model` in `Codex.Models` |
| ChatGPT auth mode | `Codex.Models.default_model(:chatgpt)` | `@default_chatgpt_model` in `Codex.Models` |
| Realtime sessions | `Codex.Realtime.Agent.default_model()` | `@default_model` in `Codex.Realtime.Agent` |
| Speech-to-text | `Codex.Voice.Models.OpenAISTT.model_name()` | `@default_model` in `OpenAISTT` |
| Text-to-speech | `Codex.Voice.Models.OpenAITTS.model_name()` | `@default_model` in `OpenAITTS` |

### Environment Overrides

The SDK checks these environment variables (in order) before falling back to
the compiled default:

1. `CODEX_MODEL`
2. `OPENAI_DEFAULT_MODEL`
3. `CODEX_MODEL_DEFAULT`

```bash
CODEX_MODEL=gpt-5.1-codex-max mix run my_script.exs
```

## Available Models

Call `Codex.Models.list_visible/1` to see what models are available for the
current auth mode:

```elixir
iex> Codex.Models.list_visible(:api) |> Enum.map(& &1.id)
["gpt-5.1-codex-max", "gpt-5.1-codex-mini", "gpt-5.2"]
```

Each model preset includes:

- `id` / `model` / `display_name` - the model identifier
- `description` - short human-readable description
- `default_reasoning_effort` - the effort level used when none is specified
- `supported_reasoning_efforts` - the effort levels the model accepts
- `is_default` - whether this is the default for the auth mode
- `upgrade` - optional upgrade path to a newer model

## Reasoning Effort

Reasoning effort controls how much "thinking" the model does before responding.
Higher effort produces better answers for complex problems but increases latency
and cost.

### Valid Levels

| Atom | String | Description |
|------|--------|-------------|
| `:none` | `"none"` | No reasoning |
| `:minimal` | `"minimal"` | Minimal reasoning |
| `:low` | `"low"` | Fast responses with lighter reasoning |
| `:medium` | `"medium"` | Balanced speed and reasoning depth (default) |
| `:high` | `"high"` | Greater reasoning depth for complex problems |
| `:xhigh` | `"xhigh"` | Extra-high reasoning for the most complex problems |

Aliases `"extra_high"` and `"extra-high"` are also accepted and normalize to
`:xhigh`.

### Setting Reasoning Effort

**At the Options level** (applies to all threads):

```elixir
{:ok, opts} = Codex.Options.new(%{reasoning_effort: :high})
```

**At the Thread level** (per-thread override):

```elixir
{:ok, thread_opts} = Codex.Thread.Options.new(%{reasoning_effort: :low})
```

**Per-turn** (via config overrides):

```elixir
Codex.Thread.run(thread, "complex question", %{
  config_overrides: [{"model_reasoning_effort", "xhigh"}]
})
```

### Automatic Coercion

Not all models support all effort levels. When you request an unsupported level,
the SDK automatically coerces it to the nearest supported value:

```elixir
# gpt-5.1-codex-mini only supports :medium and :high
iex> Codex.Models.coerce_reasoning_effort("gpt-5.1-codex-mini", :xhigh)
:high

iex> Codex.Models.coerce_reasoning_effort("gpt-5.1-codex-mini", :low)
:medium
```

Use `Codex.Models.supported_reasoning_efforts/1` to query what a model accepts:

```elixir
iex> Codex.Models.supported_reasoning_efforts("gpt-5.1-codex-mini")
[
  %{effort: :medium, description: "Dynamically adjusts reasoning based on the task"},
  %{effort: :high, description: "Maximizes reasoning depth for complex or ambiguous problems"}
]
```

### Normalizing Effort Values

Use `Codex.Models.normalize_reasoning_effort/1` to parse strings or atoms:

```elixir
iex> Codex.Models.normalize_reasoning_effort("extra_high")
{:ok, :xhigh}

iex> Codex.Models.normalize_reasoning_effort(:medium)
{:ok, :medium}

iex> Codex.Models.normalize_reasoning_effort("invalid")
{:error, {:invalid_reasoning_effort, "invalid"}}
```

## Configuration Layers

Model and reasoning configuration follows the SDK's layered override system.
Later layers take precedence:

1. **Compiled defaults** - `Codex.Models.default_model()`, `:medium` effort
2. **Environment variables** - `CODEX_MODEL`, etc.
3. **`Codex.Options`** - `:model` and `:reasoning_effort` fields
4. **`Codex.Thread.Options`** - per-thread overrides
5. **`Codex.Thread.Options.config_overrides`** - TOML-style key/value pairs
6. **Per-turn `config_overrides`** - passed to `Codex.Thread.run/3`

### Config Overrides

Both `Codex.Options` and `Codex.Thread.Options` accept a `:config` map that
gets serialized as `--config key=value` CLI flags:

```elixir
{:ok, opts} = Codex.Options.new(%{
  config: %{
    "model_reasoning_effort" => "xhigh",
    "model_reasoning_summary" => "concise"
  }
})
```

Nested maps are automatically flattened with dot notation:

```elixir
%{"sandbox_workspace_write" => %{"network_access" => true}}
# becomes: "sandbox_workspace_write.network_access" => true
```

## Model Verbosity

Model verbosity is separate from reasoning effort. It controls how much detail
the model includes in its responses:

```elixir
{:ok, thread_opts} = Codex.Thread.Options.new(%{model_verbosity: :low})
```

Valid values: `:low`, `:medium`, `:high` (or their string equivalents).

## Realtime and Voice Models

Realtime and voice subsystems use separate model families:

### Realtime

```elixir
# Uses the default realtime model
agent = Codex.Realtime.agent(name: "Assistant")

# Override with a specific model
agent = Codex.Realtime.agent(name: "Mini", model: "gpt-4o-mini-realtime-preview")
```

The default realtime model is accessible via `Codex.Realtime.Agent.default_model/0`.

### Voice (STT/TTS)

```elixir
# Default STT model
stt = Codex.Voice.Models.OpenAISTT.new()

# Default TTS model
tts = Codex.Voice.Models.OpenAITTS.new()

# Custom models
stt = Codex.Voice.Models.OpenAISTT.new("whisper-1")
tts = Codex.Voice.Models.OpenAITTS.new("tts-1-hd")
```

The `OpenAIProvider` delegates to the individual STT/TTS module defaults.

## Upgrade Paths

Some models have upgrade paths to newer versions. Query them with:

```elixir
iex> Codex.Models.get_upgrade("gpt-5.1-codex-max")
%{
  id: "gpt-5.3-codex",
  migration_config_key: "gpt-5.1-codex-max",
  reasoning_effort_mapping: nil,
  ...
}
```

## Architecture: Where Defaults Live

The SDK follows a single-source-of-truth pattern for all model defaults:

| Constant | Module | Used By |
|----------|--------|---------|
| `@default_api_model` | `Codex.Models` | `Codex.Options`, `Codex.Thread`, all exec/transport code |
| `@default_model` | `Codex.Realtime.Agent` | `Codex.Realtime.Session`, examples |
| `@default_model` | `Codex.Voice.Models.OpenAISTT` | `OpenAIProvider`, examples |
| `@default_model` | `Codex.Voice.Models.OpenAITTS` | `OpenAIProvider`, examples |
| `@efforts_full` | `Codex.Models` | Shared across model presets with full effort support |
| `@efforts_mini` | `Codex.Models` | Shared across mini-class model presets |
| `@efforts_standard` | `Codex.Models` | Shared across standard codex presets |

Downstream modules reference these via public functions (`default_model/0`,
`model_name/0`) rather than duplicating string literals.

### For Tests

Import `Codex.Test.ModelFixtures` to reference canonical model constants:

```elixir
import Codex.Test.ModelFixtures

test "uses the default model" do
  {:ok, opts} = Options.new(%{})
  assert opts.model == default_model()
end
```

Available fixtures: `default_model/0`, `alt_model/0`, `max_model/0`,
`realtime_model/0`, `stt_model/0`, `tts_model/0`.
