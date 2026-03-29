Mix.Task.run("app.start")

Code.require_file(Path.expand("support/example_helper.exs", __DIR__))

alias CodexExamples.Support

Support.init!()

defmodule CodexExamples.LiveAppServerMcp do
  @moduledoc false

  def main(_argv) do
    codex_opts = Support.codex_options!()
    :ok = Support.ensure_app_server_supported(codex_opts)

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

    tool_names = tool_names(server)

    resources =
      case Map.get(server, "resources") do
        list when is_list(list) -> length(list)
        _ -> 0
      end

    IO.puts("""

    - #{name}
      requiresAuth: #{inspect(requires_auth)}
      tools: #{length(tool_names)}
      resources: #{resources}
    """)

    Enum.each(tool_names, fn tool_name ->
      qualified_name = Codex.MCP.Client.qualify_tool_name(name, tool_name)

      IO.puts("    tool: #{tool_name}")
      IO.puts("    qualified: #{qualified_name}")
    end)
  end

  defp tool_names(%{"tools" => %{} = tools}) do
    Map.keys(tools)
  end

  defp tool_names(%{"tools" => tools}) when is_list(tools) do
    Enum.map(tools, fn
      %{"name" => name} -> name
      %{name: name} -> name
      other -> inspect(other)
    end)
  end

  defp tool_names(_server), do: []
end

CodexExamples.LiveAppServerMcp.main(System.argv())
