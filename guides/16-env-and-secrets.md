# Environment And Secrets

The SDK treats environment access and credential handling as runtime boundaries.
Application modules under `lib/` do not read or mutate the OS environment
directly. `config/runtime.exs` takes a named allowlist into application config,
and the SDK's internal environment wrapper reads that materialized map. Callers
can supply explicit env or `process_env` maps when a bounded operation needs
additional values.

## Execution boundaries

- Governed execution requires an explicit authority reference and a
  materialized child environment. Ambient shell state does not satisfy that
  authority.
- Subprocess launchers preserve their clear-environment behavior. They receive
  only the SDK's allowlisted runtime map plus explicit per-call overrides.
- A new ambient variable must be added deliberately to the runtime allowlist.
  Arbitrary deployment credentials should instead be passed through the
  top-level application's configuration or an explicit call option.
- Live Codex commands use `~/scripts/with_bash_secrets` and must never print a
  key or token.

## Secret-bearing structs

Any struct that can hold a key, token, OAuth verifier or authorization header
uses `@derive {Inspect, except: [...]}` (or a custom `Inspect` implementation).
This protects common implicit inspection paths such as OTP crash reports,
logger metadata and error tuples. Redaction changes only inspection; the fields
remain available to the runtime code that owns the credential.

Log credential names or the keys of a validated env map, never credential
values or an entire unreviewed map. Persisted auth files are written atomically
with restrictive permissions. Tests use synthetic marker values and keep live
authentication paths behind live-only tags.

## Repository policy

Real `.env` files and files ending in `.env` are ignored. A checked-in template
must end in `.env.example`. The package must not contain developer auth files,
captured keys or token-bearing logs.

Two executable guards backstop review:

- `scripts/atom_guard.sh` rejects dynamic atom creation from wire data.
- `scripts/secrets_guard.sh` rejects whole-environment runtime snapshots and
  secret-named struct fields without Inspect redaction. A reviewed false
  positive may use `# secret-safe:` on the matching line or immediately above
  it.

Both guards run in `mix ci`; the full release gate also runs them directly.
