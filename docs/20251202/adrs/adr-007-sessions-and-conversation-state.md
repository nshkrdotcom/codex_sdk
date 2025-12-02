# ADR-007: Add Session Abstraction and Conversation Resume

Status: Proposed

Context
- Python: `src/agents/memory/session.py` defines Session protocol; `sqlite_session.py` and `openai_conversations_session.py` implement durable history; runner merges history via `_prepare_input_with_session` (`run.py:1903-1940`) and supports `session_input_callback`, `conversation_id`, and `previous_response_id` to avoid resending server items.
- Elixir: relies on codex continuation tokens only; no session protocol or merge callbacks; no conversation_id/previous_response_id handling.

Decision
- Introduce `Codex.Session` behaviour and built-ins (SQLite-backed, optional OpenAI Conversations if API permits) to persist input items across runs; allow custom session implementations.
- Add session merge callback equivalent (`session_input_callback`) and enforce list-input validation when sessions are used.
- Extend runner to track server items (conversation_id/previous_response_id) when codex supports it; otherwise document fallback to continuation tokens.

Consequences
- Benefits: durable chat memory and resumption parity; predictable history merging; better handling of server-stored conversations.
- Risks: persistence and locking concerns; divergence if codex cannot expose conversation IDs; more branching in runner.
- Actions: define protocol and adapters; integrate merge logic; guard list-input requirements; test similar to `tests/test_session.py`, `tests/test_openai_conversations_session.py`, `tests/test_session_exceptions.py`.
