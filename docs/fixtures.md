# Python Parity Fixtures

Milestone 0 focuses on capturing golden event streams from the Python Codex SDK so that every Elixir parity test can replay deterministic transcripts. This document explains how to harvest, review, and maintain those fixtures.

## Goals
- Produce JSONL logs that represent the canonical behavior of key workflows (thread lifecycle, tools, structured output, sandbox approvals, error paths).
- Store fixtures under `integration/fixtures/python` with stable filenames and metadata.
- Regenerate fixtures as the Python SDK evolves, keeping a clear audit trail.

## Harvesting Workflow
1. **Clone Python SDK**  
   Check out the `openai-agents-python` repository next to this project (or set `CODEX_PYTHON_SDK_PATH`).

2. **Install Dependencies**  
   ```
   python3 -m venv .venv
   source .venv/bin/activate
   pip install -e .[dev]
   ```

3. **Build or Download codex-rs Binary**  
   Ensure the Python SDK runs against the same `codex-rs` version we pin in this repo. Point to it via `--codex-path` when running the harvester if needed.

4. **Run Harvester**  
   ```
   python3 scripts/harvest_python_fixtures.py \
     --python-sdk ../openai-agents-python \
     --output integration/fixtures/python
   ```

   Use `--scenario` to target a subset (e.g., `--scenario thread_basic`).

5. **Review Output**  
   Inspect generated `.jsonl` files and associated schemas. Confirm naming, metadata comments (if any), and absence of secrets.

6. **Commit Fixtures**  
   Add new or updated files under `integration/fixtures/`. Note in PR and update the parity checklist.

## Scenario Modules

The harvester expects the Python repo to provide modules under `harvest_scenarios.*` with a `record(output_path, **kwargs)` function. Each function should:
- Execute the relevant workflow using the Python SDK.
- Stream codex events into `output_path` as JSONL.
- Optionally write structured output schemas under `integration/fixtures/schemas`.

Example skeleton (in Python repo):
```python
from codex.client import CodexClient

def record(output_path, codex_path=None):
    client = CodexClient(codex_binary=codex_path)
    thread = client.start_thread()
    turn = client.run(thread, "hello")

    with open(output_path, "w", encoding="utf-8") as f:
        for event in turn.events:
            f.write(event.json() + "\n")
```

## Maintenance Checklist
- Update `SCENARIOS` in `scripts/harvest_python_fixtures.py` when new workflows need coverage.
- Track harvested scenarios and their freshness in `docs/python-parity-checklist.md`.
- Regenerate fixtures whenever the Python SDK changes behavior; keep diffs to confirm expected deltas.
- Ensure sensitive data is redacted before committing.

## Troubleshooting
- **Module Not Found**: Verify `PYTHONPATH` includes the Python repo (the harvester adds it automatically).
- **codex-rs Mismatch**: Rebuild or download the binary pinned in `config/native.exs` once available.
- **Fixture Drift**: Re-run harvester and compare diffs. Legitimate changes should be accompanied by updated Elixir tests.
