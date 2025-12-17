# Upstream Pull Deep Dive (5d77d4db6..a9a7cf348)

Date: 2025-12-17  
Upstream repo: `codex/` (openai/codex)  
Old HEAD: `5d77d4db6` — “Reimplement skills loading using SkillsManager + skills/list op. (#7914)”  
New HEAD: `a9a7cf348` — “download new windows binaries when staging npm package (#8203)”  
Delta: **72 commits**, **184 files changed** (≈11k insertions / 2.3k deletions)

This doc is a deep dive on what changed upstream in `codex/` and how to port it into the Elixir SDK in this repo (`codex_sdk`). The SDK uses the system `codex` binary for execution, so most Rust/Node internals are “no-port”; the actionable items are where upstream changes the **app-server protocol**, **config surface**, and any **observable runtime behavior** the SDK depends on.

---

## Executive Summary (What Matters for the Elixir Port)

### Breaking / behavior-changing for `codex app-server` consumers

1) **Removed**: `thread/compact` (protocol + server)  
   - Upstream removed a previously stubbed API entirely; clients must rely on server-side auto-compaction.
   - Elixir impact: `Codex.AppServer.thread_compact/2` becomes incompatible with new servers.

2) **Renamed**: `mcpServers/list` → `mcpServerStatus/list` (protocol + server + docs)  
   - Elixir impact: `Codex.AppServer.Mcp.list_servers/2` currently calls the old method.

3) **Changed**: config layer metadata schema (`ConfigLayerName` → tagged union `ConfigLayerSource`)  
   - `config/read` with `includeLayers: true` returns a **different JSON shape** now.
   - Elixir impact: any code/docs/tests assuming `{name: <string>, source: <string>}` must be updated.

4) **Added (internal/experimental)**: `ThreadStartParams.experimentalRawEvents` + `rawResponseItem/completed` notification  
   - Opt-in flag on `thread/start` enables raw response item streaming.
   - Elixir impact: optional support; should at least be safely pass-through / safely ignored.

### Feature surface expansions worth porting/documenting

5) **Skills**: new feature-flag docs + new `SkillScope::Public` variant in `skills/list` response  
   - Elixir impact: update any skills docs/types that assume only `User|Repo`.

6) **Config**: new `ghost_snapshot.*` keys + stricter `approval_policy` validation + `xhigh` reasoning effort in docs  
   - Elixir impact: update SDK-side validation/documentation where we expose these knobs (or intentionally don’t).

### Runtime/tooling correctness fixes to be aware of

7) **Parallel tool calls**: upstream fixes ordering and turn-diff emission after in-flight tool tasks drain  
   - Elixir impact: review app-server streaming termination rules and any SDK tool orchestration logic that assumes all “final” signals arrive before tool side-effects land.

---

## Change Inventory by Subsystem

This is not an exhaustive per-file list (184 files), but it covers every *port-relevant* delta plus the major internal refactors that might change observable behavior.

### A) App-server protocol & server changes (port-relevant)

#### A1) `thread/compact` removed (BREAKING)

