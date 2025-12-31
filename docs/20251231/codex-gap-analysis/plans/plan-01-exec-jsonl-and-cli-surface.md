# Implementation Plan - Exec JSONL and CLI Surface

Source
- docs/20251231/codex-gap-analysis/01-exec-jsonl-and-cli-surface.md

Goals
- Align exec JSONL CLI defaults with upstream codex behavior.
- Forward all relevant options (model provider, instructions, sandbox policy, reasoning controls).
- Expose provider tuning settings in a typed, SDK-friendly way.

Scope
- Exec transport argument construction and config overrides.
- Options and thread options structs/validation.
- Documentation updates for exec usage.

Plan
1. Audit existing exec argument builder and options validation.
   - Files: lib/codex/exec.ex, lib/codex/exec/options.ex, lib/codex/thread/options.ex.
2. Add or extend typed options.
   - model_reasoning_summary, model_verbosity, model_context_window,
     model_supports_reasoning_summaries.
   - request_max_retries, stream_max_retries, stream_idle_timeout_ms.
   - sandbox_policy details (writable_roots, exclude_tmpdir_env_var, exclude_slash_tmp).
   - Files: lib/codex/options.ex, lib/codex/thread/options.ex.
3. Introduce a shared config overrides builder that can emit properly quoted `--config` entries.
   - Use for model_provider, base_instructions, developer_instructions, reasoning settings,
     provider tuning, and sandbox policy keys.
   - Files: lib/codex/exec.ex (or new helper module), lib/codex/options.ex.
4. Align sandbox defaults for exec.
   - Treat :default as "inherit" and avoid passing `--sandbox` unless explicitly set.
   - Avoid overriding approval_policy unless explicitly set.
   - Files: lib/codex/exec.ex, lib/codex/thread/options.ex.
5. Map model_provider and instruction overrides for exec.
   - Use `--config model_provider=...` and `--config base_instructions=...` / `developer_instructions=...`.
   - Files: lib/codex/exec.ex.
6. Map sandbox policy fields for exec.
   - Translate `sandbox_policy.writable_roots` to `sandbox_workspace_write.writable_roots`.
   - Translate exclude flags to config keys as defined in codex/docs/config.md.
   - Files: lib/codex/exec.ex.
7. Switch exec JSON flag to `--json` (keep compatibility fallback if needed).
   - Files: lib/codex/exec.ex.
8. Review environment variables.
   - Confirm whether setting OPENAI_API_KEY alongside CODEX_API_KEY is acceptable;
     if not, gate behind an option and document.
   - Files: lib/codex/exec.ex, lib/codex/app_server/connection.ex.

Tests
- Add unit tests for options validation and config overrides.
- Add tests for exec argument construction, covering:
  - default sandbox omission,
  - model_provider/instruction overrides,
  - reasoning summary/verbosity,
  - provider retry/timeout overrides,
  - sandbox policy mapping.

Docs
- Update README and relevant docs in docs/ to describe new options and defaults.
- Update examples/ if new defaults change usage.

Acceptance criteria
- Exec CLI arguments match upstream defaults when no explicit overrides are provided.
- New options are validated and forwarded correctly.
- Tests cover default and override behavior with no regressions.
