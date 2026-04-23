# Models and Reasoning Configuration

This guide explains how model selection and reasoning-effort levels work in the
Codex SDK, where canonical defaults live, and how to override them at every
layer of the configuration stack.

## Quick Reference

```elixir
# Use the bundled registry default model metadata (currently gpt-5.4)
{:ok, opts} = Codex.Options.new(%{})

# Explicitly choose a model
{:ok, opts} = Codex.Options.new(%{model: "gpt-5.5"})

# Override reasoning effort
{:ok, opts} = Codex.Options.new(%{model: "gpt-5.2", reasoning_effort: :high})

# Use the realtime default model
agent = %Codex.Realtime.Agent{model: Codex.Realtime.Agent.default_model()}
```

## Model Defaults

The SDK derives bundled text-model metadata from the shared
`CliSubprocessCore.ModelRegistry` catalog:

| Context | Default | Source |
|---------|---------|--------|
| API auth mode | `Codex.Models.default_model(:api)` | First picker-visible API-supported model from the active catalog, with `Codex.Config.Defaults.default_api_model/0` as fallback |
| ChatGPT auth mode | `Codex.Models.default_model(:chatgpt)` | First picker-visible ChatGPT model from the active catalog, with `Codex.Config.Defaults.default_chatgpt_model/0` as fallback |
| Realtime sessions | `Codex.Realtime.Agent.default_model()` | `@default_model` in `Codex.Realtime.Agent` |
| Speech-to-text | `Codex.Voice.Models.OpenAISTT.model_name()` | `@default_model` in `OpenAISTT` |
| Text-to-speech | `Codex.Voice.Models.OpenAITTS.model_name()` | `@default_model` in `OpenAITTS` |

`Codex.Models.default_model/0` is a registry reader. It does not apply env
overrides and it does not force live exec/app-server runs to use that model.
Those live runtime surfaces only pin a model when `Codex.Options` resolves an
explicit model from user input, `CODEX_MODEL`, or an OSS provider route.

The exact text default is catalog-derived, not a permanent public contract. With
the bundled catalog vendored in this repo, both text auth modes currently resolve
to `gpt-5.4`.

The active offline catalog lives in
`../cli_subprocess_core/priv/models/codex.json`. `priv/models.json` is kept as a
local snapshot of the installed CLI's visible model metadata for compatibility
with older docs and tools.

Persistent `Codex.OAuth` login participates in the same ChatGPT auth-mode model
selection. Memory-only external app-server auth is connection-local and does not
change the current BEAM process's default-model inference on its own.

### Environment Overrides

When you build `Codex.Options` without an explicit `:model`, the shared payload
resolver checks these environment variables (in order) before leaving model
selection implicit for the installed `codex` CLI runtime:

1. `CODEX_MODEL`
2. `OPENAI_DEFAULT_MODEL`
3. `CODEX_MODEL_DEFAULT`

```bash
CODEX_MODEL=gpt-5.5 mix run my_script.exs
```

## Available Models

Call `Codex.Models.list_visible/1` to see the bundled picker-visible catalog:

```elixir
iex> Codex.Models.list_visible(:api) |> Enum.map(& &1.id)
#=> [
#=>   "gpt-5.4",
#=>   "gpt-5.5",
#=>   "gpt-5.4-mini",
#=>   "gpt-5.3-codex",
#=>   "gpt-5.3-codex-spark",
#=>   "gpt-5.2"
#=> ]

iex> Codex.Models.list_visible(:chatgpt) |> Enum.map(& &1.id)
#=> [
#=>   "gpt-5.4",
#=>   "gpt-5.5",
#=>   "gpt-5.4-mini",
#=>   "gpt-5.3-codex",
#=>   "gpt-5.3-codex-spark",
#=>   "gpt-5.2"
#=> ]
```

That is the bundled picker-visible snapshot shipped with this repo and the
order `Codex.Models.list_visible/1` exposes locally. If upstream ships a newer
runtime-only model before the bundled catalog is refreshed here, pass it
explicitly via `model:` or `CODEX_MODEL`.

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
# Current Codex models do not accept :minimal, so it coerces to :low.
iex> Codex.Models.coerce_reasoning_effort("gpt-5.4-mini", :minimal)
:low

iex> Codex.Models.coerce_reasoning_effort("gpt-5.4-mini", :xhigh)
:xhigh
```

Use `Codex.Models.supported_reasoning_efforts/1` to query what a model accepts:

```elixir
iex> Codex.Models.supported_reasoning_efforts("gpt-5.4-mini")
[
  %{effort: :low, description: "Low"},
  %{effort: :medium, description: "Medium"},
  %{effort: :high, description: "High"},
  %{effort: :xhigh, description: "Xhigh"}
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

1. **Bundled registry metadata** - `Codex.Models.default_model/0` and `Codex.Models.default_reasoning_effort/1` expose the vendored catalog defaults
2. **Environment variables** - `CODEX_MODEL`, `OPENAI_DEFAULT_MODEL`, and `CODEX_MODEL_DEFAULT` are consumed when `Codex.Options` is built without an explicit model
3. **`Codex.Options`** - `:model` and `:reasoning_effort` fields
4. **`Codex.Thread.Options`** - per-thread overrides
5. **`Codex.Thread.Options.config_overrides`** - TOML-style key/value pairs
6. **Per-turn `config_overrides`** - passed to `Codex.Thread.run/3`

If `Codex.Options` still has no explicit model after that resolution, the exec
and app-server transports leave model selection to the installed `codex` CLI.

### `openai_base_url` and `model_providers`

Layered `config.toml` files can also affect provider resolution:

- `openai_base_url` overrides the built-in `openai` provider base URL and wins over `OPENAI_BASE_URL`
- user `[model_providers.<id>]` entries extend the built-in provider set
- reserved built-ins such as `openai`, `ollama`, and `lmstudio` cannot be overridden

Example:

```toml
openai_base_url = "https://gateway.example.com/v1"

[model_providers.openai_custom]
name = "OpenAI Custom"
base_url = "https://gateway.example.com/v1"
env_key = "OPENAI_API_KEY"
wire_api = "responses"
```

Use `model_provider = "openai_custom"` in config, or pass `model_provider` in thread options,
when you want turns to target the custom provider ID.

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
iex> Codex.Models.get_upgrade("gpt-5.5")
nil
```

Upgrade targets come from the bundled/current catalog and can change across
upstream pulls.

## Architecture: Where Defaults Live

The SDK follows a single-source-of-truth pattern for model defaults and model
metadata:

| Constant | Module | Used By |
|----------|--------|---------|
| Shared `CliSubprocessCore.ModelRegistry` catalog | `Codex.Models` | Visible model listing, default selection, upgrade metadata |
| `Codex.Config.Defaults.default_api_model/0` and `default_chatgpt_model/0` | `Codex.Config.Defaults` | Fallback when catalog-based default selection cannot resolve |
| `@default_model` | `Codex.Realtime.Agent` | `Codex.Realtime.Session`, examples |
| `@default_model` | `Codex.Voice.Models.OpenAISTT` | `OpenAIProvider`, examples |
| `@default_model` | `Codex.Voice.Models.OpenAITTS` | `OpenAIProvider`, examples |

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
