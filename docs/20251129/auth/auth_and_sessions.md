# Auth, account, and session handling notes for the Elixir SDK

Upstream changes:
- Enterprises can skip upgrade checks/messages; rollout session initialization errors were clarified.
- Conversations are dropped when invoking `/new`, and early-exit sessions are no longer persisted.
- Regression fixes landed for experimental sandbox command assessment and Azure/OpenAI rate-limit handling.

SDK impact:
- If the SDK mirrors the CLI conversation lifecycle, ensure `/new` semantics and early-exit handling match upstream.
- Auth/storage flows may surface fewer upgrade prompts; document any divergence if the SDK keeps older behavior.
- Rate-limit and sandbox assessment changes may alter error shapes; update parsers accordingly.

Action items:
- Align conversation/session reset behavior with upstream before releasing the next SDK cut.
- Verify auth prompts and rate-limit error parsing in integration tests.
- Note the skipped-upgrade behavior in release notes if it affects embedded CLI usage.
