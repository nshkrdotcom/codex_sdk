# Models, compaction, and prompt handling changes for the Elixir SDK

Upstream changes:
- New model defaults and reasoning-level tweaks (gpt-5.1 family) shipped; some experimental tool-enabled models were added.
- Remote compaction is on by default with explicit compaction events and token-usage updates emitted during turns.
- Truncation helpers were refactored to avoid double-truncation and to tokenize more accurately during unified exec and history replay.

SDK impact:
- Validate that default model selection and reasoning options in the SDK match the upstream CLI defaults.
- Compaction now surfaces explicit events and token deltas; SDK consumers should be ready to handle those streams.
- Any SDK-side truncation or history replay should align with the refactored helpers to avoid mismatched token accounting.

Action items:
- Refresh the model list/constants exposed by the SDK and document reasoning effort defaults.
- Add support for compaction events and token-usage updates in event handling and tests.
- Revisit truncation logic (or delegate to the CLI) to mirror upstream behavior and prevent drift in prompt sizing.
