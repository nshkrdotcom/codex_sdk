# Migrating to 0.19

Codex SDK 0.19 aligns its subprocess runtime with `cli_subprocess_core ~> 0.7.0`.
This makes the SDK directly compatible with `agent_session_manager` 0.14 and
newer releases that use the same core line. No Codex-facing API migration is
required.

Update the dependency:

```elixir
{:codex_sdk, "~> 0.19.0"}
```

Then resolve dependencies normally. Applications that also declare
`cli_subprocess_core` directly must allow the `~> 0.7.0` line.

The release also preserves empty arrays in app-server payloads, projects
approval and full-auto policies explicitly, and completes interrupted
app-server streams without waiting indefinitely.
