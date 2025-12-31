# Implementation Plan - Observability, Rate Limits, and Errors

Source
- docs/20251231/codex-gap-analysis/07-observability-rate-limit-errors.md

Goals
- Wire retry and rate-limit handling into transports.
- Surface rate limit snapshots to SDK users.
- Normalize exec errors to Codex.Error.
- Add idle timeout handling for exec streams.

Scope
- Exec and app-server transports.
- Retry/rate limit utilities.
- Error normalization.

Plan
1. Add opt-in retry configuration.
   - Provide thread/transport options to enable retries and configure backoff.
   - Files: lib/codex/thread/options.ex, lib/codex/transport/app_server.ex, lib/codex/exec.ex.
2. Integrate Codex.Retry and Codex.RateLimit.
   - Wrap exec and app-server requests with retry logic and rate-limit backoff.
   - Ensure 429s and transient errors are handled safely.
   - Files: lib/codex/retry.ex, lib/codex/rate_limit.ex, lib/codex/exec.ex,
     lib/codex/transport/app_server.ex.
3. Store and expose rate limit snapshots.
   - Persist account/rateLimits/updated notifications in thread state.
   - Add a getter or callback for current rate limit info.
   - Files: lib/codex/events.ex, lib/codex/thread.ex.
4. Add exec idle timeout handling.
   - Distinguish idle timeouts from total stream duration.
   - Files: lib/codex/exec.ex.
5. Normalize exec errors.
   - Convert exec transport errors into Codex.Error with additional details.
   - Files: lib/codex/exec.ex, lib/codex/error.ex.

Tests
- Retry behavior tests for exec and app-server.
- Rate limit snapshot tests for notifications.
- Error normalization tests for exec failures.
- Idle timeout tests for streaming.

Docs
- Update README and docs/ for retry, rate-limit, and timeout configuration.

Acceptance criteria
- Retry/rate-limit handling is opt-in and documented.
- Rate limit snapshots are accessible.
- Exec errors align with Codex.Error behavior.
