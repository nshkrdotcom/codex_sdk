# OAuth and Login

`Codex.OAuth` adds an SDK-managed ChatGPT OAuth path alongside the existing
API-key and CLI passthrough auth behavior.

Use it when you want:

- upstream-compatible persistent ChatGPT login written to `auth.json`
- a host-managed login UX built from `begin_login/1` + `await_login/2`
- memory-only auth for embedded app-server clients

## Auth resolution overview

For normal CLI-backed SDK execution, auth precedence remains:

1. `CODEX_API_KEY`
2. `auth.json` `OPENAI_API_KEY`
3. ChatGPT OAuth tokens in `auth.json`

`Codex.OAuth` only manages the ChatGPT OAuth branch. It does not replace direct
API-key auth for realtime or voice.

Persistent OAuth respects upstream `auth_mode`:

- `chatgpt` means managed ChatGPT OAuth persisted on disk
- `chatgptAuthTokens` remains external/ephemeral semantics
- stale `OPENAI_API_KEY` values in `auth.json` do not silently override a
  persisted ChatGPT `auth_mode`

ChatGPT plan strings are canonicalized before the SDK exposes or forwards them:

- `hc` and case variants of `enterprise` become `"enterprise"`
- `education` and `edu` become `"edu"`
- existing canonical lowercase plans such as `"free"`, `"plus"`, `"pro"`,
  `"team"`, and `"business"` stay unchanged

## Public API

```elixir
{:ok, result} = Codex.OAuth.login(storage: :file, interactive?: true)
{:ok, status} = Codex.OAuth.status()
{:ok, status} = Codex.OAuth.refresh()
:ok = Codex.OAuth.logout()
```

Host applications can control the browser UX directly:

```elixir
{:ok, pending} = Codex.OAuth.begin_login(storage: :memory, interactive?: true)
:ok = Codex.OAuth.open_in_browser(pending)
{:ok, result} = Codex.OAuth.await_login(pending, timeout: 120_000)
```

## Storage modes

### `storage: :file` or `:auto`

- writes upstream-compatible `auth.json` under the effective `CODEX_HOME`
- normal exec/app-server/model-list flows can reuse those credentials naturally
- `Codex.OAuth.refresh/1` rotates refreshed tokens back into that file

### `storage: :memory`

- keeps tokens in memory only
- avoids writing the login to disk
- is the mode used for external app-server auth

## Environment behavior

- Local desktop: browser auth code + PKCE + loopback callback
- WSL: browser first, then device code fallback if the callback never arrives
- SSH/headless/container: device code by default
- CI/non-interactive: no automatic login; existing credentials are used or the
  call fails clearly

The browser flow always uses:

- an external browser
- PKCE `S256`
- a loopback listener bound to `127.0.0.1`, with an upstream-compatible browser redirect URI on `localhost`
- the upstream-compatible localhost callback port `1455` by default, unless explicitly overridden

## App-server integration

Persistent child auth:

```elixir
{:ok, conn} =
  Codex.AppServer.connect(codex_opts,
    process_env: %{"CODEX_HOME" => "/tmp/codex-home"},
    oauth: [mode: :auto, storage: :file, interactive?: true]
  )
```

Memory-only external auth:

```elixir
{:ok, conn} =
  Codex.AppServer.connect(codex_opts,
    experimental_api: true,
    process_env: %{"CODEX_HOME" => "/tmp/codex-home"},
    oauth: [mode: :auto, storage: :memory, auto_refresh: true]
  )
```

Memory mode works like this:

1. the SDK obtains ChatGPT OAuth tokens natively
2. the app-server child initializes normally
3. the SDK calls `account/login/start` with `chatgptAuthTokens`
4. a connection-owned refresh responder answers
   `account/chatgptAuthTokens/refresh`

Set `auto_refresh: false` when you want to subscribe and respond to refresh
requests yourself.

Remote websocket app-server connections use the same external-auth shape:

```elixir
{:ok, conn} =
  Codex.AppServer.connect_remote(
    "wss://app-server.example/ws",
    auth_token_env: "CODEX_REMOTE_AUTH_TOKEN",
    experimental_api: true,
    oauth: [mode: :auto, storage: :memory, auto_refresh: true]
  )
```

Remote mode only supports `storage: :memory`. `storage: :file` and `:auto` are
rejected because there is no managed child process or child `CODEX_HOME` to
prepare ahead of time.

## Child environment semantics

When OAuth is used through `Codex.AppServer.connect/2`, auth resolution is based
on the effective child `cwd` and `process_env`, not the caller's current shell
state. That matters for isolated `CODEX_HOME` setups and repo-local config.

For `connect_remote/2`, `cwd` and `process_env` still inform auth-context
resolution, but they do not create or prepare a child process. Remote bearer
auth headers are only attached for `wss://` or loopback `ws://` websocket URLs.

## TLS / CA behavior

All OAuth HTTP traffic reuses `Codex.Net.CA`:

1. `CODEX_CA_CERTIFICATE`
2. `SSL_CERT_FILE`

The same trust root configuration is shared by CLI subprocesses, OAuth refresh,
MCP HTTP/OAuth, remote model fetches, realtime websockets, and voice HTTP
requests.

## Example

Run the live OAuth example:

```bash
mix run examples/live_oauth_login.exs
mix run examples/live_oauth_login.exs --interactive
mix run examples/live_oauth_login.exs --interactive --browser --no-browser
mix run examples/live_oauth_login.exs --interactive --device
mix run examples/live_oauth_login.exs --interactive --app-server-memory
```

By default the example uses an isolated temporary `CODEX_HOME`, so it does not
change the login stored in your normal Codex home. It always prints the current
OAuth `status` first. In non-interactive mode it never starts a login on its
own: if no saved session is available, it prints `SKIPPED` and exits cleanly.

Useful switches:

- `--interactive` allows the example to start a real login when needed.
- `--browser` forces browser login. `--device` forces device-code login.
- `--no-browser` prints the authorization URL and leaves it to you to open it
  manually.
- `--app-server-memory` continues into the memory-mode app-server flow after
  login so you can see SDK-managed external auth in action.
- `--keep-home` keeps the generated temporary `CODEX_HOME` instead of deleting
  it when the example exits.
- `CODEX_OAUTH_EXAMPLE_HOME=/path` reuses a specific `CODEX_HOME` so you can
  return to the same saved session on later runs.
- `--use-real-home` makes the example operate on your normal Codex home
  intentionally instead of an isolated temporary one.

For browser login, the example uses the upstream-compatible callback
`http://localhost:1455/auth/callback` by default. If that port is already in
use on your machine, pass `--callback-port=<port>` and open the printed URL in
your browser.
