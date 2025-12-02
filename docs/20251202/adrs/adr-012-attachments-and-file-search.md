# ADR-012: Align Attachments, Structured File/Image Outputs, and File Search

Status: Proposed

Context
- Python: structured tool outputs include file/image payloads (`ToolOutputFileContent`, `ToolOutputImage`), converted to Responses `input_file/input_image` items (`items.py:493-519`); `FileSearchTool` configures vector_store_ids, filters, ranking, include_search_results; history merging avoids resending server items.
- Elixir: `Codex.Files` stages local attachments with TTL/persist and attaches to thread options; no structured tool output helpers or file search config exposed; unknown mapping between staged files and codex request schema.

Decision
- Implement structured file/image output helpers and ensure runner translates them to codex-friendly input items (file_data/file_url/file_id/filename, image_url/detail/file_id).
- Map `Codex.Files` staging outputs into those schemas, ensuring checksum-based paths translate to file_data or upload ids; provide vector store/file search configuration on threads/runs.
- Preserve history merging semantics to avoid duplicate file/image inputs when resuming or streaming.

Consequences
- Benefits: parity for file/image tool outputs and hosted file search; better interop with codex attachments.
- Risks: codex upload API constraints; potential payload size issues; staging/cleanup must remain reliable.
- Actions: build converters and schema validations; wire file search options; extend attachment pipeline tests; mirror Python cases like `tests/test_tool_output_conversion.py` and create vector store fixtures.
