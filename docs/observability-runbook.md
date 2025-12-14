# Observability Runbook

Guidance for enabling and validating the Codex SDK telemetry pipeline in production and local environments. OTLP exporting is **disabled by default**; enable it explicitly when you have a collector configured.

Note: This runbook covers **Elixir-side** telemetry (`Codex.Telemetry`). The Codex CLI (`codex-rs`) can also export its own OpenTelemetry log events via `$CODEX_HOME/config.toml` `[otel]` (see `codex/docs/config.md`), which is independent of the SDK exporter.

## Telemetry Payloads
- Thread, tool, and approval events now emit `duration_ms` alongside the original `duration` field.
- All SDK-originated events include `originator: :sdk` plus `span_token` metadata used for span correlation.
- Stop/exception events add `system_time` to support precise span end timestamps.
- Default logs can be enabled with `Codex.Telemetry.attach_default_logger/1`; they report durations in milliseconds.
- Thread telemetry now carries `thread_id`, `turn_id`, and any `source` metadata found on the thread, and it emits incremental signals for token-usage updates, diff streams, and compaction stages (`[:codex, :thread, :token_usage, :updated]`, `[:codex, :turn, :diff, :updated]`, `[:codex, :turn, :compaction, stage]`).

## Enabling OTLP Export
1. Enable OTLP exporting and export the collector endpoint (and optional headers):
   ```bash
   export CODEX_OTLP_ENABLE=1
   export CODEX_OTLP_ENDPOINT="https://otel.example.com:4318"
   export CODEX_OTLP_HEADERS="authorization=Bearer abc123,tenant-id=codex-sdk"
   ```
2. Boot the SDK (or your host application) so it invokes `Codex.Telemetry.configure/1`. The helper restarts the OTEL apps with a simple span processor.
3. Verify the apps started cleanly:
   ```bash
   iex -S mix
   iex> Application.started_applications() |> Enum.filter(&(elem(&1, 0) in [:opentelemetry, :opentelemetry_exporter]))
   ```
4. Emit a thread run and confirm spans arrive in your collector.

### mTLS
- Provide client certificates for the OTLP exporter with:
  ```bash
  export CODEX_OTLP_CERTFILE=/path/to/client.crt
  export CODEX_OTLP_KEYFILE=/path/to/client.key
  export CODEX_OTLP_CACERTFILE=/path/to/ca.crt
  ```
- The exporter passes these through as `ssl_options`; leave them unset to fall back to the default root store.

## Local Verification with the PID Exporter
Use the in-memory exporter to validate spans without a collector:
```elixir
iex -S mix
iex> {:ok, codex_opts} = Codex.Options.new(%{api_key: "test", codex_path_override: Codex.TestSupport.FixtureScripts.cat_fixture!("thread_basic.jsonl")})
iex> {:ok, thread_opts} = Codex.Thread.Options.new(%{})
iex> {:ok, thread} = Codex.start_thread(codex_opts, thread_opts)
iex> Codex.Telemetry.configure(env: %{"CODEX_OTLP_ENDPOINT" => "pid://local"}, exporter: {:otel_exporter_pid, self()})
:ok
iex> Codex.Thread.run(thread, "trace check")
iex> flush()
{:span, _span_record}
```
`{:span, span_record}` messages include the exported OpenTelemetry span (`otel_span` record).

## Tailing Telemetry & Logs
- Attach the default logger: `Codex.Telemetry.attach_default_logger(level: :debug)`.
- Use the PID exporter above to introspect span attributes quickly.
- For noisy environments, attach custom handlers with `:telemetry.attach_many/4`.

## Cleaning Execution State
- Clear staged attachments: `Codex.Files.force_cleanup()` or `rm -rf $(Codex.Files.staging_dir())`.
- Restart the OTEL stack if configuration drifts: re-run `Codex.Telemetry.configure/1` after adjusting environment variables.
- If an `erlexec` worker gets wedged, call `:exec.stop(pid)` (visible in telemetry metadata) or restart the host BEAM node; `Codex.Thread.run/3` always tears down processes on completion.
