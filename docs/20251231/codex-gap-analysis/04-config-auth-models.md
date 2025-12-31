# Config, Auth, and Models Gaps

Agent: config-auth

Upstream references
- `codex/docs/config.md`
- `codex/codex-rs/core/src/config/mod.rs`

Elixir references
- `lib/codex/config/layer_stack.ex`
- `lib/codex/options.ex`
- `lib/codex/models.ex`
- `lib/codex/auth.ex`
- `lib/codex/thread/options.ex`

Gaps and deviations
- Gap: config parsing is partial. LayerStack only reads `features.remote_models` and `project_root_markers`; all other config keys, profiles, and TOML types are ignored. Implement a full TOML reader and typed config struct, or add a thin layer for commonly used keys (model_provider, shell_environment_policy, history, features). Refs: `lib/codex/config/layer_stack.ex`, `codex/docs/config.md`.
- Gap: model_provider override is not forwarded for exec transport. Add config override mapping for `model_provider` when Thread.Options.model_provider is set. Refs: `lib/codex/thread/options.ex`, `lib/codex/exec.ex`.
- Gap: missing typed options for model_reasoning_summary and model_verbosity. These are supported in upstream config but not surfaced in Options or Thread.Options. Add fields and map to config overrides. Refs: `codex/docs/config.md`, `lib/codex/options.ex`.
- Gap: missing typed options for model_context_window and model_supports_reasoning_summaries. These should be settable for advanced users and forwarded as config overrides. Refs: `codex/docs/config.md`, `lib/codex/options.ex`.
- Gap: `shell_environment_policy` is unsupported. SDK only supports `env` and `clear_env?`, not the include/exclude/filter semantics of the CLI. Implement policy mapping or provide helpers to generate config overrides. Refs: `codex/docs/config.md`, `lib/codex/exec.ex`.
- Gap: feature flags in config are not surfaced as SDK options (apply_patch_freeform, view_image_tool, unified_exec, skills). Add explicit options or helpers to set `features.*` overrides. Refs: `codex/docs/config.md`, `lib/codex/thread/options.ex`.
- Gap: keyring-based auth store is not supported. CLI can store credentials in OS keyring via `cli_auth_credentials_store`; SDK only reads auth.json. This breaks ChatGPT token detection and remote model fetch when keyring is used. Refs: `codex/docs/config.md`, `lib/codex/auth.ex`, `lib/codex/models.ex`.
- Gap: forced_login_method and forced_chatgpt_workspace_id are not enforced by the SDK when using app-server login flows. Consider validating before login_start or documenting the limitation. Refs: `codex/docs/config.md`, `lib/codex/app_server/account.ex`.

Implementation notes
- If full TOML parsing is too heavy, add a ConfigOverrides helper that builds correctly quoted `--config` strings for common keys.
- For keyring support, a minimal path is to detect `cli_auth_credentials_store` and skip remote model fetch with a clear warning.
