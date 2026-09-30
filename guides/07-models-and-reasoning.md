# Models and Reasoning Configuration

The SDK reads model metadata from `CliSubprocessCore.ModelRegistry`; it does
not maintain a second catalog. Version 0.21 requires CLI Core 0.9.

## Quick Reference

```elixir
{:ok, opts} = Codex.Options.new(%{model: "gpt-6.1-sol", reasoning_effort: :low})
{:ok, opts} = Codex.Options.new(%{model: "gpt-5.6-terra", reasoning_effort: :ultra})
Codex.Models.default_model() # "gpt-6.1-sol"
```

## Model Defaults

Both auth modes expose the same bundled picker and registry default. Omitting
an explicit model in a live invocation still lets the installed CLI choose;
the registry reader itself does not apply environment overrides. Runtime
configuration materializes `CODEX_MODEL`, `OPENAI_DEFAULT_MODEL`, and
`CODEX_MODEL_DEFAULT` in that order when supplied.

Realtime, speech-to-text, and text-to-speech use their own model defaults.
A CLI catalog refresh does not change those separate API surfaces.

## Available Models

Authenticated `codex-cli 0.159.0` `model/list` with `includeHidden: true`
was captured on 2026-09-29. The shared Core fixture
`test/fixtures/codex_model_list_20260929.json` records the response.

| Picker model | Default effort | Allowed CLI efforts |
| --- | --- | --- |
| `gpt-6.1-sol` (default) | `low` | low, medium, high, xhigh, max, ultra |
| `gpt-6-astra` | `low` | low, medium, high, xhigh, max, ultra |
| `gpt-6-sol` | `medium` | low, medium, high, xhigh, max, ultra |
| `gpt-6-luna` | `medium` | low, medium, high, xhigh, max |
| `gpt-5.6-sol` | `low` | low, medium, high, xhigh, max, ultra |
| `gpt-5.6-terra` | `medium` | low, medium, high, xhigh, max, ultra |
| `gpt-5.6-luna` | `medium` | low, medium, high, xhigh, max |
| `gpt-5.5` | `medium` | low, medium, high, xhigh |

`gpt-reserve` and `codex-auto-review` are internal and omitted from the
picker. GPT-5.4 Mini, GPT-5.4, and Spark were absent from this live response and are no longer
bundled entries; explicit unknown-model passthrough remains available.
The SDK convenience aliases `astra` and `gpt-6` resolve to `gpt-6-astra`;
they are not claims about provider API aliases.

```elixir
Codex.Models.list_visible(:api) |> Enum.map(& &1.id)
# ["gpt-6.1-sol", "gpt-6-astra", "gpt-6-sol", "gpt-6-luna", "gpt-5.6-sol", "gpt-5.6-terra",
#  "gpt-5.6-luna", "gpt-5.5"]
```

GPT-6.1 Sol uses low by default in Codex CLI and supports CLI `ultra`.
The [official GPT-6.1 Sol API model page](https://developers.openai.com/api/docs/models/gpt-6.1-sol)
lists low through max; API requests do not support `none` or `minimal`.

The [official Astra API model page](https://developers.openai.com/api/docs/models/gpt-6-astra)
lists low through max, a 1,050,000-token context, and 128,000 maximum output.
The additional `ultra` effort above is authenticated **Codex CLI** evidence,
not Responses API support. Registry effort multipliers are SDK normalization
values, not measured cost ratios.

### Dependency And Release Ordering

Committed dependencies are ordinary Hex requirements. Operator-managed local
development uses the MWO bootstrap and Portfolio Registry source coordinates.
Publish from ordinary standalone Hex mode in this order:

1. Publish GroundPlane Contracts 0.1.1. Existing Persistence Policy 0.1.0,
   Execution Plane core 0.3.0, and JSON-RPC 0.2.0 remain prerequisites; do not republish them.
2. Publish `execution_plane_process 0.3.1`.
3. Refresh Core's Hex lock and publish `cli_subprocess_core 0.9.2`.
4. Refresh this SDK's Hex lock, rerun QC, and publish `codex_sdk 0.21.3`.

Tag the exact published commit `v0.21.3` after verifying the Hex release.
The vendored upstream source is historical protocol evidence; this model
refresh does not assert full parity with every CLI 0.159.0 feature.

### Models Newer Than The Bundled Registry

The bundled catalog is a vendored snapshot - it lags real upstream releases
between SDK versions. `Codex.Options` does not need to wait for a catalog
refresh to use a new model: pass it explicitly via `model:` or `CODEX_MODEL`
and it passes through as-is, because `allow_unknown_model` defaults to `true`
(matching the installed `codex` CLI, which does not itself validate `--model`
against this registry):

```elixir
iex> {:ok, opts} = Codex.Options.new(%{model: "gpt-5.7-not-yet-bundled"})
16:20:00.000 [warning] Codex model "gpt-5.7-not-yet-bundled" is not in the
bundled model registry; passing it through as-is. ...
iex> opts.model
"gpt-5.7-not-yet-bundled"
iex> opts.model_payload.extra["unregistered"]
true
```

Reasoning-effort coercion and upgrade metadata are unavailable for a
passthrough model (`supported_reasoning_efforts/1` returns `[]`,
`get_upgrade/1` returns `nil`), since neither exists in the bundled catalog
for it - but the model id itself reaches the CLI/app-server unchanged.

Pass `allow_unknown_model: false` to restore strict rejection (useful for
catching a typo'd `CODEX_MODEL`/`model:` early rather than silently sending
it to the CLI):

```elixir
iex> Codex.Options.new(%{model: "gpt-5.7-not-yet-bundled", allow_unknown_model: false})
{:error, {:unknown_model, "gpt-5.7-not-yet-bundled", [...known ids...], :codex}}
```

`Codex.Thread.Options` (the `:app_server` transport) has always accepted any
model string without registry validation at all - there is no
`allow_unknown_model` flag there because there is nothing to opt out of.

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

Current upstream Responses requests always include a reasoning object and ask
for encrypted reasoning content, using configured effort or the selected
model's default. Reasoning summaries are still capability-aware: Codex omits
the summary parameter and its streaming-delivery option when the final selected
model does not support reasoning summaries. These are CLI transport behaviors;
the SDK continues to pass the corresponding model and reasoning configuration
through without duplicating that capability gate.

### Valid Levels

| Atom | String | Description |
|------|--------|-------------|
| `:none` | `"none"` | No reasoning |
| `:minimal` | `"minimal"` | Minimal reasoning |
| `:low` | `"low"` | Fast responses with lighter reasoning |
| `:medium` | `"medium"` | Balanced speed and reasoning depth (model-dependent default) |
| `:high` | `"high"` | Greater reasoning depth for complex problems |
| `:xhigh` | `"xhigh"` | Extra-high reasoning for the most complex problems |
| `:max` | `"max"` | Upstream's highest first-class effort level |
| `:ultra` | `"ultra"` | Upstream's highest-yet first-class effort level |

Aliases `"extra_high"` and `"extra-high"` are also accepted and normalize to
`:xhigh`. Any other non-empty string is accepted and passed through
unchanged (e.g. a model-specific effort value newer than this list) - only
`normalize_reasoning_effort/1` rejects blank/empty input. GPT-5.6 Sol and Terra
advertise both `:max` and `:ultra`; Luna advertises `:max` but not `:ultra`.
Validation is model-specific.

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
iex> Codex.Models.get_upgrade("gpt-5.5").id
"gpt-5.6-sol"

iex> Codex.Models.get_upgrade("gpt-5.4")
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
