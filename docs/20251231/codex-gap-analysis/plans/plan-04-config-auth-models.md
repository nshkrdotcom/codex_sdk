# Implementation Plan - Config, Auth, and Models

Source
- docs/20251231/codex-gap-analysis/04-config-auth-models.md

Goals
- Expand config parsing to cover core upstream keys.
- Expose missing model and reasoning options in the SDK.
- Support keyring-based auth and enforced login constraints.

Scope
- Config layer parsing and overrides.
- Options structs for model and reasoning controls.
- Auth flows for app-server and exec.

Plan
1. Expand config parsing.
   - Implement a typed config struct that covers: model_provider, features.*, history.*,
     shell_environment_policy, cli_auth_credentials_store, project_root_markers.
   - Ensure layered config precedence matches upstream.
   - Files: lib/codex/config/layer_stack.ex (and new modules as needed).
2. Add typed options for model/reasoning controls.
   - model_reasoning_summary, model_verbosity, model_context_window,
     model_supports_reasoning_summaries.
   - Ensure options map to config overrides for exec and app-server.
   - Files: lib/codex/options.ex, lib/codex/thread/options.ex.
3. Add feature flag helpers.
   - Surface features.apply_patch_freeform, features.view_image_tool,
     features.unified_exec, features.skills in options or helper APIs.
   - Files: lib/codex/thread/options.ex, lib/codex/options.ex.
4. Implement shell_environment_policy mapping.
   - Provide include/exclude semantics and translate to config or env handling.
   - Files: lib/codex/exec.ex, lib/codex/config/layer_stack.ex.
5. Support keyring-based auth.
   - Detect cli_auth_credentials_store and attempt to read keyring entries.
   - If OS keyring support is not available, emit a clear warning and disable
     remote model fetch rather than silently failing.
   - Files: lib/codex/auth.ex, lib/codex/models.ex.
6. Enforce forced login constraints.
   - Validate forced_login_method and forced_chatgpt_workspace_id before login.
   - Files: lib/codex/app_server/account.ex.

Tests
- Config parsing tests for new keys and layered precedence.
- Option mapping tests for reasoning and model controls.
- Auth tests for keyring detection and forced login constraints.

Docs
- Update README and docs/config references to cover new config support.
- Document keyring behavior and any platform limitations.

Acceptance criteria
- Config keys described in codex/docs/config.md are honored or explicitly documented.
- Model and reasoning options are available and correctly mapped.
- Auth flow respects keyring and forced login constraints.
