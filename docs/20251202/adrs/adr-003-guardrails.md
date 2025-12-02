# ADR-003: Add Input/Output/Tool Guardrails with Tripwires

Status: Proposed

Context
- Python: `src/agents/guardrail.py` defines input/output guardrails (parallel vs sequential, tripwire exceptions); `src/agents/tool_guardrails.py` provides tool input/output guardrails with behaviors (`allow`, `reject_content`, `raise_exception`); runner integrates guardrails in both blocking and streaming paths.
- Elixir: no guardrail concept; codex runs proceed unless approvals are triggered by the binary.

Decision
- Introduce guardrail structs and decorators (`Codex.Guardrail`, `Codex.ToolGuardrail`) for input/output/tool stages with run_in_parallel and behavior options.
- Integrate guardrail execution into the runner (pre-agent, pre/post tool) with tripwire errors halting runs and optional rejection messages surfaced to the model.
- Mirror streaming behavior by emitting guardrail results/events and enforcing tripwires mid-stream.

Consequences
- Benefits: safety and policy enforcement aligned with Python behavior; clearer failure modes.
- Risks: increases runner complexity; needs robust error taxonomy and telemetry; must ensure codex binary can accept rejection messages.
- Actions: define guardrail APIs, behaviors, and error structs; wire into turn loop and streaming; add tests similar to `tests/test_guardrails.py`, `tests/test_tool_guardrails.py`, `tests/test_stream_input_guardrail_timing.py`, `tests/test_tracing_errors_streamed.py`.
