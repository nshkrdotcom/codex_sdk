# ADR-014: Realtime and Voice Feature Scope

Status: Proposed

Context
- Python includes realtime and voice pipelines (`tests/realtime/*`, `tests/voice/*`, `src/agents/realtime`, `src/agents/voice`) covering audio formats, playback trackers, SIP/Twilio integration, and realtime model conversions.
- Elixir SDK currently has no realtime or voice support; codex binary capabilities for these are unclear.

Decision
- Defer implementation of realtime/voice features until core agent parity is delivered and codex binary capabilities are confirmed.
- Document lack of support in Elixir docs and provide clear error paths if users attempt realtime/voice APIs.
- Re-evaluate after core parity to decide whether to invest in a realtime/voice layer or keep out-of-scope.

Consequences
- Benefits: focuses effort on core agent parity; avoids speculative work without backend confidence.
- Risks: feature gap remains vs Python; potential user confusion if expectations are not managed.
- Actions: note exclusion in README/docs; add minimal stubs raising informative errors; create follow-up decision once codex support is clarified.
