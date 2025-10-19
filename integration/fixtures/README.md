# Integration Fixtures

This directory stores golden transcripts and schemas captured from the Python Codex SDK. Fixtures are generated during **Milestone 0 – Discovery & Characterization** using the harvesting script under `scripts/harvest_python_fixtures.py`.

## Layout

- `python/` — JSONL event streams emitted by the Python client for representative scenarios.
- `schemas/` — Structured-output JSON schemas referenced by fixtures.

Each fixture must include metadata in its filename (e.g., `thread_basic.jsonl`, `auto_run_tool_retry.jsonl`) and remain stable to support contract testing.

## Regeneration Workflow
1. Clone `openai-agents-python` and ensure it can run against the local `codex-rs` binary.
2. Activate the Python virtualenv and install dependencies (`pip install -e .[dev]`).
3. Run the harvesting script: `python3 scripts/harvest_python_fixtures.py --python-sdk ../openai-agents-python --output integration/fixtures/python`.
4. Review generated fixtures and commit alongside any schema updates.

Never edit fixtures by hand—always regenerate from the canonical Python client to maintain parity.
