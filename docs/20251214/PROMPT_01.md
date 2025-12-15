You are a senior Elixir engineer agent working in `/home/home/p/g/n/codex_sdk`.

Mission: implement the multi-transport refactor so codex_sdk achieves full parity with upstream codex external
surfaces by supporting both:

1. exec JSONL (codex exec --experimental-json) — keep as default and 100% backwards compatible
2. app-server JSON-RPC over stdio (codex app-server) — add as a new stateful, bidirectional transport

You must work strictly TDD-first: for each behavior, write failing tests (unit/contract/integration as
appropriate), then implement, then refactor. Keep the codebase warning-free and dialyzer-clean.

Hard constraints / repo rules:

- Follow repo guidelines in AGENTS.md (root). Treat codex/ as vendored third-party; do not modify it.
- Do not touch doc/ (Mix-generated HTML docs output).
- Keep style idiomatic Elixir; run mix format.
- CI gates must be clean: mix test, MIX_ENV=test mix credo --strict, mix compile (no warnings), MIX_ENV=dev
  mix dialyzer (no warnings).
- Network is allowed, but tests must remain deterministic; keep real-CLI tests opt-in like existing test/
  live/*.

Critical context you must internalize (read before coding):

1. Current transport behavior (exec-only today)
    - Codex.Exec spawns the external codex executable using erlexec and reads JSONL events: lib/codex/exec.ex
    - Codex.Thread is currently hard-wired to exec (Codex.Exec.run/2 / run_stream/2): lib/codex/thread.ex:107,
      lib/codex/thread.ex:188
    - The SDK does not vendor codex; it resolves via CODEX_PATH or PATH: lib/codex/options.ex:58-86 (also
      described in README.md)
2. The authoritative app-server protocol (read only; do not edit codex/)
    - Message shapes + error schema: codex/codex-rs/app-server-protocol/src/jsonrpc_lite.rs:21-71
    - Method/notification/request registry: codex/codex-rs/app-server-protocol/src/protocol/common.rs:96-
      299 (client requests), :465-494 (server requests), :521-559 (server notifications), :561-563 (client
      notifications)
    - v2 types: codex/codex-rs/app-server-protocol/src/protocol/v2.rs
        - ApprovalDecision: codex/codex-rs/app-server-protocol/src/protocol/v2.rs:405-414
        - ExecPolicyAmendment (transparent array): codex/codex-rs/app-server-protocol/src/protocol/v2.rs:481-
          486
        - Approval request/response structs: codex/codex-rs/app-server-protocol/src/protocol/v2.rs:1714-1749
        - TurnDiffUpdatedNotification.diff is a String unified diff: codex/codex-rs/app-server-protocol/src/
          protocol/v2.rs:1524-1530
        - UserInput union (no Skill): codex/codex-rs/app-server-protocol/src/protocol/v2.rs:1289-1293
    - App-server documentation is useful but not always correct; e.g. acceptSettings is mentioned but not in
      v2 structs:
        - README mentions acceptSettings: codex/codex-rs/app-server/README.md:340
        - v2 responses only define decision: codex/codex-rs/app-server-protocol/src/protocol/v2.rs:1727-1729
3. Project planning docs for this sprint (these are your “spec”)
    Read all of these and implement exactly what they specify (update them only if you find mismatches with
    reality, with file:line evidence):
    - docs/20251214/multi_transport_refactor/README.md
    - docs/20251214/multi_transport_refactor/09_requirements_and_nongoals.md
    - docs/20251214/multi_transport_refactor/10_protocol_mapping_spec.md
    - docs/20251214/multi_transport_refactor/11_failure_modes_and_recovery.md
    - docs/20251214/multi_transport_refactor/12_public_api_proposal.md
    - docs/20251214/multi_transport_refactor/07_phased_implementation_plan.md
    - Skills delta context (do not reimplement SkillsManager in Elixir; use skills/list): docs/20251214/
      technical_plan/porting-plan.md
4. Existing test patterns you must follow
    - Deterministic “integration” tests use fixture scripts (mock codex executables) rather than real CLI:
        - test/support/fixture_scripts.ex (creates mock_codex_* scripts)
        - Example: test/integration/turn_resumption_test.exs
    - Real CLI tests are opt-in under CODEX_TEST_LIVE:
        - test/live/codex_live_cli_test.exs

What “full implementation” means (deliverables):
A) Transport abstraction (backwards compatible)

- Add a transport behavior (per docs) and refactor Codex.Thread to be transport-agnostic while preserving the
  existing exec default.
- Implement Codex.Transport.ExecJsonl as a thin wrapper around the current Codex.Exec.
- Thread structs must carry transport metadata (without breaking existing APIs).

B) App-server transport (stateful)

- Implement a supervised connection process that spawns codex app-server and speaks newline-delimited JSON
  messages over stdio.
- Implement the initialize/initialized handshake exactly as upstream requires (no "jsonrpc":"2.0" field; see
  jsonrpc_lite.rs + app-server README).
- Robust line buffering, partial line handling, interleaving, stderr handling per docs.
- Correlate responses by request id (which can be integer OR string): codex/codex-rs/app-server-protocol/src/
  jsonrpc_lite.rs:11-17.

C) App-server API surface (v2 methods)
Implement Elixir APIs for all v2 client request methods (see docs/20251214/
multi_transport_refactor/09_requirements_and_nongoals.md:23-44), at minimum:

- thread/start, thread/resume, thread/list, thread/archive, thread/compact
- turn/start, turn/interrupt
- skills/list
- model/list
- config/read, config/value/write, config/batchWrite
- review/start
- command/exec
- account/* and mcp* endpoints as in the doc set (implement; don’t handwave)

D) Events + item mapping strategy (forward compatible)

- Must surface app-server notifications losslessly (raw {method, params}) and must not crash on unknown
  methods/items.
- For core/P0/P1 notifications, map into typed %Codex.Events.*{} so existing patterns work.
- Ensure turn/diff/updated produces diff as a unified diff string; update Codex.Events.TurnDiffUpdated
  accordingly (currently diff: %{} in lib/codex/events.ex:97-109).

E) Approvals (server->client requests)

- Handle server requests:
    - item/commandExecution/requestApproval
    - item/fileChange/requestApproval
- Provide both:
    1. headless auto-approval using Codex.Approvals.Hook (extend hook return shapes backwards-compatibly)
    2. manual UI approval path via subscription + Codex.AppServer.respond/3 (as designed in docs/20251214/
        multi_transport_refactor/12_public_api_proposal.md)
- Implement full ApprovalDecision surface for command approvals:
    - "accept"
    - "acceptForSession"
    - "decline"
    - "cancel"
    - {"acceptWithExecpolicyAmendment":{"execpolicyAmendment":["cmd","arg"]}}
      Evidence and wire examples are in docs/20251214/
      multi_transport_refactor/10_protocol_mapping_spec.md:210-246.
- Do NOT implement or rely on acceptSettings (README mismatch).

F) Skills

- Implement skills/list via app-server (request/response), and port the response types (SkillScope,
  SkillMetadata, SkillErrorInfo, etc.).
- Do NOT reimplement Rust SkillsManager/loader semantics in Elixir.
- Explicitly document that UserInput::Skill cannot be sent over app-server v2 today (optional emulation mode
  is allowed but must be clearly labeled as emulation).

G) Tests (strict TDD)
You must add/extend tests so the implementation is locked down. At minimum:

1. Unit tests:
    - JSON line buffering (partial lines, multiple messages in one chunk)
    - Message classification (request/notification/response/error)
    - Request correlation by id + timeouts + cleanup
    - Unknown notification/item passthrough behavior (no crashes)
    - Approval decision encoding (including acceptForSession + acceptWithExecpolicyAmendment)
2. Integration tests (deterministic, no network):
    - Extend test/support/fixture_scripts.ex (or add a new fixture helper) to generate a mock app-server
      script that reads JSON lines and emits correct responses/notifications.
    - Use that script via Codex.Options.codex_path_override so tests can spawn codex app-server
      deterministically without requiring a real codex install.
3. Live tests (optional):
    - If you add real-CLI app-server tests, keep them opt-in like test/live/codex_live_cli_test.exs and skip
      unless explicitly enabled.

H) Documentation + versioning (required)
After implementation is complete and tests are green, update docs and release metadata:

1. Version bump (minor bump): current is 0.2.5 (mix.exs:4, VERSION).
    - Bump to 0.3.0 (“x.y++.0”).
    - Update:
        - mix.exs @version and any derived refs (mix.exs:4, mix.exs:107)
        - README.md dependency snippet (currently {:codex_sdk, "~> 0.2.5"} in README.md)
        - VERSION file
2. Changelog:
    - Add a new entry at top: ## [0.3.0] - 2025-12-14 in CHANGELOG.md
    - Summarize the multi-transport refactor, new app-server transport/API surface, approvals decision
      support, diff handling, and any notable changes; include migration/backwards-compat notes.
3. README + guides:
    - Update README.md to include app-server transport usage and the new capabilities (threads list/archive/
      compact, skills/list, config/model APIs, interrupt, approvals).
    - Search and update any relevant guides under docs/ (anything describing current limitations) so docs
      match the new code. Don’t touch doc/.

Commands you must run and keep clean before finishing:

- mix deps.get
- mix format
- mix compile (no warnings)
- mix test
- MIX_ENV=test mix credo --strict
- MIX_ENV=dev mix dialyzer (no warnings; do not “solve” by adding ignores unless absolutely required and
  justified)

Work style requirements:

- Maintain a clear step plan and checkpoints; keep commits out (do not git commit unless explicitly asked).
- Prefer small PR-sized steps: transport abstraction first, then app-server connection core, then mapping,
  then approvals, then full API surface, then docs/version/changelog.
- When facts are uncertain, verify them by citing upstream file + line numbers (from the vendored codex/ tree)
  or existing Elixir source.

Definition of Done (must all be true):

- Default behavior (exec JSONL) is unchanged and existing tests still pass.
- App-server transport is fully implemented and exposes all v2 client request methods and handles all v2
  server notifications/requests (typed where implemented + raw passthrough for the rest).
- Approvals support full ApprovalDecision surface for command approvals; file-change approval behavior is
  correct.
- turn/diff/updated.diff is handled as a unified diff string.
- Docs are updated; version bumped to 0.3.0; changelog entry added for 2025-12-14.
- mix test, mix credo --strict, and mix dialyzer are all clean.

Now start by reading the required files above, then implement via strict TDD.
