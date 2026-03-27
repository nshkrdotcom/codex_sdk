# Typed Plugin API

`Codex.AppServer` now exposes two plugin surfaces:

- raw wrappers that preserve the original map payloads
- typed wrappers backed by `Codex.Protocol.Plugin.*` structs

The raw wrappers remain:

- `plugin_list/2`
- `plugin_read/3`
- `plugin_install/4`
- `plugin_uninstall/3`

The typed wrappers are:

- `plugin_list_typed/2`
- `plugin_read_typed/3`
- `plugin_install_typed/4`
- `plugin_uninstall_typed/3`

There is also a generic typed request helper:

```elixir
alias Codex.AppServer
alias Codex.Protocol.Plugin

{:ok, %Plugin.ReadResponse{plugin: plugin}} =
  AppServer.request_typed(
    conn,
    "plugin/read",
    %Plugin.ReadParams{
      marketplace_path: "/tmp/marketplace.json",
      plugin_name: "demo-plugin"
    },
    Plugin.ReadResponse
  )
```

Raw and typed usage can live side by side:

```elixir
alias Codex.AppServer
alias Codex.Protocol.Plugin

{:ok, raw} =
  AppServer.plugin_read(conn, "/tmp/marketplace.json", "demo-plugin")

{:ok, %Plugin.ReadResponse{plugin: plugin}} =
  AppServer.plugin_read_typed(conn, "/tmp/marketplace.json", "demo-plugin")

IO.inspect(raw["plugin"]["apps"], label: "raw apps")
IO.inspect(plugin.apps, label: "typed apps")
```

## Typed Params

Typed plugin params own app-server wire encoding:

- `Plugin.ListParams`
- `Plugin.ReadParams`
- `Plugin.InstallParams`
- `Plugin.UninstallParams`

They accept snake_case Elixir fields and encode the upstream wire casing such as
`marketplacePath`, `pluginName`, and `forceRemoteSync`.

## Typed Responses

Typed plugin responses project the app-server payloads into structs while keeping
forward-compatible data:

- `Plugin.ListResponse`
- `Plugin.ReadResponse`
- `Plugin.InstallResponse`
- `Plugin.UninstallResponse`

Unknown upstream fields that matter for forward compatibility are preserved in
`extra` maps on the typed structs.

That includes fields that are broader than the current generated Python models,
such as:

- `featuredPluginIds`
- `marketplaceLoadErrors`
- app `needsAuth`

## Policies And Compatibility

Plugin install and auth policies normalize known upstream values into atoms:

- `AVAILABLE` -> `:available`
- `NOT_AVAILABLE` -> `:not_available`
- `INSTALLED_BY_DEFAULT` -> `:installed_by_default`
- `ON_INSTALL` -> `:on_install`
- `ON_USE` -> `:on_use`

Unknown future policy values are preserved as strings instead of being dropped.

## Raw vs Typed

Use the raw wrappers when you want the original wire maps or you are matching the
upstream JSON shape directly. Use the typed wrappers when you want:

- stable structs
- camelCase to snake_case normalization
- preserved `extra` metadata
- repo-local parse errors instead of raw validation internals

Nested response validation failures also stay on the outer response contract.
For example, an invalid `plugin/list` payload still returns
`{:error, {:invalid_plugin_list_response, details}}` instead of leaking nested
schema exceptions.

The typed plugin models remain local to `codex_sdk`; they are not moved into the
shared runtime-core repos.

Local manifest, marketplace, and scaffold authoring are a separate API on
`Codex.Plugins.*`. See `guides/13-plugin-authoring.md` and
`guides/14-plugin-marketplaces.md` for the local file-authoring surface.
