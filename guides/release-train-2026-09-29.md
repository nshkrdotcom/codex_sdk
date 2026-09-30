# Codex model release train — 2026-09-29

Prepared versions, in publication order:

1. `cli_subprocess_core 0.9.2`
2. `codex_sdk 0.21.3` (requires Core `~> 0.9.3`)
3. `agent_session_manager 0.17.2` (requires Core `~> 0.9.3`)

All three consume the shared GPT-6.1 Sol default with low CLI reasoning effort.
The authenticated `codex-cli 0.159.0` catalog is recorded in Core's
`test/fixtures/codex_model_list_20260929.json`. Existing lower Execution Plane
and Ground Plane releases remain prerequisites and need no new release.
ASM keeps provider SDKs optional and documents Codex SDK `~> 0.21.3` for callers
who install its SDK lane.

## Publication handoff

Publication is authorized for this train. Resolve downstream Hex locks against
Core 0.9.2 after its publication. Do not fabricate a lock checksum or publish
downstream packages with local path dependencies.

Use ordinary Hex mode for each command below (`env -u
MIX_WORKSPACE_OPS_BOOTSTRAP mix ...`); stop if a required version is unavailable.
Commit the reviewed source changes before publishing each package. Publish Core
first using `mix hex.publish` from its repository. After confirming Core 0.9.2
is available on Hex, run these commands in the SDK repository, then ASM:

```sh
env -u MIX_WORKSPACE_OPS_BOOTSTRAP mix deps.update cli_subprocess_core
env -u MIX_WORKSPACE_OPS_BOOTSTRAP mix deps
# Confirm cli_subprocess_core resolves from Hex at 0.9.2.
env -u MIX_WORKSPACE_OPS_BOOTSTRAP mix compile --warnings-as-errors
env -u MIX_WORKSPACE_OPS_BOOTSTRAP mix test
env -u MIX_WORKSPACE_OPS_BOOTSTRAP mix hex.build
```

Commit each refreshed `mix.lock` before publishing that package. Run
`mix hex.publish` after validation. Confirm SDK 0.21.3 is
available before publishing ASM. ASM has no direct SDK dependency or SDK lock
to update; SDK consumers should update `codex_sdk` to 0.21.3 in their own locks.
Tag each exact published commit `v0.9.2`, `v0.21.3`, or `v0.17.2` after verifying
its Hex release. A clean standalone Hex resolution after Core publication is
the remaining release-time check; local source verification cannot replace it.

## Recorded validation

The live SDK exec test using the strict registered default returned
`SDK_RELEASE_OK`; ASM's Core lane using GPT-6.1 Sol returned `ASM_RELEASE_OK`.
Both ran through `~/scripts/with_bash_secrets` on 2026-09-29. No credentials
are included in the catalog fixture. These checks verify model routing and
completion, not complete CLI protocol parity or product acceptance.
