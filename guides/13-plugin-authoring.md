# Plugin Authoring

`Codex.Plugins` owns the local plugin authoring surface.

Use it when you want to create or maintain:

- `.codex-plugin/plugin.json`
- `.agents/plugins/marketplace.json`
- minimal local plugin directory trees

The local authoring defaults stay Codex-native, but the reader/path helpers now
also accept the discoverable Claude-compatible locations:

- `.claude-plugin/plugin.json`
- `.claude-plugin/marketplace.json`

This namespace is intentionally separate from `Codex.AppServer.plugin_*`.
Authoring uses normal Elixir file IO and does not require a running Codex
subprocess.

## Core API

```elixir
{:ok, manifest} =
  Codex.Plugins.new_manifest(
    name: "demo-plugin",
    skills: "./skills",
    interface: [display_name: "Demo Plugin"]
  )

:ok =
  Codex.Plugins.write_manifest(
    "/repo/plugins/demo-plugin/.codex-plugin/plugin.json",
    manifest,
    create_parents: true
  )
```

High-level scaffold:

```elixir
{:ok, result} =
  Codex.Plugins.scaffold(
    cwd: "/repo/root",
    plugin_name: "demo-plugin",
    with_marketplace: true,
    skill: [name: "hello-world", description: "Greets the user"]
  )
```

`result` includes:

- `plugin_root`
- `manifest_path`
- `marketplace_path` when requested
- `skill_paths`

## Validation Rules

Stable rules enforced locally:

- manifest `name` must be a non-empty kebab-case identifier
- manifest component paths such as `skills`, `hooks`, `mcpServers`, `apps`, and
  interface asset paths must start with `./`
- relative paths cannot escape with `..`
- `interface.defaultPrompt` accepts at most 3 prompts and each prompt must be
  128 characters or fewer after whitespace normalization
- writes are deterministic JSON with a trailing newline
- scaffold does not generate `mix.exs`, `.formatter.exs`, `build_support/*`, or
  Dialyzer/PLT files in phase 1

Unknown forward-compatible keys are preserved in `extra` maps and survive
read-modify-write flows where possible.

## Scope Resolution

Repo scope:

- plugin root defaults to `<repo-root>/plugins/<plugin-name>`
- marketplace defaults to `<repo-root>/.agents/plugins/marketplace.json`

Personal scope:

- plugin root defaults to `~/plugins/<plugin-name>`
- marketplace defaults to `~/.agents/plugins/marketplace.json`

You can override either path explicitly with `root:` or `marketplace_path:`.

## Compatibility Discovery

Write and scaffold flows still default to:

- `.codex-plugin/plugin.json`
- `.agents/plugins/marketplace.json`

Read and validation flows now accept either the Codex-native paths above or the
discoverable Claude-compatible paths when you pass those files explicitly, or
when a plugin root already contains only the alternate manifest location.

## Authoring Versus Runtime

Normal authoring flows should stay local:

- `Codex.Plugins.write_manifest/3`
- `Codex.Plugins.write_marketplace/3`
- `Codex.Plugins.add_marketplace_plugin/3`
- `Codex.Plugins.scaffold/1`

Runtime verification stays on app-server:

- `Codex.AppServer.plugin_list_typed/2`
- `Codex.AppServer.plugin_read_typed/3`
- `Codex.AppServer.plugin_install_typed/4`
- `Codex.AppServer.plugin_uninstall_typed/3`
- `Codex.AppServer.marketplace_add/3` when you want runtime marketplace import
  rather than local file authoring

If you need the literal CLI marketplace surface instead of JSON-RPC, use
`Codex.CLI.marketplace_add/2`.

The SDK does not route normal local authoring through app-server `fs/*`.
