# ADR-004: Provide Function Tool Wrapper and Structured Tool Outputs

Status: Proposed

Context
- Python: `src/agents/tool.py` `function_tool` decorator builds JSON schemas (strict optional), dynamic enablement, and tool-specific guardrails; structured tool outputs (`ToolOutputText/Image/FileContent`) serialize to Responses inputs (`items.py:429-520`).
- Elixir: tools are modules registered via `Codex.Tools.register/2`; outputs are opaque maps; no schema generation or structured output helpers.

Decision
- Add a `Codex.function_tool` macro/helper to wrap Elixir functions into tool metadata with JSON schema (strict by default) and optional enablement callbacks and error handlers.
- Define structured tool output structs (text/image/file) and conversion utilities to codex-compatible input items; ensure lists of outputs are supported.
- Retain registry approach but enrich metadata with schema/guardrail info for codex exec.

Consequences
- Benefits: parity with Python ergonomics; reduces manual schema authoring; enables image/file outputs.
- Risks: schema generation from Elixir types may be lossy; must align with codex binary expectations for tool payloads.
- Actions: implement macro + schema builder; add structured output converters; update registry storage; test against parity cases (`tests/test_function_tool.py`, `tests/test_tool_output_conversion.py`, `tests/test_function_tool_decorator.py`, `tests/test_streaming_tool_call_arguments.py`).
