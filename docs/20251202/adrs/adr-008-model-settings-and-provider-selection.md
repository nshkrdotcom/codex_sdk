# ADR-008: Expand Model Settings and Provider Selection

Status: Proposed

Context
- Python: `src/agents/model_settings.py` supports temperature/top_p/penalties/tool_choice/parallel_tool_calls/truncation/max_tokens/reasoning/verbosity/metadata/store/prompt_cache/response_include/top_logprobs/extra headers/body/query/args; defaults adapt to GPT-5 via `models/default_models.py`. `RunConfig` allows provider override with `OpenAIProvider` toggling Responses vs Chat Completions and default model from `OPENAI_DEFAULT_MODEL`.
- Elixir: `Codex.Options` exposes base_url, model, reasoning_effort; no fine-grained settings, provider selection, or env-based default model beyond codex defaults.

Decision
- Add a `Codex.ModelSettings` struct mirroring Python fields and merging behavior; feed through `RunConfig` and agent defaults.
- Support provider selection (Responses vs Chat Completions) and `OPENAI_DEFAULT_MODEL` env, mapping to codex CLI flags or request payloads; fall back gracefully if unsupported by binary.
- Provide `set_default_openai_api/key/client` equivalents to configure defaults and tracing export key reuse.

Consequences
- Benefits: feature parity for model tuning and API mode selection; better alignment with upstream defaults; developer control over tool choice and parallel tool calls.
- Risks: some settings may be ignored by codex; user confusion if options are silently unsupported; need validation with clear errors.
- Actions: design struct and merge semantics; wire through runner to codex exec; add validation and tests mirroring `tests/test_run_config.py`, `tests/models/test_default_models.py`, `tests/models/test_kwargs_functionality.py`, `tests/models/test_litellm_user_agent.py`.
