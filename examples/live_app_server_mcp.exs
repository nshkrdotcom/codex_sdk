Mix.Task.run("app.start")

defmodule CodexExamples.LiveAppServerMcp do
  @moduledoc false

  def main(_argv) do
    codex_path = fetch_codex_path!()
    ensure_app_server_supported!(codex_path)

    {:ok, codex_opts} =
      Codex.Options.new(%{
        codex_path_override: codex_path
      })

    {:ok, conn} = Codex.AppServer.connect(codex_opts, init_timeout_ms: 30_000)

    try do
      IO.puts("Listing MCP servers via app-server:")

      case Codex.AppServer.Mcp.list_servers(conn) do
        {:ok, %{"data" => servers} = response} when is_list(servers) ->
          IO.puts("Found #{length(servers)} MCP server(s).")

          Enum.each(servers, &print_server/1)

          if Map.has_key?(response, "nextCursor") do
            IO.puts("\nnextCursor: #{inspect(response["nextCursor"])}")
          end

        other ->
          IO.inspect(other)
      end
    after
      :ok = Codex.AppServer.disconnect(conn)
    end
  end

  defp print_server(%{} = server) do
    name = Map.get(server, "name") || "(unknown)"
    requires_auth = Map.get(server, "requiresAuth")

    tools =
      case Map.get(server, "tools") do
        %{} = tools -> map_size(tools)
        _ -> 0
      end

    resources =
      case Map.get(server, "resources") do
        list when is_list(list) -> length(list)
        _ -> 0
      end

    IO.puts("""

    - #{name}
      requiresAuth: #{inspect(requires_auth)}
      tools: #{tools}
      resources: #{resources}
    """)
  end

  defp fetch_codex_path! do
    System.get_env("CODEX_PATH") ||
      System.find_executable("codex") ||
      Mix.raise("""
      Unable to locate the `codex` CLI.
      Install the Codex CLI and ensure it is on your PATH or set CODEX_PATH.
      """)
  end

  defp ensure_app_server_supported!(codex_path) do
    {_output, status} = System.cmd(codex_path, ["app-server", "--help"], stderr_to_stdout: true)

    if status != 0 do
      Mix.raise("""
      Your `codex` CLI does not appear to support `codex app-server`.
      Upgrade via `npm install -g @openai/codex` and retry.
      """)
    end
  end
end

CodexExamples.LiveAppServerMcp.main(System.argv())
