# Models and Reasoning Configuration

This guide explains how model selection and reasoning-effort levels work in the
Codex SDK, where canonical defaults live, and how to override them at every
layer of the configuration stack.

## Quick Reference

```elixir
# Use the bundled registry default model metadata (currently gpt-5.6-sol)
{:ok, opts} = Codex.Options.new(%{})

# Explicitly choose a model
{:ok, opts} = Codex.Options.new(%{model: "gpt-5.6-sol"})

# Override reasoning effort
{:ok, opts} = Codex.Options.new(%{model: "gpt-5.6-terra", reasoning_effort: :ultra})

# A model newer than the bundled registry passes through by default (with a
# logged warning) - see "Models Newer Than The Bundled Registry" below
{:ok, opts} = Codex.Options.new(%{model: "gpt-5.7-not-yet-bundled"})

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

The exact text default is catalog-derived, not a permanent public contract.
With the shared catalog selected for this SDK, both text auth modes currently
resolve to `gpt-5.6-sol` (default reasoning effort `:low`).

Upstream's separate Amazon Bedrock catalog also prioritizes GPT-5.6 Sol as its
provider default, followed by Terra and Luna. That catalog behavior is distinct
from the experimental Bedrock login request, which current upstream still
reports as unimplemented.

The active offline catalog is owned by `CliSubprocessCore.ModelRegistry`. In a
sibling development checkout its Codex data lives at
`../cli_subprocess_core/priv/models/codex.json`; standalone and released builds
consume the same catalog from their selected `cli_subprocess_core` dependency.
This SDK does not ship or read a second model-data copy.

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
CODEX_MODEL=gpt-5.6-sol mix run my_script.exs
```

## Available Models

Call `Codex.Models.list_visible/1` to see the bundled picker-visible catalog:

```elixir
iex> Codex.Models.list_visible(:api) |> Enum.map(& &1.id)
#=> [
#=>   "gpt-5.6-sol",
#=>   "gpt-5.6-terra",
#=>   "gpt-5.6-luna",
#=>   "gpt-5.5",
#=>   "gpt-5.4",
#=>   "gpt-5.4-mini",
#=>   "gpt-5.3-codex-spark"
#=> ]

iex> Codex.Models.list_visible(:chatgpt) |> Enum.map(& &1.id)
#=> [
#=>   "gpt-5.6-sol",
#=>   "gpt-5.6-terra",
#=>   "gpt-5.6-luna",
#=>   "gpt-5.5",
#=>   "gpt-5.4",
#=>   "gpt-5.4-mini",
#=>   "gpt-5.3-codex-spark"
#=> ]
```

That is the bundled picker-visible snapshot shipped with this repo and the
order `Codex.Models.list_visible/1` exposes locally. The catalog also carries
an internal `codex-auto-review` entry (visibility `:internal`) that
`list_visible/1` omits by default, matching upstream's "hide" visibility for
that model.

This catalog was last verified 2026-07-10 against a live `model/list`
JSON-RPC probe (including `includeHidden: true`) run directly against an
authenticated `codex-cli 0.144.1` install. The pulled upstream source snapshot
placed GPT-5.6 Sol first and still listed `gpt-5.2`; the live backend made Sol
the default, exposed Spark, and did not serve `gpt-5.2`. A live Spark exec also
returned the expected response. The bundled catalog therefore follows the
live current CLI contract. Repeat the probe with
`Codex.AppServer.model_list(conn, include_hidden: true)` when the installed CLI
changes.

The current specialized Codex IDs are explicit:

| Model | Role | Default effort | Supported efforts |
| --- | --- | --- | --- |
| `gpt-5.6-sol` | Frontier agentic coding | `:low` | `:low`, `:medium`, `:high`, `:xhigh`, `:max`, `:ultra` |
| `gpt-5.6-terra` | Balanced everyday agentic coding | `:medium` | `:low`, `:medium`, `:high`, `:xhigh`, `:max`, `:ultra` |
| `gpt-5.6-luna` | Fast agentic coding | `:medium` | `:low`, `:medium`, `:high`, `:xhigh`, `:max` |
| `gpt-5.3-codex-spark` | Near-instant text-only ChatGPT Pro preview | `:high` | `:low`, `:medium`, `:high`, `:xhigh` |

The OpenAI API's `gpt-5.6` family alias is not added to this Codex CLI catalog.
Select one of the explicit IDs reported by `model/list`.
Spark is a ChatGPT Pro research preview with a separate usage limit and is not
available through the OpenAI API at launch; inspect `supported_in_api` before
presenting it in API-key-only product UI.

Upstream model-availability announcements now consider only the first eligible
catalog entry. Once that announcement reaches its display limit, Codex shows no
announcement instead of falling back to an older model's announcement.

### Dependency And Release Ordering

Development dependency selection prefers a real sibling path, then the GitHub
source, then Hex. Release tasks intentionally select Hex, so a release consumes
the catalog published by `cli_subprocess_core`, not an arbitrary workspace
copy. Publish the dependency chain bottom-up:

1. `ground_plane_contracts` and `ground_plane_persistence_policy`
2. `execution_plane`, `execution_plane_jsonrpc`, and `execution_plane_process`
3. `cli_subprocess_core`
4. `codex_sdk`

Publishing `codex_sdk` 0.17.0 is currently blocked because those five Ground
Plane and Execution Plane packages are not yet available on Hex, and publish
mode cannot lock the current core dependency graph. This SDK must not be
published until that chain is released and verified from a clean Hex-only
consumer.

The recommended installed CLI remains `codex-cli 0.144.1`; no stable 0.145
release is available. The SDK also carries additive parser coverage derived
from newer protocol source. Those optional fields are harmless when absent and
become available when the connected CLI emits them. A live app-server build
reporting 0.144.1 already exposed turn timing, while the current exec JSONL
terminal event still exposes usage only.

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
| `:medium` | `"medium"` | Balanced speed and reasoning depth (default) |
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
iex> Codex.Models.get_upgrade("gpt-5.5")
nil

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
