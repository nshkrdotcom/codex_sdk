# Telemetry and observability considerations for the Elixir SDK

What changed upstream:
- Feedback metadata now includes source information; thread/turn events carry richer identifiers (thread_id, turn_id).
- OTEL/observability hooks were expanded (including mTLS support) and more detailed exec/compaction events are emitted.
- Token-usage updates and diff streams provide finer-grained timing/usage signals during a turn.

SDK impact:
- If forwarding telemetry, propagate the new identifiers and metadata so downstream systems can correlate events.
- Ensure OTEL exporters or logs accept the enriched exec/compaction telemetry without field loss.
- Consider exposing token-usage updates to SDK users for metering/monitoring.

Action items:
- Update telemetry schemas and tests to include new fields (source info, thread_id/turn_id).
- Verify OTEL configuration in the SDK can enable mTLS and the expanded spans/metrics.
- Add documentation/examples for consuming token-usage/diff telemetry from the SDK.
