# Plugin Marketplaces

`Codex.Plugins.Marketplace` models the local
`.agents/plugins/marketplace.json` file used by Codex discovery.

Canonical writes remain Codex-native, but read/validation flows also accept the
discoverable alternate marketplace path `.claude-plugin/marketplace.json`.

## Canonical Shape

Use nested `policy.*` fields for every plugin entry:

```elixir
{:ok, marketplace} =
  Codex.Plugins.new_marketplace(
    name: "repo-marketplace",
    interface: [display_name: "Repo Plugins"],
    plugins: [
      [
        name: "demo-plugin",
        source: [source: :local, path: "./plugins/demo-plugin"],
        policy: [installation: :available, authentication: :on_install],
        category: "Productivity"
      ]
    ]
  )
```

The SDK writes:

- `policy.installation`
- `policy.authentication`
- optional `policy.products`

It does not emit legacy top-level `installPolicy` or `authPolicy` as the
canonical output shape.

## Safe Updates

Use `add_marketplace_plugin/3` for read-modify-write updates:

```elixir
{:ok, result} =
  Codex.Plugins.add_marketplace_plugin(
    "/repo/.agents/plugins/marketplace.json",
    name: "demo-plugin",
    source: [source: :local, path: "./plugins/demo-plugin"],
    policy: [installation: :available, authentication: :on_install],
    category: "Productivity"
  )
```

Behavior:

- preserves unrelated plugin entries
- preserves unknown forward-compatible keys where possible, including overwrite
  updates on an existing entry
- preserves optional compatible metadata such as `policy.products` unless you
  replace it explicitly
- refuses duplicate plugin names unless `overwrite: true`
- writes deterministic pretty JSON with a trailing newline

## Path Rules

Marketplace source paths must:

- start with `./`
- reject traversal segments such as `..`, even when the expanded path would
  still land under the marketplace root
- stay within the marketplace root
- resolve relative to the root owning the marketplace manifest

The root-containment check runs on read, write, and update flows when the
actual marketplace path is known.

For repo scope that means:

- marketplace: `<repo-root>/.agents/plugins/marketplace.json`
- plugin source path: `./plugins/<plugin-name>`

For alternate discovery compatibility, the SDK also accepts:

- marketplace: `<repo-root>/.claude-plugin/marketplace.json`
- plugin source path: `./plugins/<plugin-name>`

For personal scope that means:

- marketplace: `~/.agents/plugins/marketplace.json`
- plugin source path: `./plugins/<plugin-name>`

## Verification Workflow

Recommended split:

1. Author locally with `Codex.Plugins.*`.
2. Use `Codex.CLI.marketplace_add/2` or `Codex.AppServer.marketplace_add/3`
   when you need runtime marketplace acquisition from a source tree or Git ref.
3. Start `codex app-server` only if you want runtime verification.
4. Verify discovery with `plugin/list`.
5. Verify details with `plugin/read`.

The local authoring layer and the runtime verification layer share validation
vocabulary where it is stable, but they remain separate APIs.