**Upstream commits**
- `412dd3795` — “chore(app-server): remove stubbed thread/compact API (#8086)”

**Upstream changes**
- Removed request definition from `codex-rs/app-server-protocol/src/protocol/common.rs`
- Removed types from `codex-rs/app-server-protocol/src/protocol/v2.rs`
- Removed handler from `codex-rs/app-server/src/codex_message_processor.rs`

**Port to Elixir**
- `lib/codex/app_server.ex`:
  - Deprecate/remove `thread_compact/2`, or change it into a compatibility shim:
    - Option A (recommended): keep the function but return `{:error, :unsupported}` with a message pointing to auto-compaction.
    - Option B: attempt `thread/compact` only when talking to older servers (requires a capability/version probe; otherwise detect “unknown method” and surface a targeted error).
- Docs needing updates:
  - `docs/09-app-server-transport.md` (currently lists `thread_compact/2` as supported)
  - `docs/20251214/multi_transport_refactor/*` (protocol inventories and matrices reference `thread/compact`)

**Validation**
- Manual: call `Codex.AppServer.thread_compact/2` against a new `codex app-server`; verify it fails with a clear, SDK-owned error.

---

#### A2) MCP list method rename: `mcpServers/list` → `mcpServerStatus/list` (BREAKING)

**Upstream commits**
- `600d01b33` — “chore: update listMcpServers to listMcpServerStatus (#8114)”
- `370279388` — “chore: update listMcpServerStatus to be non-blocking (#8151)” (behavioral; no protocol change)

**Upstream protocol changes**
- `codex-rs/app-server-protocol/src/protocol/common.rs`:
  - `McpServersList => "mcpServers/list"` removed
  - `McpServerStatusList => "mcpServerStatus/list"` added
- `codex-rs/app-server-protocol/src/protocol/v2.rs` renamed types:
  - `ListMcpServersParams` → `ListMcpServerStatusParams`
  - `McpServer` → `McpServerStatus`
  - `ListMcpServersResponse` → `ListMcpServerStatusResponse`

**Port to Elixir**
- `lib/codex/app_server/mcp.ex`:
  - Update `Connection.request/4` method string to `"mcpServerStatus/list"`.
  - Consider API compatibility:
    - Keep `list_servers/2` but return “status” entries, or
    - Add a new `list_server_statuses/2` function and keep `list_servers/2` as a deprecated alias.
  - Optional compatibility fallback:
    - Try `"mcpServerStatus/list"` first; on `-32601`/“method not found”, retry `"mcpServers/list"`.
- Docs needing updates:
  - `docs/20251214/multi_transport_refactor/10_protocol_mapping_spec.md` (has `mcpServers/list`)

**Validation**
- Live call: `Codex.AppServer.Mcp.list_servers(conn)` returns expected response shape against a new server.
- Compatibility: test against an older server (if you keep fallback).

---

#### A3) Config layers schema changed: `ConfigLayerName` → tagged union `ConfigLayerSource`

**Upstream commits**
- `de3fa03e1` — “feat: change ConfigLayerName into a disjoint union rather than a simple enum (#8095)”

**Upstream protocol changes**
- `codex-rs/app-server-protocol/src/protocol/v2.rs`:
  - `ConfigLayerName` enum replaced with:
    - `ConfigLayerSource` tagged union (`type` discriminator)
    - Variants:
      - `mdm` → `{type: "mdm", domain: String, key: String}`
      - `system` → `{type: "system", file: AbsolutePathBuf}`
      - `sessionFlags` → `{type: "sessionFlags"}`
      - `user` → `{type: "user", file: AbsolutePathBuf}`
  - `ConfigLayerMetadata.source` removed
  - `ConfigLayer.source` removed

**What the new JSON looks like**

```json
{
  "name": {"type": "system", "file": "/etc/codex/managed_config.toml"},
  "version": "sha256:<...>",
  "config": { "...": "..." }
}
```

**Port to Elixir**
- If the SDK stays “map-through” for config APIs: no code change required, but update docs/tests that describe the old shape.
- If the SDK adds typed structs for config layers (recommended long-term):
  - Add a decoder that accepts *both* shapes for compatibility:
    - Old: `%{"name" => "system", "source" => "...", "version" => "..."}`
    - New: `%{"name" => %{"type" => "system", ...}, "version" => "..."}`
- Docs to update:
  - Any place we document `config/read` response fields with layers (search for `include_layers` and “layers”).

**Validation**
- Live: `Codex.AppServer.config_read(conn, include_layers: true)` works and SDK docs match the returned shape.

---

#### A4) Raw response items (experimental/internal)

**Upstream commits**
- `70913effc` — “[app-server] add new RawResponseItem v2 event (#8152)”

**Upstream protocol changes**
- `ThreadStartParams` gains `experimental_raw_events: bool` (default false)
- New server notification:
  - method: `"rawResponseItem/completed"`
  - params: `{threadId, turnId, item: ResponseItem}`

**Port to Elixir**
- `lib/codex/app_server.ex`:
  - Consider accepting `experimental_raw_events` (snake) / `experimentalRawEvents` (camel) in `thread_start/2` and `thread_resume/3`, passing through to wire params.
- `lib/codex/transport/app_server.ex`:
  - If exposing this at thread options level, add it to `thread_start_params/1`.
- `lib/codex/app_server/notification_adapter.ex`:
  - Optional: add a typed event (e.g., `%Codex.Events.RawResponseItemCompleted{...}`) and map it.
  - Minimal: current implementation safely wraps unknown methods in `%Events.AppServerNotification{}`; ensure docs mention how to observe raw events if enabled.
- **Streaming semantics check**:
  - If raw events can arrive after `turn/completed`, our app-server stream currently halts on `%Events.TurnCompleted{}`; consider adding a “drain for N ms” option or an opt-in “include post-completion notifications” mode.

**Validation**
- Requires a server/client that sets `experimentalRawEvents: true` and triggers raw response items.

---

### B) Skills: docs + `SkillScope::Public` + discovery behavior changes

**Upstream commits**
- `7c6a47958` — “docs: document enabling experimental skills (#8024)”
- `4897efcce` — “Add public skills + improve repo skill discovery and error UX (#8098)”
- `9f28c6251` — “fix: proper skills dir cleanup (#8194)”

**Upstream changes**
- Skills are now explicitly behind `[features].skills = true` (docs change).
- `skills/list` response adds `SkillScope::Public` variant in app-server protocol.
- Discovery behavior improvements:
  - searches upward for nearest `.codex/skills` within a git repo
  - deduplicates skills by name with deterministic ordering
  - adds a public skills cache directory (implementation detail in core)

**Port to Elixir**
- **Docs**:
  - If we document skills usage via app-server, include the feature-flag prerequisite and the new `Public` scope value.
  - Update any mention that skills are always available after the `skills/list` protocol addition.
- **SDK feature plumbing (optional but useful)**:
  - Add `skills_enabled` to `Codex.Thread.Options` and plumb it:
    - exec transport: pass `--enable skills` (preferred) or `--config features.skills=true`
    - app-server transport: start subprocess with `codex --enable skills app-server` (requires extending `Codex.AppServer.Connection.build_command/1` to accept extra args)

**Validation**
- Live: `Codex.AppServer.skills_list(conn, cwds: [repo])` returns skills including `scope: "Public"` when configured.

---

### C) Config & sandbox surface changes

#### C1) Stricter `approval_policy` validation (config contract tightening)

**Upstream commits**
- `9352c6b23` — “feat: Constrain values for approval_policy (#7778)”

**Upstream changes**
- codex-rs config parsing now constrains `approval_policy` to an allowed set (internal `Constrained<T>` helper).

**Port to Elixir**
- `lib/codex/thread/options.ex` and `lib/codex/app_server/params.ex`:
  - Consider rejecting arbitrary strings for approval policy earlier (today we allow any string for forward compatibility).
  - Alternatively, keep accepting strings, but document that invalid values will hard-fail in newer `codex`.
- `lib/codex/exec.ex`:
  - Ensure `--config approval_policy="..."` only emits allowed values when using atoms.

---

#### C2) Ghost snapshot config additions + warning controls

**Upstream commits**
- `4274e6189` — “feat: config ghost commits (#7873)”
- `0d9801d44` — “feat: ghost snapshot v2 (#8055)”
- `3d92b443b` — “feat: add config to disable warnings around ghost snapshot (#8178)”

**Upstream changes**
- New documented keys in `docs/config.md`:
  - `ghost_snapshot.disable_warnings`
  - `ghost_snapshot.ignore_large_untracked_files` (bytes; default 10 MiB; `0` disables)
  - `ghost_snapshot.ignore_large_untracked_dirs` (count; default 200; `0` disables)
- Substantial implementation changes in `codex-rs/utils/git/src/ghost_commits.rs`

**Port to Elixir**
- SDK likely does not need to implement ghost snapshotting (it’s runtime-internal), but:
  - Update any SDK docs that mention ghost snapshot behavior/config.
  - If SDK provides higher-level “generate config.toml” helpers, add these fields.

---

#### C3) Sandbox: `.codex/` treated like `.git/` as read-only subpath under writable roots

**Upstream commits**
- `bef36f4ae` — “feat: if .codex is a sub-folder of a writable root, then make it read-only to the sandbox (#8088)”

**Upstream changes**
- Under Seatbelt (macOS; planned elsewhere), writable roots now mark `.codex/` read-only in addition to `.git/`.
- Documented in upstream `docs/config.md`.

**Port to Elixir**
- Docs:
  - Update sandbox docs to mention `.codex/` is read-only under workspace-write and may trigger approvals for writes.
- Testing considerations:
  - Any tests relying on writes to `.codex/` inside a workspace-write sandbox may start failing when run via the real `codex` binary.

---

#### C4) ConfigToml path semantics: `experimental_*_file` becomes `AbsolutePathBuf`

**Upstream commits**
- `1e9babe17` — “fix: PathBuf -> AbsolutePathBuf in ConfigToml struct (#8205)”

**Upstream changes**
- `experimental_instructions_file` and `experimental_compact_prompt_file` are now resolved relative to the parent folder of `config.toml` (not `cwd`), and stored as absolute paths.
- Upstream example config changed `experimental_compact_prompt_file = "./compact_prompt.txt"`.

**Port to Elixir**
- Only relevant if the SDK parses/generates these config keys itself (most users won’t).
- If adding config helpers, mirror upstream path resolution:
  - resolve relative paths against `CODEX_HOME/config.toml`’s directory.

---

### D) Tooling/runtime notes (possible SDK impact)

#### D1) Parallel tool calls fixes (ordering + diff emission after draining in-flight tool tasks)

**Upstream commits**
- `d802b1871` — “fix parallel tool calls (#7956)”

**Upstream changes (high-level)**
- Tool-call tasks can execute concurrently; upstream now ensures:
  - in-flight tool futures are drained before emitting turn diffs
  - turn-diff emission timing aligns with tool side-effects

**Port to Elixir (review items)**
- `lib/codex/transport/app_server.ex`:
  - Confirm we don’t miss `turn/diff/updated` if it can arrive late relative to `turn/completed`.
  - Consider configurable drain behavior after `TurnCompleted`.
- `lib/codex/thread.ex` + `lib/codex/agent_runner.ex`:
  - If we want parity with upstream “parallel tool calls”, consider executing multiple tool calls concurrently when the model requests multiple in the same turn.
  - Ensure emitted streaming events (`Codex.StreamEvent.*`) remain deterministic (or document nondeterminism).

---

#### D2) `apply-patch` crate refactor + new fixture scenarios (mostly internal)

**Upstream commits**
- `e290d4826` — “chore(apply-patch) move invocation parsing (#8110)”
- `a3b137d09` — “chore(apply-patch) move invocation tests (#8111)”
- `ae3793eb5` — “chore(apply-patch) unicode scenario (#8141)”

**Upstream changes**
- Major refactor: invocation parsing moved into `codex-rs/apply-patch/src/invocation.rs`.
- Test fixtures expanded, including unicode scenario and several rejection cases (empty patch, missing file delete, etc).

**Port to Elixir**
- Only actionable if we implement a built-in `apply_patch` editor in Elixir (today we delegate via callback in `Codex.Tools.ApplyPatchTool`):
  - Mirror the upstream acceptance/rejection behavior from fixtures for compatibility.
  - Add property tests around unicode and empty-hunk edge cases.

---

### E) Packaging/CI (no SDK port required)

Representative upstream commits:
- Windows sandbox binaries and packaging: `3a0d9bca6`, `a9a7cf348`
- macOS code-sign action refactor: `b27c702e8`
- GitHub Actions updates for Node 24 compatibility: `5ceeaa96b`

These are vendoring/CI concerns inside `codex/` and do not change the Elixir SDK’s runtime contract.

---

## Concrete Porting Checklist (Recommended Order)

### P0 (breakages)
- Update MCP method call to `"mcpServerStatus/list"` with optional fallback to `"mcpServers/list"`.
- Remove/deprecate `Codex.AppServer.thread_compact/2` and update docs that advertise it.

### P1 (protocol/data-shape updates)
- Update config/read docs/decoders for `ConfigLayerSource` tagged union.
- Update skills docs/types for `SkillScope::Public`.
- Decide whether to plumb `experimentalRawEvents` + surface `rawResponseItem/completed`.

### P2 (docs alignment)
- Mirror upstream docs deltas that affect SDK users:
  - skills feature flag (`[features].skills = true`)
  - sandbox note about `.codex/` being read-only under writable roots
  - `xhigh` reasoning effort mention (SDK already supports it)

### P3 (behavioral parity / robustness)
- Re-evaluate app-server streaming termination vs late notifications (diff updates, raw events).
- Consider concurrent tool execution support if parity is a goal.

---

## Suggested Validation Runs (after porting)

- SDK: `mix format` and `mix test`
- Live app-server smoke (requires local `codex`):
  - `examples/live_app_server_basic.exs`
  - `examples/live_app_server_streaming.exs`
  - `examples/live_app_server_approvals.exs`
- Manual checks:
  - `Codex.AppServer.Mcp.list_servers/2` works on new servers.
  - `Codex.AppServer.config_read(conn, include_layers: true)` shape matches docs.

