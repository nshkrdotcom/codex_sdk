# Model Registry Port Documentation

This directory documents upstream Codex model registry behavior and how to port it into the Elixir SDK (`lib/codex/models.ex`).

## Sources of truth (in this repo)

- `codex/codex-rs/core/src/openai_models/model_presets.rs`
- `codex/codex-rs/core/models.json`
- `codex/codex-rs/core/src/openai_models/models_manager.rs`
- `codex/codex-rs/core/src/openai_models/model_family.rs`
- `codex/codex-rs/protocol/src/openai_models.rs`

## Key behavior changes in the upstream update

1. **New ChatGPT default**: `gpt-5.2-codex` is the default model for ChatGPT auth.
2. **New base model**: `gpt-5.2` is available for API and ChatGPT auth.
3. **Auth-aware defaults**: API key users default to `gpt-5.1-codex-max`; ChatGPT users default to `gpt-5.2-codex`.
4. **Auth mode inference**: prefer API key when `CODEX_API_KEY` or `auth.json` `openai_api_key` is present; otherwise use ChatGPT tokens.
5. **Remote model gating**: the remote model list is behind `features.remote_models` (default `false`).
6. **Model list merge**: when remote models are enabled, remote `/models` (fallback `models.json`) are merged with local presets; missing slugs (notably `gpt-5.2-codex`) are appended.
7. **Auto-balanced override**: `codex-auto-balanced` is preferred for ChatGPT when present in the remote list.

## Expected `list_models` output (remote_models disabled; default)

- **API key auth**: `gpt-5.1-codex-max` (default), `gpt-5.1-codex-mini`, `gpt-5.2`
- **ChatGPT auth**: `gpt-5.2-codex` (default), `gpt-5.1-codex-max`, `gpt-5.1-codex-mini`, `gpt-5.2`

## Documentation structure

| File | Description |
|------|-------------|
| [01-current-elixir-state.md](./01-current-elixir-state.md) | Current Elixir models.ex implementation |
| [02-upstream-model-presets.md](./02-upstream-model-presets.md) | Rust model_presets.rs analysis |
| [03-upstream-models-json.md](./03-upstream-models-json.md) | Bundled models.json fallback data |
| [04-model-family-config.md](./04-model-family-config.md) | Model family capabilities |
| [05-protocol-types.md](./05-protocol-types.md) | Protocol types for models |
| [06-port-requirements.md](./06-port-requirements.md) | Specific porting requirements |
| [07-implementation-plan.md](./07-implementation-plan.md) | Step-by-step implementation plan |
| [08-models-manager-flow.md](./08-models-manager-flow.md) | Merge, filter, and default logic |
| [09-streaming-telemetry-followup.md](./09-streaming-telemetry-followup.md) | Streaming telemetry lifecycle note |
