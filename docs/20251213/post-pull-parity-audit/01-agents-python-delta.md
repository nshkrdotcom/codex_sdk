# openai-agents-python delta (`0d2d771..71fa12c`)

This section focuses on **runtime** changes under `openai-agents-python/src/` (not the translated
docs churn).

Upstream commits in-range affecting `src/`:

- `a9d95b4` — `auto_previous_response_id`
- `509ddda` — usage normalization
- `df020d1` — chat-completions logprobs preservation
- `9f96338` — apply-patch context threading
- `d258d8d` — LiteLLM reasoning.summary preservation
- `e0e6794` — allow `None` values to Realtime API

## Applicability rules (Elixir SDK)

The Elixir SDK is not a direct port of the Python runtime; it wraps the **Codex CLI**. A Python
feature is “applicable” only if:

1. There is a corresponding concept in the Codex CLI transport we use (`codex exec --experimental-json`), or
2. It is a public SDK-facing option that we can safely accept/store without breaking behavior,
   even if the current transport cannot exercise it yet (forward-compatible wiring).

## Commit-by-commit analysis

### `a9d95b4` — `auto_previous_response_id`

**Upstream behavior**
- Adds `auto_previous_response_id` to run config and enables “previous_response_id mode” even on
  the first turn (so chaining activates once a `response_id` becomes available).

**Elixir status**
- Implemented as `Codex.RunConfig.auto_previous_response_id` (default `false`, validated boolean).
- Runner stores `last_response_id` when a backend `response_id` is observed and can reuse it as
  `previous_response_id` for subsequent internal turns when enabled.

**Transport caveat**
- `codex exec --experimental-json` does not currently surface a `response_id`, so this feature is
  effectively dormant on the exec transport. The implementation is defensive and does not crash
  when absent.

### `509ddda` — usage normalization (token detail objects)

**Upstream behavior**
- Normalizes optional token detail objects (`cached_tokens`, `reasoning_tokens`) to `0` when
  providers return `None` or when model construction bypasses validation.

**Elixir status**
- Not a 1:1 mapping: the exec transport emits a simple usage shape (see `02-codex-rs-delta.md`),
  and the SDK currently represents usage as a `map()` (not a typed nested structure).

**What is still worth porting**
- Ensure the SDK normalizes missing integer usage keys to `0` when producing any *SDK-authored*
  aggregates (e.g., if we expose helpers that sum usage across turns).
- Ensure docs/examples always treat usage keys as optional on exec transport.

### `df020d1` — preserve chat-completions logprobs

**Upstream behavior**
- Carries logprobs from Chat Completions into Responses-like output items.

**Elixir applicability**
- Not applicable on the exec transport. Codex CLI JSONL does not expose logprobs today, and the
  Elixir SDK does not directly wrap the Chat Completions API.

### `9f96338` — apply-patch context threading

**Upstream behavior**
- Adds `ctx_wrapper` to `ApplyPatchOperation`, allowing host editors to access run context.

**Elixir status**
- Partial equivalence: the Elixir hosted tool callbacks already receive a `context` map containing
  `:thread`, `:event`, user metadata, and other run information.

**Remaining work**
- Audit the context passed to the `apply_patch` hosted tool to ensure it includes:
  - thread/session identifiers when available
  - turn attempt counters
  - trace metadata when tracing is enabled
- Add documentation for what `context` contains for hosted tools (especially `apply_patch`).

### `d258d8d` — LiteLLM reasoning.summary preservation

**Elixir applicability**
- Not applicable: the SDK does not integrate LiteLLM model adapters.

### `e0e6794` — allow `None` values to Realtime API

**Elixir applicability**
- Not applicable today: the SDK’s realtime/voice surface is currently a deliberate “unsupported”
  stub. If/when realtime is implemented, this is a reminder to tolerate null/optional fields in
  client events.

## Takeaway

From `openai-agents-python`, the only directly actionable parity work for our current SDK is:

- Keep `auto_previous_response_id` wired (done).
- Tighten hosted tool context guarantees (apply_patch context) and document them.
- Treat the usage-normalization change as a design signal for future typed usage helpers, not as a
  direct port.

