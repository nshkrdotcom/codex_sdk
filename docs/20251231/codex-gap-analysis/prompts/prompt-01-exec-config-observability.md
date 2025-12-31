# Prompt - Exec, Config, and Observability Parity

Goal
Implement all work described in these plans:
- docs/20251231/codex-gap-analysis/plans/plan-00-overview.md
- docs/20251231/codex-gap-analysis/plans/plan-01-exec-jsonl-and-cli-surface.md
- docs/20251231/codex-gap-analysis/plans/plan-04-config-auth-models.md
- docs/20251231/codex-gap-analysis/plans/plan-07-observability-rate-limit-errors.md

Required reading before coding
Gap analysis docs
- docs/20251231/codex-gap-analysis/01-exec-jsonl-and-cli-surface.md
- docs/20251231/codex-gap-analysis/04-config-auth-models.md
- docs/20251231/codex-gap-analysis/07-observability-rate-limit-errors.md

Upstream references
- codex/docs/exec.md
- codex/docs/config.md
- codex/codex-rs/exec/src/cli.rs
- codex/codex-rs/core/src/config/mod.rs
- codex/codex-rs/protocol/src/protocol.rs

Elixir sources
- lib/codex/exec.ex
- lib/codex/exec/options.ex
- lib/codex/thread/options.ex
- lib/codex/options.ex
- lib/codex/config/layer_stack.ex
- lib/codex/models.ex
- lib/codex/auth.ex
- lib/codex/app_server/account.ex
- lib/codex/transport/app_server.ex
- lib/codex/retry.ex
- lib/codex/rate_limit.ex
- lib/codex/events.ex
- lib/codex/error.ex
- lib/codex/thread.ex

Context and constraints
- Ignore the known CLI bundling difference; do not edit codex/ except for reference.
- Preserve backward compatibility; behavior changes must be opt-in or clearly documented.
- Use ASCII-only edits.

Implementation requirements
- Align exec JSONL CLI defaults with upstream behavior; avoid passing sandbox or approval_policy unless explicitly set.
- Forward model_provider, base_instructions, developer_instructions, and sandbox_policy details via config overrides.
- Add typed options for reasoning summary/verbosity/context window/supports reasoning summaries.
- Add typed options for provider tuning (request_max_retries, stream_max_retries, stream_idle_timeout_ms).
- Expand config parsing to cover core keys (features.*, history.*, shell_environment_policy, cli_auth_credentials_store).
- Implement keyring auth handling with clear warnings when unsupported.
- Enforce forced_login_method and forced_chatgpt_workspace_id in login flows.
- Wire Codex.Retry and Codex.RateLimit into exec and app-server as opt-in.
- Normalize exec errors into Codex.Error and add stream idle timeout handling.

Documentation and release requirements
- Update README.md and any affected guides in docs/ and examples/.
- Update CHANGELOG.md 0.4.6 entry with the changes implemented here.
- Update the 0.4.6 highlights in README.md.

Testing and quality requirements
- Run: mix format
- Run: mix test
- Run: MIX_ENV=test mix credo --strict
- Run: MIX_ENV=dev mix dialyzer
- No warnings or errors are acceptable.

Deliverable
- Provide a concise change summary and list the tests executed.
