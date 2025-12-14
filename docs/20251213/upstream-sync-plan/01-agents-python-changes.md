# OpenAI Agents Python SDK - Upstream Changes Analysis

## Version / Scope

- **Baseline Commit**: `0d2d771` (not tagged; precedes `v0.6.2`)
- **Current Commit**: `71fa12c` (post-`v0.6.3`; example-only change)
- **Tags Within Range**: `v0.6.2` (`9fcc68f`), `v0.6.3` (`8e1fd7a`)
- **OpenAI SDK Dependency**: Bumped to `openai==2.9.0` (`5f2e83e`)

This analysis covers the mainline commit range `0d2d771..71fa12c` and focuses on
changes under `src/agents/`.

## Detailed Change Analysis

---

## 1. Response Chaining: `auto_previous_response_id`

### Commit: a9d95b4

### Description
Enables server-side `previous_response_id` mode to start on the first internal model call, without
requiring the caller to already have a previous response id.

### Python Implementation

```python
# src/agents/run.py (excerpt)
class RunOptions(TypedDict, Generic[TContext]):
    auto_previous_response_id: NotRequired[bool]

# Usage (Runner.run kwarg)
result = await Runner.run(
    agent,
    "Hello",
    auto_previous_response_id=True  # Automatically chains responses
)
```

Key mechanics:
- `src/agents/run.py` introduces `_ServerConversationTracker.auto_previous_response_id`, and updates
  `previous_response_id` after the first model response when using auto mode.
- `src/agents/result.py` already exposes `RunResultBase.last_response_id` as a convenience getter.

### Changes to Port

**Where it belongs in Elixir**: `Codex.RunConfig` (the Elixir SDK already models
`conversation_id` + `previous_response_id` there).

**Behavior**:
- When `true`, the SDK should capture the `response_id` from the first turn
- Automatically pass it as `previous_response_id` to subsequent turns
- Surface the last response id to callers (for external chaining)

**Important dependency note**:
The current Elixir SDK transport (`codex exec --experimental-json`) does not expose an OpenAI
`response_id` in its event stream. Implementing full parity may require backend support (either
enhanced codex output, or a direct Responses API integration).

**Files to Modify**:
- `lib/codex/run_config.ex` - Add `auto_previous_response_id` (default `false`)
- `lib/codex/agent_runner.ex` - Persist/update last response id when available

---

## 2. Logprobs Preservation (Chat Completions)

### Commit: df020d1

### Description
Preserves token-level probability data from the Chat Completions API by converting chat logprobs
into Responses-compatible `Logprob` models and attaching them to `ResponseOutputText.logprobs`.

### Python Implementation

```python
# src/agents/models/chatcmpl_helpers.py (excerpt)
def convert_logprobs_for_output_text(
    logprobs: list[ChatCompletionTokenLogprob] | None
) -> list[Logprob] | None: ...

def convert_logprobs_for_text_delta(
    logprobs: list[ChatCompletionTokenLogprob] | None
) -> list[DeltaLogprob] | None: ...
```

### Changes to Port

**Relevance to the Elixir SDK**:
- This change is specific to the Chat Completions provider path in agents-python.
- The open-source `codex exec --experimental-json` event stream does not currently surface logprobs.

**If/when logprobs are available in the Elixir SDK**:
- Prefer extending `Codex.Items.AgentMessage` with an optional `logprobs` field (keep the raw shape
  as returned) rather than inventing Elixir-native structs prematurely.

---

## 3. Usage Normalization

### Commit: 509ddda

### Description
Normalizes `None` token detail objects on `Usage` initialization to prevent TypeErrors.

### Python Implementation

```python
# src/agents/usage.py (excerpt)
def _normalize_input_tokens_details(
    v: InputTokensDetails | PromptTokensDetails | None,
) -> InputTokensDetails: ...

def _normalize_output_tokens_details(
    v: OutputTokensDetails | CompletionTokensDetails | None,
) -> OutputTokensDetails: ...
```

### Changes to Port

**Status in Elixir**:
The Elixir SDK currently treats usage as a flat numeric map (input/output/cached/reasoning tokens)
and merges defensively. There are no nested token-detail structs that can be `nil`.

**Files to Modify**:
- None required for the current exec event format.
- If the SDK later models nested token detail objects, normalize `nil` to `0` (or empty structs).

---

## 4. Apply-Patch Operations: Attach Run Context

### Commit: 9f96338

### Description
Threads the `RunContextWrapper` into apply-patch editor operations so host-defined editors can
inspect run context when applying patches.

### Python Implementation (excerpt)

```python
# src/agents/editor.py
class ApplyPatchOperation:
    ...
    ctx_wrapper: RunContextWrapper | None = None
```

### Changes to Port

If the Elixir SDK exposes host-side patch application hooks, include per-run context in the payload
(thread id, trace ids, etc.) so tool implementations can make context-aware decisions.

---

## 5. Realtime API Improvements

### Commits: e0e6794, 4d71290

### Description
- Allow sending None values to Realtime API
- Fixed CLI demo energy threshold settings

### Changes to Port

**Less Critical**: The Elixir port has placeholder Realtime support. These fixes would apply if/when full Realtime integration is implemented.

**Current Status**: `lib/codex/realtime.ex` exists as placeholder

---

## 6. LiteLLM Compatibility

### Commit: d258d8d

### Description
Preserves `reasoning.summary` when passing to LiteLLM.

### Changes to Port

**If using LiteLLM backend**: Ensure reasoning summary is preserved in model responses.

**Current Status**: Not directly applicable - Elixir port uses codex-rs which handles model calls.

---

## Not Included in This Sync

The following change is referenced in some downstream notes but is **not** part of the synced
mainline range `0d2d771..71fa12c`:

- `4abf66c` (“Add on_stream to agents as tools”) lives on `origin/agent-as-tool-streaming` and is
  not reachable from `71fa12c`.

---

## Summary: Required Changes for Elixir Port (From This Sync)

| Feature | Files to Modify | Complexity |
|---------|----------------|------------|
| Response Chaining (`auto_previous_response_id`) | `lib/codex/run_config.ex`, `lib/codex/agent_runner.ex` | Medium (backend-dependent) |
| Apply-patch context | Tool/patch hook surface (if exposed) | Low–Medium |
| Usage normalization | N/A for current exec usage shape | Low |
| Logprobs preservation | Blocked unless backend surfaces logprobs | Medium (backend-dependent) |

---

## Testing Requirements

For each ported feature, prefer fixture-based tests that assert the SDK’s observable behavior:
- When adding new config fields, validate parsing/normalization (`Codex.RunConfig.new/1`).
- When plumbing metadata through tool hooks, validate callback payload shape.
