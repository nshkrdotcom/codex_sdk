# TODO: Bundled Codex Runtime (Build/Ship a Pinned `codex` Binary)

## Context (Why this exists)

`codex_sdk` currently shells out to an **external** `codex` executable resolved via:

1. `codex_path_override` in `Codex.Options`
2. `CODEX_PATH`
3. `System.find_executable("codex")`

This makes the SDK’s feature surface **version-dependent** on whatever Codex CLI happens to be installed.

Concrete example seen in practice:

- `codex-cli 0.72.0` supports `codex app-server`, `model/list`, `thread/*`, etc.
- But `codex app-server` rejects the JSON-RPC method `skills/list` with `-32600` (unknown method enum variant).

This is not a client bug: it’s a runtime/protocol mismatch. A client can only call methods the server build implements.

## Goal

Make `codex_sdk` able to use a **pinned Codex runtime** that we control:

- reproducible (deterministic version)
- installable with a single command
- verifiable (expected protocol schema/capabilities)
- optional (do not break users who prefer system `codex`)

## Non-goals (for this TODO doc)

- Implementing Rustler (in-process Rust) now.
- Modifying the vendored `codex/` source tree in this repo (it’s treated as third-party).
- Making tests non-deterministic (no live network in default test runs).

## Key facts (as of the vendored upstream code)

### 1) The “npm codex” is a launcher + bundled native binary

`@openai/codex` installs a Node entrypoint that selects a vendored native binary under
`vendor/<target>/codex/codex` and execs it.

So “npm” is not a separate runtime implementation; it’s a distribution mechanism for a native `codex-cli` binary.

### 2) The open-source Rust CLI supports both login styles

The Rust CLI implements:

- ChatGPT browser login (local login server)
- ChatGPT device-code login (`https://auth.openai.com/codex/device`)
- API key login (read from stdin)

So bundling/building the Rust CLI does **not** imply “API-key-only”.

See upstream evidence:

- ChatGPT login server path: `codex/codex-rs/cli/src/login.rs:18`
- Device code prompt: `codex/codex-rs/login/src/device_code_auth.rs:140`
- API key login: `codex/codex-rs/cli/src/login.rs:67`

### 3) App-server protocol is versioned by the binary, not the client

The authoritative “what methods exist” is the runtime’s schema output:

`codex app-server generate-json-schema --out DIR`

If the generated schema does not contain `skills/list`, then no client can call it successfully.

## Proposed direction (high-level)

Add an opt-in “managed runtime” story:

- `mix codex.install` downloads or builds a known-good `codex` binary into a project-local location (e.g. `priv/codex/bin/codex`).
- `mix codex.verify` (or a new task) validates:
  - `codex --version`
  - `codex app-server generate-json-schema` contains required v2 methods (e.g. `skills/list`).
- `Codex.Options` / docs provide a canonical way to point the SDK at that binary (`codex_path_override`).

## Decision points (choose one distribution strategy)

### Option A: Download prebuilt binaries (recommended UX)

**Approach**

- Download a known Codex release artifact for the current OS/arch.
- Store it under `priv/` (or a cache dir) and set `CODEX_PATH`/`codex_path_override`.
- Verify checksums/signatures.

**Pros**
- No Rust toolchain required for end users.
- Fast installs; good for CI.

**Cons / Open questions**
- Does upstream publish stable per-platform artifacts suitable for this?
- How do we verify authenticity (checksums, signatures, provenance)?
- Which cadence (pin to `codex-cli X.Y.Z` vs commit hash)?

### Option B: Build from source (best “we control it”, worst UX)

**Approach**

- Require `cargo` and build `codex-cli` from a pinned commit.
- Copy the produced `codex` binary into `priv/…`.

**Pros**
- Full control; works even without upstream binary releases.
- Can compile exactly the code we want (and confirm `skills/list` exists).

**Cons**
- Heavy: Rust toolchain + build times.
- Cross-platform complexity (musl vs glibc, Windows signing, macOS notarization, etc.).
- CI complexity (caching, toolchains).

### Option C: Depend on npm-managed runtime (not recommended)

**Approach**

- Require Node + `@openai/codex` install.
- Resolve `codex` via npm global path or local node_modules.

**Pros**
- Simple “install story” for Node developers.

**Cons**
- Not an Elixir-native experience.
- Hard to guarantee which binary is inside the package.
- Still version drift unless pinned carefully.

## TODO checklist (implementation plan)

### Phase 0 — Research + constraints (1–2 days)

