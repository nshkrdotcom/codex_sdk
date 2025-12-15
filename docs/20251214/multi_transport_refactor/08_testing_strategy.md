# Testing Strategy for App-Server Parity

## Goals

- Catch protocol regressions when upstream app-server schema changes.
- Ensure the transport abstraction does not regress existing exec-based behavior.
- Validate end-to-end streaming and approvals flows against a real `codex app-server` process.

## 1) Unit tests (fast, deterministic)

Add unit tests for:

- JSON line decoding + buffering (partial line handling)
- JSON-RPC routing:
  - response correlation by `id`
  - handling interleaved notifications while requests are in-flight
  - server requests that require responses (approvals)
- Normalization:
  - app-server notification → canonical `%Codex.Events{}` mapping
  - app-server thread item → `%Codex.Items{}` mapping
  - `turn/diff/updated` diff is a **string** (unified diff) (`codex/codex-rs/app-server-protocol/src/protocol/v2.rs:1524-1530`)
  - unknown methods/items are preserved as raw (no crashes)

These tests should not spawn the real codex process; feed recorded JSON lines into the parser.

## 2) Contract fixtures (golden transcripts)

Record “golden” transcripts produced by upstream:

- `initialize` + `initialized`
- `thread/start` + `turn/start`
- a short turn that produces:
  - `item/agentMessage/delta`
  - `item/completed`
  - `turn/completed`

Store as newline-delimited JSON files and replay them through the Elixir decoder + mapper.

This isolates “our decoding” from “upstream behavior” and makes failures actionable.

## 3) Integration tests (spawn real `codex app-server`)

Write a small set of `@tag :integration` tests that:

1. Spawn a real `codex app-server` process
2. Perform the handshake
3. Start a thread + run a trivial turn
4. Assert a minimal set of notifications are observed

Also add one integration test that triggers approval requests, if we can configure codex to request them deterministically.

When feasible, also cover:
- `AcceptForSession` and `AcceptWithExecpolicyAmendment` wire encoding + server acceptance (command approvals)

## 4) Schema drift detection

Upstream can generate version-matched schemas:

- `codex app-server generate-ts --out DIR`
- `codex app-server generate-json-schema --out DIR`
  (see `codex/codex-rs/app-server/README.md:21`)

For long-term maintainability, consider adding a CI job that:

- regenerates schemas for the vendored upstream version,
- compares them to committed snapshots (or uses them to generate Elixir decoders),
- flags breaking drift early.

## 5) Keep exec tests intact

Do not weaken the existing exec contract tests; the transport abstraction should be invisible for the default exec backend.
