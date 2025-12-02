Python
- `src/agents/run.py:179-267` `RunConfig` controls model override, provider, model_settings overlay, handoff history nesting/mapping, guardrails, tracing toggles (`tracing_disabled`, `trace_include_sensitive_data`), workflow/group metadata, custom trace ids, session handling callbacks, and `call_model_input_filter` to mutate instructions/input before model invocation.
- `src/agents/run.py:106-110` defaults `trace_include_sensitive_data` from `OPENAI_AGENTS_TRACE_INCLUDE_SENSITIVE_DATA` env (true unless explicitly falsey).
- `src/agents/_config.py:8-26` and `src/agents/__init__.py:172-200` expose setters for default OpenAI key/client and default API flavor (chat_completions vs responses), optionally reused for tracing exports.
- `src/agents/models/default_models.py:9-58` picks default model from `OPENAI_DEFAULT_MODEL` (fallback `gpt-4.1`), and adapts default `ModelSettings` for GPT-5 reasoning requirements.
- `src/agents/model_settings.py:69-190` provides per-call knobs: temperature, top_p, penalties, tool_choice/parallel_tool_calls, truncation, max_tokens, reasoning effort, verbosity, metadata, store flag, prompt cache retention, include_usage, response_include fields, top_logprobs, and extra headers/body/query/args merging via `resolve`.
- `src/agents/models/openai_provider.py:28-97` allows provider-level api_key/base_url/organization/project overrides or custom AsyncOpenAI client; switches between Responses and Chat Completions based on `use_responses` default or override.

Elixir status
- `lib/codex/options.ex:11-179` offers `api_key`, `base_url`, `codex_path_override`, telemetry prefix, model, and reasoning_effort defaults; derives key from env or codex CLI credentials. No per-call model settings beyond model/reasoning_effort.
- No equivalent env-driven tracing toggles; telemetry uses `Codex.Telemetry` with prefix configuration only.
- No provider abstraction; always shells out to codex binary using configured base_url/model.
- No hook to filter or mutate model payloads before execution.

Gaps/deltas
- Missing fine-grained model settings (temperature/top_p/penalties/tool_choice/parallel calls/truncation/prompt cache/response_include).
- No configuration for trace metadata, workflow/group IDs, sensitive-data inclusion, or disabling tracing per run.
- Lacks run-level mutation hooks (`call_model_input_filter`) and session input callbacks.
- Provider selection (chat_completions vs responses) and default model env parity absent.

Porting steps + test plan
- Extend `Codex.Options`/`Codex.Thread.Options` with a struct mirroring `ModelSettings` fields, mapping to codex CLI flags or request body; add validation similar to `model_settings.py` and tests akin to `tests/test_model_payload_iterators.py`.
- Add run-level config struct with trace metadata fields and a hook to pre-process payloads (Elixir function accepting instructions/input), validating behavior with parity cases from `tests/test_call_model_input_filter.py`.
- Introduce env toggles for tracing sensitive data and default model selection (`OPENAI_AGENTS_TRACE_INCLUDE_SENSITIVE_DATA`, `OPENAI_DEFAULT_MODEL`) with unit coverage.
- Add provider-style overrides for base URL/api key per run; ensure compatibility with codex exec args and cover via option tests similar to `tests/test_config.py` and `tests/test_run_config.py`.***
