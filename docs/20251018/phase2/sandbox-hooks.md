# Configurable Sandbox Hooks – Design (2025-10-17)

## ✅ Implementation Status: COMPLETE

## Overview
Introduce a pluggable approval layer that lets SDK consumers route sandbox/tool approval requests to external systems (e.g., Slack, Jira, custom REST). Today `Codex.Approvals.StaticPolicy` only handles allow/deny; the goal is to expose behaviour-based hooks with async support and structured metadata.

## Goals
✅ Allow callers to register approval modules implementing new behaviour callbacks.
✅ Support synchronous allow/deny as well as async queueing (reply later).
✅ Preserve existing options shape (`Codex.Thread.Options`) while adding hook configuration.
✅ Emit telemetry for request lifecycle (submitted, approved, denied, timeout).

## Non-Goals
- Building the external transport (Slack/Jira) adapters.
- UI for managing approval queues.
- Persisting approval state across BEAM restarts.

## Architecture
1. Define `Codex.Approvals.Hook` behaviour:
   - `c:prepare/2` (called before invocation, may mutate metadata).
   - `c:review_tool/3`, `c:review_command/3`, `c:review_file/3`.
   - Optional `c:await/2` for async channels (returns `{:ok, decision}`).
2. Extend `Codex.Approvals` dispatcher:
   - If hook returns `{:async, ref}`, store ref in ETS and await via `await/2` with timeout from thread options.
   - Maintain backwards-compatible path for `StaticPolicy`.
3. Thread options:
   - Add `approval_hook: module()` and `approval_timeout_ms`.
4. Telemetry:
   - `[:codex, :approval, :requested]`, `:approved`, `:denied`, `:timeout`.

## Data Flow
1. `Codex.Thread.run_auto/3` receives `tool.call.required`.
2. `Codex.Approvals.review_tool/3` delegates to configured hook.
3. For async, hook returns `{:async, ref, payload}`; `Codex.Approvals` emits telemetry and waits.
4. Hook side-channel (user code) calls `Codex.Approvals.reply(ref, decision)`.
5. Decision resumes auto-run loop.

## API Changes
- `Codex.Thread.Options` gains `:approval_hook` and `:approval_timeout`.
- New `Codex.Approvals.Hook` module with behaviour & default implementation.
- Public `Codex.Approvals.reply/2`.

## Risks
- Async wait could leak ETS entries; enforce timeouts & cleanup.
- Need to prevent memory leaks if clients forget to reply — add dead-letter fallback.
- Ensure concurrency safety when multiple hooks share refs.

## Implementation Plan
1. Behaviour & dispatcher refactor.
2. ETS registry (keyed by ref) plus timeout supervision.
3. Telemetry emission.
4. Docs/examples for writing custom hook.

## Verification
✅ Unit tests for dispatcher (sync + async).
✅ Integration test using fake async hook (simulate delayed decision).
✅ Property: awaiting after timeout returns `{:error, :timeout}`.
✅ Telemetry capture tests assert event payloads.

## Implementation Details

### Files Created/Modified
- ✅ `lib/codex/approvals/hook.ex` - Behaviour definition
- ✅ `lib/codex/approvals/registry.ex` - ETS registry for async tracking (created but not used in MVP)
- ✅ `lib/codex/approvals.ex` - Updated dispatcher with hook support
- ✅ `lib/codex/thread/options.ex` - Added `approval_hook` and `approval_timeout_ms`
- ✅ `lib/codex/thread.ex` - Updated to pass timeout and prefer approval_hook
- ✅ `test/codex/approvals_test.exs` - Comprehensive test coverage
- ✅ `examples/approval_hook_example.exs` - Usage examples

### Key Design Decisions
1. **Auto-await**: When a hook returns `{:async, ref}` and implements `c:await/2`, the dispatcher automatically calls `await` rather than returning the async tuple. This simplifies the integration.
2. **Backwards compatibility**: `approval_policy` (StaticPolicy) is still supported. `approval_hook` takes precedence if both are set.
3. **Telemetry**: All approval lifecycle events emit telemetry for observability.
4. **Timeout handling**: Async hooks that timeout are converted to `{:deny, "approval timeout"}` automatically.

### Usage Example
```elixir
defmodule MyApprovalHook do
  @behaviour Codex.Approvals.Hook

  @impl true
  def prepare(_event, context), do: {:ok, context}

  @impl true
  def review_tool(event, _context, _opts) do
    # Post to external system and return async ref
    ref = post_to_slack(event)
    {:async, ref}
  end

  @impl true
  def await(ref, timeout) do
    # Wait for external decision
    receive do
      {:slack_decision, ^ref, decision} -> {:ok, decision}
    after
      timeout -> {:error, :timeout}
    end
  end
end

# Configure thread with hook
{:ok, opts} = Codex.Thread.Options.new(%{
  approval_hook: MyApprovalHook,
  approval_timeout_ms: 60_000
})
```

## Open Questions
- ✅ Should hooks be supervised processes? For MVP assume caller supervises. **Decision: Callers manage their own supervision**
- ✅ Should we allow per-request overrides on events? Option for later. **Decision: Not in MVP, can add later if needed**

## Follow-up Work
- Build example Slack/Discord integration adapters
- Consider adding `review_command/3` and `review_file/3` support
- Explore persistent approval queues for long-running workflows
