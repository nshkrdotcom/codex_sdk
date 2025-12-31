# Observability, Rate Limits, and Error Handling Gaps

Agent: reliability

Upstream references
- `codex/docs/config.md`
- `codex/codex-rs/protocol/src/protocol.rs`
- `codex/codex-rs/app-server-protocol/src/protocol/v2.rs`

Elixir references
- `lib/codex/exec.ex`
- `lib/codex/transport/app_server.ex`
- `lib/codex/retry.ex`
- `lib/codex/rate_limit.ex`
- `lib/codex/events.ex`

Gaps and deviations
- Gap: Codex.Retry and Codex.RateLimit utilities are not wired into exec/app-server transports. Transient errors and 429s are not retried automatically. Add optional retry layers around exec and app-server requests. Refs: `lib/codex/exec.ex`, `lib/codex/transport/app_server.ex`, `lib/codex/retry.ex`, `lib/codex/rate_limit.ex`.
- Gap: provider-level stream retry and idle timeout settings (`request_max_retries`, `stream_max_retries`, `stream_idle_timeout_ms`) are not exposed as SDK options. Add typed options or config override helpers. Refs: `codex/docs/config.md`, `lib/codex/thread/options.ex`.
- Gap: `account/rateLimits/updated` notifications are parsed but not stored or exposed in thread state; there is no helper to read current rate limit snapshot. Add storage on thread or a callback hook. Refs: `lib/codex/events.ex`, `lib/codex/thread.ex`.
- Gap: exec stream timeout is a single overall timeout (default 1h) and does not distinguish idle vs total duration. Upstream defaults to a 5m stream idle timeout per provider. Add separate idle timeout handling for exec streams if feasible. Refs: `lib/codex/exec.ex`, `codex/docs/config.md`.
- Deviation: Codex.Events parses error structures with additional_details and codex_error_info, but Exec transport errors only return TransportError. Consider normalizing exec errors into Codex.Error for parity with app-server notifications. Refs: `lib/codex/events.ex`, `lib/codex/exec.ex`, `lib/codex/error.ex`.

Implementation notes
- Make retry and rate-limit handling opt-in via thread/turn opts to avoid changing default behavior.
- If adding idle timeouts, ensure they do not conflict with long-running turns (e.g., large repos).
