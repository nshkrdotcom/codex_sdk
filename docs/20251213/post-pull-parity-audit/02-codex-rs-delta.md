# codex delta (`6eeaf46ac..a2c86e5d8`)

The upstream `codex` pull is extremely large (~1189 files changed). For the Elixir SDK, the only
meaningful slice is what affects:

1. The **`codex exec --experimental-json`** JSONL transport (event schema + semantics), and
2. The **CLI flags/config** we can pass when spawning `codex`.

Everything else (TUI2, sandbox internals, protocol/app-server features) is “upstream churn” unless
we adopt those transports.

## Exec JSONL schema (source of truth)

The schema for events emitted by `codex exec --experimental-json` is defined in:

- `codex/codex-rs/exec/src/exec_events.rs`

Highlights:

- Events:
  - `thread.started` → `%{"thread_id" => "..."}`
  - `turn.started` → `%{}`
  - `turn.completed` → `%{"usage" => %{...}}`
  - `item.started|updated|completed` → `%{"item" => %{...}}`
  - `turn.failed` / `error`
- Items:
  - `agent_message`, `reasoning`, `command_execution`, `file_change`, `mcp_tool_call`, `web_search`,
    `todo_list`, `error`
- Usage:
  - `input_tokens`, `cached_input_tokens`, `output_tokens`

**Implication for the Elixir SDK**

- The exec transport does **not** provide:
  - `response_id` (needed to exercise `auto_previous_response_id`)
  - thread/turn IDs on turn events
  - app-server events like `thread.tokenUsage.updated`, `turn.diff.updated`, etc.

Our decoder should remain tolerant of both:

- the minimal schema above (real CLI), and
- richer internal fixtures we already have (so existing deterministic tests keep value).

## CLI surface changes that matter to the SDK

The exec subcommand CLI parser lives at:

- `codex/codex-rs/exec/src/cli.rs`

Notable exec-visible functionality in this upstream range:

- Exec JSON flag is now `--json` with alias `--experimental-json`.
- `codex exec review ...` exists as a non-interactive review workflow (new `ReviewArgs` under the
  exec subcommand).

### What the Elixir SDK currently passes

The SDK builds `codex exec` args in `lib/codex/exec.ex` and currently supports:

- `--experimental-json`
- `--model <name>`
- `--output-schema <file>`
- `resume <thread_id>`
- `--continuation-token <token>`
- `--cancellation-token <token>`
- `--image <path>` for staged image attachments
- `--config ...` overrides (for reasoning effort)

### Gaps worth addressing

These are upstream-supported exec flags that the Elixir SDK does not yet expose:

- `--skip-git-repo-check` (required for running in non-git dirs)
- `--cd <dir>` / `--add-dir <dir>` (workspace selection)
- `--sandbox <mode>` / `--full-auto` / `--dangerously-bypass-approvals-and-sandbox` (policy toggles)
- `codex exec review ...` as a first-class SDK call (optional, but now reachable via exec)

Whether we expose these should follow existing SDK architecture:

- global defaults belong in `Codex.Options`
- per-run/per-thread knobs belong in `Codex.RunConfig` or `Codex.Thread.Options`

## Observability: codex-rs OTEL export vs Elixir OTLP export

Upstream added TOML-driven OTEL export (see `codex/docs/config.md`, `[otel]` section).

This is distinct from the Elixir SDK’s OTLP exporter (`CODEX_OTLP_ENABLE=1`). The SDK should keep
these layers explicitly separated:

- codex-rs OTEL: configured via `CODEX_HOME` + `config.toml`
- Elixir OTLP: configured via Elixir env/application config

**Potential SDK enhancement (optional)**

Add a small, well-tested mechanism to run `codex` with an isolated `CODEX_HOME` pointing at a
generated config directory. This enables programmatic control over codex-rs config (including
`[otel]`) without mutating the user’s real `~/.codex`.

## Transport-dependent features (not applicable today)

The following major upstream additions are real, but are **not reachable** through exec JSONL:

- layered config loader + `ConfigService` (app-server protocol)
- `ModelsManager` + caching (app-server protocol)
- skills (core/protocol)
- review mode and unified exec refactors (protocol-driven; exec has a separate review subcommand)

If we decide to adopt protocol/app-server transport, that becomes a separate initiative (new
transport module, request/response framing, new fixtures, and docs labeling which features are
available on which transport).
