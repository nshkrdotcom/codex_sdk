# ADR-001: Add Agent Abstraction and Multi-Turn Runner

Status: Proposed

Context
- Python: `src/agents/agent.py` defines Agent with instructions/prompt, handoffs, output_type, tool_use_behavior, guardrails, hooks; `src/agents/run.py` provides `Runner.run/run_sync/run_streamed`, `RunConfig`, max_turns enforcement, conversation resume.
- Elixir: `lib/codex/thread.ex` runs single codex turn (or auto-run retry) without Agent struct or RunConfig; no per-run hooks or reusable agent definitions.

Decision
- Introduce `Codex.Agent` struct and `Codex.RunConfig` mirroring Python semantics (instructions/prompt, model settings overrides, hooks, tool_use_behavior placeholder, guardrail lists, nest_handoff_history, call_model_input_filter later).
- Replace the one-shot `Thread.run/3` orchestration with a multi-turn runner that loops until final output or max_turns, including handoff/tool handling.
- Keep existing `Codex.Thread` as thin facade over the new runner for compatibility.

Consequences
- Benefits: unlocks feature parity (handoffs, guardrails, sessions), clearer public API, reusable agent templates.
- Risks: significant refactor of turn pipeline; needs careful backward compatibility and telemetry continuity; may expose codex binary limitations.
- Actions: design `Codex.Agent` and `Codex.RunConfig` structs; build runner loop with max_turns and error taxonomy; update docs/examples; add migration helpers to wrap old Thread calls.
