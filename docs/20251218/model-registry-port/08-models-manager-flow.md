# Models Manager Flow

## File Location
`codex/codex-rs/core/src/openai_models/models_manager.rs`

## Key Constants

```rust
const OPENAI_DEFAULT_API_MODEL: &str = "gpt-5.1-codex-max";
const OPENAI_DEFAULT_CHATGPT_MODEL: &str = "gpt-5.2-codex";
const CODEX_AUTO_BALANCED_MODEL: &str = "codex-auto-balanced";
```

## Remote Model Gating

Remote models are only used when `features.remote_models` is enabled (default `false`). When disabled:
- The remote list is empty.
- `list_models` returns only local presets from `model_presets.rs`.

## Remote Models Fetching

When enabled:

1. Remote models are loaded from the embedded `models.json` at startup.
2. `/models` is fetched when possible (ChatGPT auth only), using ETag caching.
3. API key auth skips the network fetch; the list remains the bundled `models.json`.
4. The client version header is major/minor/patch only (`0.0.0` dev builds send `99.99.99`).
5. Results are stored in `models_cache.json` for reuse (TTL: 300 seconds).

## List Models Algorithm

1. Load remote models (empty if feature disabled).
2. Sort remote models by `priority` (ascending).
3. Convert each `ModelInfo` to `ModelPreset`.
4. Merge with local presets:
   - If a slug exists in remote models, ignore the local preset.
   - Otherwise, append the local preset (notably `gpt-5.2-codex`).
5. Filter visible models:
   - `show_in_picker == true`
   - If auth mode is API key, also require `supported_in_api == true`.
6. If no model is marked `is_default`, mark the first entry as default.

## Default Model Selection (`get_model`)

If no model is explicitly provided:

1. If ChatGPT auth and `codex-auto-balanced` exists in the remote list, return it.
2. If ChatGPT auth, return `gpt-5.2-codex`.
3. Otherwise, return `gpt-5.1-codex-max`.

## Implications for Elixir Port

- The SDK should treat default selection as auth-aware, not purely static.
- When remote models are disabled, list models should match local presets:
  - API key auth: `gpt-5.1-codex-max` (default), `gpt-5.1-codex-mini`, `gpt-5.2`
  - ChatGPT auth: `gpt-5.2-codex` (default), `gpt-5.1-codex-max`, `gpt-5.1-codex-mini`, `gpt-5.2`
- Remote model enablement introduces additional visible models (e.g., `gpt-5.1`, `gpt-5.1-codex`) based on `models.json` or `/models`.