- [ ] Confirm upstream distribution options:
  - [ ] Are there official release artifacts for `codex-cli` (Linux/macOS/Windows)?
  - [ ] Are artifacts signed? Are checksums published?
  - [ ] Is there a “nightly”/main-branch build channel for features like `skills/list`?
- [ ] Confirm protocol presence for the desired features:
  - [ ] For target codex version(s), run `codex app-server generate-json-schema` and verify `skills/list` is present.
  - [ ] Identify any feature flags required at runtime (and whether they affect method availability).
- [ ] Decide pin strategy:
  - [ ] pin to `codex-cli` semver
  - [ ] or pin to upstream git SHA

### Phase 1 — Add a managed runtime installer (Mix task) (2–4 days)

- [ ] Add `mix codex.install`:
  - [ ] Install location: decide between `priv/bin/` vs `priv/codex/` vs `~/.cache/codex_sdk/…`
  - [ ] OS/arch detection and naming
  - [ ] Create/replace semantics (idempotent install)
  - [ ] Optional: `--force`, `--version`, `--sha`, `--out`
  - [ ] Verification step:
    - [ ] `codex --version` runs
    - [ ] executable bit set
- [ ] Add `mix codex.runtime` (or extend `mix codex.verify`):
  - [ ] Dump runtime info: resolved path, `--version`, method registry summary from schema
  - [ ] Explicitly show whether `skills/list` is available

### Phase 2 — Capability checks at runtime (SDK-level, backwards compatible) (2–3 days)

- [ ] Add a lightweight capability probe:
  - [ ] A function that runs `codex app-server generate-json-schema` (or a cached copy) and determines which v2 request methods are supported.
  - [ ] Expose this as `Codex.AppServer.capabilities/1` or similar.
- [ ] Improve error messaging for missing methods:
  - [ ] If server returns `-32600` with “unknown variant `X`”, map to a structured error:
    - `{:error, {:unsupported_method, "skills/list", runtime_version}}`
- [ ] Decide “strict mode”:
  - [ ] Optionally fail fast on connect if required methods are absent (configurable).

### Phase 3 — Login + credential story for bundled runtime (1–2 days)

- [ ] Document credential storage behavior:
  - [ ] `CODEX_HOME` usage
  - [ ] `cli_auth_credentials_store` (“file” vs “keyring” vs “auto”) and its implications
  - [ ] How this interacts with running inside containers/CI
- [ ] Decide whether `codex_sdk` should expose helper functions:
  - [ ] `Codex.Runtime.login/0` to run `codex login` interactively?
  - [ ] Or keep login as an external step and only document it?
- [ ] Ensure `Codex.Options.new/1` continues to:
  - [ ] accept `CODEX_API_KEY` / `OPENAI_API_KEY`
  - [ ] fall back to CLI login (`~/.codex/auth.json`) (already implemented today)

### Phase 4 — CI + testing strategy (2–4 days)

- [ ] Keep default tests deterministic:
  - [ ] do not build/download codex in `mix test` by default
  - [ ] keep live tests gated (existing `CODEX_TEST_LIVE=true`)
- [ ] Add a separate CI job / opt-in path for runtime verification:
  - [ ] install or build pinned runtime
  - [ ] run schema/capability checks
  - [ ] run live app-server tests (opt-in)

### Phase 5 — Packaging / release / licensing (1–3 days)

- [ ] Decide where the binary lives for end users:
  - [ ] Included in Hex package? (size concerns; license/provenance)
  - [ ] Download-on-install? (network + checksum management)
  - [ ] Build locally? (toolchain requirement)
- [ ] Write a security note:
  - [ ] supply chain verification
  - [ ] how to pin versions
  - [ ] how to audit the bundled binary

## Open questions

1. What upstream version/branch actually contains `skills/list` in app-server for shipping builds?
2. Is `skills` a compile-time inclusion, a feature flag, or both?
3. Do we want the SDK to:
   - tolerate missing methods (best-effort), or
   - require a minimum runtime version (strict)?
4. Where should credentials live for an embedded/bundled runtime in production apps?
   - per-user home (`~/.codex`) vs app-specific directory
5. Do we need a “portable” login for headless servers (API key only) as a recommended path?

## Acceptance criteria (for the eventual implementation)

- Users can run a single command to install a known-good runtime and point `codex_sdk` at it.
- SDK can detect and explain “missing method” errors (e.g. `skills/list`) with actionable remediation.
- Default test suite remains deterministic; live tests remain opt-in.
- Documentation clearly explains the login story (ChatGPT login vs API key) and credential storage.
