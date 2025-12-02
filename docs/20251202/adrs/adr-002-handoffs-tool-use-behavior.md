# ADR-002: Support Handoffs and Tool Use Behavior Controls

Status: Proposed

Context
- Python: `src/agents/handoffs/__init__.py` exposes Handoff objects with input filters/history nesting and dynamic enablement; `src/agents/agent.py:207-231` adds `tool_use_behavior` modes (`run_llm_again`, `stop_on_first_tool`, stop-at-tools, or custom function) plus `reset_tool_choice` default true.
- Elixir: no handoff abstraction; tool use is driven by codex responses with no SDK-level policy or tool-choice reset handling.

Decision
- Add `Codex.Handoff` struct and helpers to wrap sub-agents as tools with optional input filters and nested history; expose on `Codex.Agent.handoffs`.
- Implement `tool_use_behavior` and `reset_tool_choice` semantics in the runner, allowing stop-on-first-tool and stop-at-tools behaviors and custom callbacks.
- Ensure history nesting defaults align with Python (`RunConfig.nest_handoff_history` true) but allow opt-out.

Consequences
- Benefits: enables multi-agent delegation patterns and predictable tool loop behavior; matches Python mental model.
- Risks: depends on codex binary’s ability to pass handoff transcript cleanly; new behavior could surprise existing users if defaults differ.
- Actions: design handoff representation and history mapper; implement tool-use decision logic in `_run_single_turn`; add tests mirroring `tests/test_handoff_tool.py`, `tests/test_tool_use_behavior.py`, `tests/test_tool_choice_reset.py`.
