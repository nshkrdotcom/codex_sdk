Python
- Structured tool outputs support binary/file payloads: `ToolOutputFileContent` (`src/agents/tool.py:96-125`) accepts `file_data` (base64), `file_url`, or `file_id` plus optional filename; converted to Responses `input_file` items in `ItemHelpers._convert_single_tool_output_pydantic_model` (`items.py:507-519`).
- Image outputs can reference `image_url` or `file_id` with detail hints via `ToolOutputImage` (`tool.py:67-94`), serialized to `input_image` items (`items.py:493-506`).
- Tool outputs may be lists of structured items or plain text; `ItemHelpers.tool_call_output_item` (`items.py:429-470`) normalizes the model-facing payload.
- Hosted file-centric tools: `FileSearchTool` (`tool.py:195-218`) searches vector stores by `vector_store_ids`, with optional filters/ranking and `include_search_results`.
- Conversation history merging preserves raw input items (including files/images) through `ItemHelpers.input_to_new_input_list` (`items.py:397-408`) and `_ServerConversationTracker.prepare_input` (`run.py:151-171`), avoiding duplicate server items.

Elixir status
- Attachments are staged locally via `Codex.Files` (e.g., `lib/codex/files.ex:52-185`), creating checksum-addressed copies with TTL/persist flags and attaching them to thread options. Turn execution relies on codex exec to upload/stage.
- No structured tool output helpers for returning file/image content from tools; tool outputs are opaque maps.
- No vector store search configuration or inline `file_id`/`file_url` handling exposed in SDK.

Gaps/deltas
- Missing helpers to emit structured file/image outputs from Elixir tools and convert them to codex-compatible inputs.
- No parity for file search tool configuration or `include_search_results` semantics.
- Python relies on caller-provided `file_id/file_data` rather than a staging layer; Elixir staging exists but lacks mapping to Python-style schema fields.

Porting steps + test plan
- Add tool output structs for files/images/text mirroring `ToolOutput*` and conversion helpers that translate Elixir tool returns into codex request items; test with parity cases from `tests/test_tool_output_conversion.py` and `tests/test_tool_call_serialization.py`.
- Map `Codex.Files` staging outputs to response input shapes (`input_file` with file_data/file_url/file_id/filename) and ensure codex exec accepts them; add integration similar to `test/integration/attachment_pipeline_test.exs`.
- Introduce file search configuration on threads/turns (vector_store_ids, include_search_results, filters) and validate via new fixtures emulating `FileSearchTool` behavior.
- Verify history merging preserves attachments without duplication using continuation/stream tests aligned with `_ServerConversationTracker` expectations.***
