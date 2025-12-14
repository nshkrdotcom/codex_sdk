# Elixir SDK gap matrix (post-pull)

Status legend:

- ✅ done
- 🟡 partial / transport-blocked
- ❌ missing
- 🚫 not applicable on exec JSONL

## High-signal gaps discovered by validating against the real CLI

Running `codex exec --help` on a real installation shows:

- Exec supports `--image` (images only), **not** `--attachment`.
- Exec supports `--json` (alias `--experimental-json`).
- There are **no** exec flags for `--tool-output` / `--tool-failure`.

If the Elixir SDK passes flags that the CLI does not accept, “live” runs will fail even though
fixture-driven tests may pass (fixture scripts don’t validate arguments).

These mismatches were fixed in SDK `0.2.2` by switching image attachments to `--image` and by
stopping emission of undocumented `--tool-output/--tool-failure` flags.

## Feature matrix

| Feature / change | Upstream source | Transport | Elixir status | Notes / next steps |
|---|---|---:|---:|---|
| `auto_previous_response_id` option | agents-python `a9d95b4` | exec JSONL | ✅ | Implemented + tests. Exec JSONL does not emit `response_id`, so behavior is currently dormant on live CLI. |
| Usage token detail normalization | agents-python `509ddda` | API (Responses/Chat) | 🚫 | Elixir usage is currently a simple `map()` from exec JSONL. Consider optional helpers for normalization/aggregation only when SDK is the one computing totals. |
| Chat-completions logprobs preservation | agents-python `df020d1` | API | 🚫 | Not exposed by `codex exec`. |
| Apply-patch context threading | agents-python `9f96338` | tool runtime | 🟡 | Elixir hosted tool callbacks receive a `context` map; audit and document its guarantees for `apply_patch`. |
| `codex exec` JSONL event schema | codex-rs `exec_events.rs` | exec JSONL | ✅ | Decoder is permissive and handles minimal schema. |
| Fixtures reflect real exec schema | internal | exec JSONL | ❌ | Existing fixtures include richer/other-transport fields. Plan: add fixtures matching `exec_events.rs` and keep backwards-compat parsing tests. |
| Exec argument parity (`--image`, `--skip-git-repo-check`, etc) | codex-rs `exec/src/cli.rs` | exec JSONL | 🟡 | SDK now uses `--image` for attachments and does not emit undocumented tool-output flags; remaining work is exposing `--skip-git-repo-check`, `--cd`, `--add-dir`, `--sandbox`, etc as validated SDK options. |
| Non-git usage (`--skip-git-repo-check`) | codex-rs exec | exec JSONL | ❌ | Add a run-scoped knob mapping to this flag. |
| Workspace selection (`--cd`, `--add-dir`) | codex-rs exec | exec JSONL | ❌ | Add run/thread options and document safety implications. |
| Exec `review` workflow (`codex exec review …`) | codex-rs exec | exec JSONL | ❌ | Optional: expose as `Codex.Review.*` module or explicit function on `Codex`. |
| codex-rs `[otel]` export docs | codex-rs `ad7b9d63c` | config.toml | ✅ | Docs now distinguish Elixir OTLP vs codex-rs OTEL. |
| Isolated `CODEX_HOME` per run | codex-rs `[otel]` + config loader | exec JSONL | ❌ | Optional but useful: allow SDK to run with generated config dir (no mutation of user home). |
| App-server config service/models manager/skills | codex-rs | protocol/app-server | 🚫 | Not reachable via exec JSONL; would require a new transport implementation. |
