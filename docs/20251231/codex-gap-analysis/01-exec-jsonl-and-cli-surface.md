# Exec JSONL and CLI Surface Gaps

Agent: exec-cli

Upstream references
- `codex/codex-rs/exec/src/cli.rs`
- `codex/docs/exec.md`

Elixir references
- `lib/codex/exec.ex`
- `lib/codex/exec/options.ex`
- `lib/codex/thread/options.ex`
- `lib/codex/options.ex`

Gaps and deviations
- Gap: default sandbox for exec is workspace-write in the SDK because :default maps to "workspace-write"; codex exec default is read-only. Refs: `lib/codex/thread/options.ex`, `lib/codex/exec.ex`, `codex/docs/exec.md`.
- Gap: exec always passes a sandbox argument even when the user did not set one, overriding CLI trust/default behavior. Refs: `lib/codex/exec.ex`, `lib/codex/thread/options.ex`.
- Gap: model_provider override is ignored for exec; Thread.Options.model_provider is only used in app-server. Implement by mapping to `--config model_provider="..."` for exec. Refs: `lib/codex/thread/options.ex`, `lib/codex/exec.ex`.
- Gap: base_instructions and developer_instructions are not forwarded to exec; they only flow through app-server. Implement via `--config base_instructions="..."` and `--config developer_instructions="..."` (or `instructions` if preferred). Refs: `lib/codex/thread/options.ex`, `lib/codex/exec.ex`, `codex/codex-rs/core/src/config/mod.rs`.
- Gap: sandbox_policy fields (writable_roots, exclude_tmpdir_env_var, exclude_slash_tmp) are ignored for exec; only sandbox mode and network_access are passed. Implement by mapping sandbox_policy to config overrides such as `sandbox_workspace_write.writable_roots` and exclude flags. Refs: `lib/codex/thread/options.ex`, `lib/codex/exec.ex`, `codex/docs/config.md`.
- Gap: reasoning summary and verbosity are not exposed as SDK options for exec; only reasoning_effort is forwarded. Add fields and map to `model_reasoning_summary` and `model_verbosity` config overrides. Refs: `lib/codex/options.ex`, `lib/codex/exec.ex`, `codex/docs/config.md`.
- Gap: exec uses `--experimental-json` explicitly; upstream docs prefer `--json` (alias). Consider switching to `--json` to align with current CLI surface. Refs: `lib/codex/exec.ex`, `codex/codex-rs/exec/src/cli.rs`.
- Gap: no typed support for model provider network tuning (request_max_retries, stream_max_retries, stream_idle_timeout_ms) even though exec can accept them via config overrides. Add thread/turn options to surface these safely. Refs: `lib/codex/thread/options.ex`, `lib/codex/exec.ex`, `codex/docs/config.md`.
- Deviation: SDK sets OPENAI_API_KEY along with CODEX_API_KEY for exec/app-server; codex exec documents CODEX_API_KEY only. Confirm this does not trigger unintended auth or provider selection. Refs: `lib/codex/exec.ex`, `lib/codex/app_server/connection.ex`, `codex/docs/exec.md`.

Implementation notes
- To restore CLI defaults, treat :default as nil for exec, or add a new :inherit value that skips `--sandbox` and `approval_policy` overrides.
- Forward model_provider and instruction overrides via config_overrides to avoid new CLI flags.
- Extend Thread.Options validation for new fields only if you want typed, compile-time coverage; otherwise provide helper functions that add `config_overrides` entries.
