# Codex Provider Behavior Manifest

Provider-native Codex behavior must be proven here before this SDK translates
it. This manifest is SDK-owned evidence; it is not proof that ASM can expose the
feature as common behavior across providers.

| Feature | Evidence type | CLI version/source revision | Fixture | Live smoke | Known unsupported semantics | Date verified |
| --- | --- | --- | --- | --- | --- | --- |
| `codex exec --json` argument rendering for model, reasoning config, profile, sandbox, working directory, additional directories, output schema, continuation/cancellation, and image flags | source inspection note and SDK render tests | current Codex CLI contract as represented by SDK options | `test/codex/runtime_exec_render_test.exs`; `test/codex/exec_test.exs` | `examples/promotion_path/sdk_direct_codex.exs` | Codex-native exec flags; ASM must not accept these as generic provider options without all-four proof | 2026-04-29 |
| App-server transport, dynamic tools, MCP notifications, approval requests, sandbox policy, and permission profiles | source inspection note, recorded app-server fixtures, and live examples | current Codex app-server contract | `test/codex/app_server_transport_test.exs`; `examples/live_app_server_dynamic_tools.exs`; `examples/live_app_server_approvals.exs` | Existing app-server live examples | Codex-native only; does not establish common ASM host tools, approvals, MCP, or sandbox policy | 2026-04-29 |
| Shared `execution_surface` normalization for local and SSH placement | source inspection note and SDK runtime tests | current `cli_subprocess_core` dependency | `test/codex/exec_test.exs`; `test/codex/runtime_exec_render_test.exs` | `examples/promotion_path/sdk_direct_codex.exs` for local keyword input; live SSH tests remain opt-in | Placement only; execution surface metadata must not become provider-native Codex configuration | 2026-04-29 |

