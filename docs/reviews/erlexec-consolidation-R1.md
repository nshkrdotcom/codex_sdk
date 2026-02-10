# Erlexec Consolidation R1 Review (codex_sdk)

## Pass 1: Structural Correctness

- **5. Buffer module exists; duplicate helpers removed**: **PASS**
  - `rg -n "defp split_lines" lib/codex/` -> zero hits.
  - `rg -n "defp decode_line\\b" lib/codex/` -> zero hits.
- **6. `Codex.IO.Transport` has all 10 callbacks**: **PASS**
  - Verified 10 `@callback` entries in `lib/codex/io/transport.ex:34`.
- **7. `Transport.Erlexec` implements behaviour**: **PASS**
  - `@behaviour Codex.IO.Transport` at `lib/codex/io/transport/erlexec.ex:8`.
- **8. Subprocess modules deleted**: **PASS**
  - `rg -n "Codex\.AppServer\.Subprocess" lib/ test/` -> zero hits.
- **9. No direct `:exec` calls outside `IO.Transport.Erlexec`**: **FAIL**
  - Residual direct usage remains:
    - `lib/codex/sessions.ex:433`
    - `lib/codex/sessions.ex:435`
    - `lib/codex/sessions.ex:436`
    - `lib/codex/sessions.ex:470`
    - `lib/codex/tools/shell_tool.ex:244`
    - `lib/codex/tools/shell_tool.ex:334`

## Pass 2: Runtime Correctness (Erlexec)

- **Result**: **PASS** for requested 10 points on `lib/codex/io/transport/erlexec.ex`.
- Evidence:
  - `safe_call/3` async call + timeout: `lib/codex/io/transport/erlexec.ex:320`.
  - Async send/end_input with `pending_calls`: `lib/codex/io/transport/erlexec.ex:166`, `lib/codex/io/transport/erlexec.ex:184`, `lib/codex/io/transport/erlexec.ex:171`, `lib/codex/io/transport/erlexec.ex:189`.
  - `terminate/2` timer cancel + demonitor + force stop: `lib/codex/io/transport/erlexec.ex:306`.
  - `force_close/1` and stop+kill subprocess: `lib/codex/io/transport/erlexec.ex:95`, `lib/codex/io/transport/erlexec.ex:202`, `lib/codex/io/transport/erlexec.ex:717`.
  - Dual legacy/tagged dispatch: `lib/codex/io/transport/erlexec.ex:551`.
  - Queue batching and scheduled drain: `lib/codex/io/transport/erlexec.ex:24`, `lib/codex/io/transport/erlexec.ex:16`, `lib/codex/io/transport/erlexec.ex:283`.
  - Finalize delay + re-entrant drain: `lib/codex/io/transport/erlexec.ex:15`, `lib/codex/io/transport/erlexec.ex:244`, `lib/codex/io/transport/erlexec.ex:266`.
  - Headless timeout + last-subscriber stop: `lib/codex/io/transport/erlexec.ex:293`, `lib/codex/io/transport/erlexec.ex:449`.

## Pass 3: Source Parity vs amp_sdk Section 21

- **Result**: **FAIL**
- Matched items:
  - Transport struct shape is 15 fields and generally aligns with amp checklist (`lib/codex/io/transport/erlexec.ex:18`).
  - Transport API and lifecycle mechanics are close to amp.
- Gaps:
  - Consolidation objective not completed repo-wide because direct `:exec` paths remain outside shared transport (see Pass 1 failures).
  - Cleanup cascade parity (force_close -> await down -> shutdown -> kill) is not implemented in `Codex.Exec`; it only force-closes in `safe_stop/1` with no monitor/escalation loop:
    - `lib/codex/exec.ex:264`
  - `safe_call` task-start path is local (`async_nolink`) rather than amp TaskSupport-style utility module:
    - `lib/codex/io/transport/erlexec.ex:346`

## Pass 4: Documentation Coherence

- **Result**: **FAIL**
- Findings:
  - Some docs still describe subprocess-centric execution patterns without reflecting the new shared `Codex.IO.Transport` consolidation:
    - `docs/20251230/prompts/03-shell-hosted-tool.md:21`
    - `docs/20251213/port_gap_analysis/FEATURE_INVENTORY.md:515`
- Module docs for new transport primitives are present and consistent:
  - `lib/codex/io/buffer.ex:1`
  - `lib/codex/io/transport.ex:1`

## Pass 5: Test Suite + Quality Gates

- **Result**: **FAIL (blocked in environment)**
- Commands attempted:
  - `mix compile --warnings-as-errors`
  - `mix test`
  - `mix credo --strict`
  - `mix dialyzer`
- All failed before project execution with the same environment error:
  - `failed to open a TCP socket in Mix.Sync.PubSub.subscribe/1, reason: :eperm`

## Critical Issues Requiring Rework

1. **Consolidation incomplete: direct `:exec` usage remains outside shared transport**
   - `lib/codex/sessions.ex:433`
   - `lib/codex/sessions.ex:435`
   - `lib/codex/sessions.ex:436`
   - `lib/codex/sessions.ex:470`
   - `lib/codex/tools/shell_tool.ex:244`
   - `lib/codex/tools/shell_tool.ex:334`
2. **Consumer-side shutdown cascade parity missing in `Codex.Exec` cleanup path**
   - `lib/codex/exec.ex:264`

## Non-Critical Observations

- `Codex.IO.Transport.Erlexec` itself is structurally strong and closely tracks amp runtime semantics.
- App-server and MCP stdio consumers are now using tagged transport events correctly.

## Overall Verdict

**REWORK REQUIRED**
