Mix.Task.run("app.start")

defmodule CodexExamples.LiveAppServerPlugins do
  @moduledoc false

  def main(_argv) do
    case run() do
      :ok ->
        :ok

      {:skip, reason} ->
        IO.puts("SKIPPED: #{reason}")

      {:error, reason} ->
        Mix.raise("Plugin example failed: #{inspect(reason)}")
    end
  end

  defp run do
    with {:ok, codex_path} <- fetch_codex_path(),
         :ok <- ensure_app_server_supported(codex_path),
         :ok <- ensure_auth_available(),
         {:ok, codex_opts} <-
           Codex.Options.new(%{
             codex_path_override: codex_path,
             reasoning_effort: :low
           }),
         {:ok, conn} <- Codex.AppServer.connect(codex_opts, init_timeout_ms: 30_000) do
      try do
        with :ok <- ensure_plugin_read_supported(conn),
             {:ok, %{"marketplaces" => marketplaces} = list_result} <-
               call_with_timeout(
                 fn ->
                   request_or_skip(
                     Codex.AppServer.plugin_list(conn, cwds: [File.cwd!()]),
                     "plugin"
                   )
                 end,
                 10_000,
                 "plugin/list timed out; retry after configuring plugins or marketplace access"
               ),
             {:ok, marketplace, plugin_summary} <- pick_first_plugin(marketplaces, list_result),
             marketplace_path when is_binary(marketplace_path) <- Map.get(marketplace, "path"),
             plugin_name when is_binary(plugin_name) <- Map.get(plugin_summary, "name"),
             {:ok, %{"plugin" => plugin_detail}} <-
               call_with_timeout(
                 fn ->
                   request_or_skip(
                     Codex.AppServer.plugin_read(conn, marketplace_path, plugin_name),
                     "plugin/read"
                   )
                 end,
                 10_000,
                 "plugin/read timed out while loading plugin details"
               ) do
          print_plugin_detail(plugin_detail)
          :ok
        end
      after
        :ok = Codex.AppServer.disconnect(conn)
      end
    else
      {:skip, _reason} = skip ->
        skip

      nil ->
        {:skip, "plugin/list did not return a marketplace path or plugin name"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp request_or_skip({:ok, result}, _feature), do: {:ok, result}

  defp request_or_skip({:error, %{"code" => code, "message" => message}}, feature)
       when code in [-32_601, -32_600, -32601, -32600] do
    {:skip, "#{feature} APIs are not supported by this `codex app-server` build: #{message}"}
  end

  defp request_or_skip({:error, reason}, _feature), do: {:error, reason}

  defp ensure_plugin_read_supported(conn) do
    case Codex.AppServer.Connection.request(conn, "__codex_sdk_capability_probe__", %{},
           timeout_ms: 5_000
         ) do
      {:error, %{"message" => message}} when is_binary(message) ->
        if String.contains?(message, "`plugin/read`") do
          :ok
        else
          {:skip,
           "this `codex app-server` build does not advertise `plugin/read`; upgrade Codex and retry"}
        end

      {:error, _reason} ->
        :ok

      {:ok, _result} ->
        :ok
    end
  end

  defp call_with_timeout(fun, timeout_ms, timeout_reason) when is_function(fun, 0) do
    task = Task.async(fun)

    case Task.yield(task, timeout_ms) do
      {:ok, result} ->
        result

      nil ->
        Task.shutdown(task, :brutal_kill)
        {:skip, timeout_reason}
    end
  end

  defp pick_first_plugin(marketplaces, %{"remoteSyncError" => remote_sync_error})
       when is_list(marketplaces) do
    case Enum.find(
           marketplaces,
           &(is_list(Map.get(&1, "plugins")) and Map.get(&1, "plugins") != [])
         ) do
      nil when is_binary(remote_sync_error) and remote_sync_error != "" ->
        {:skip,
         "plugin/list returned no plugins and reported remoteSyncError: #{remote_sync_error}"}

      nil ->
        {:skip,
         "plugin/list returned no plugins; enable plugins in Codex config or add a marketplace before rerunning"}

      %{"plugins" => [plugin | _]} = marketplace ->
        {:ok, marketplace, plugin}
    end
  end

  defp pick_first_plugin(marketplaces, _response) when is_list(marketplaces) do
    pick_first_plugin(marketplaces, %{})
  end

  defp print_plugin_detail(%{} = plugin) do
    summary = Map.get(plugin, "summary") || %{}
    interface = Map.get(summary, "interface") || %{}
    skills = Map.get(plugin, "skills") || []
    apps = Map.get(plugin, "apps") || []
    mcp_servers = Map.get(plugin, "mcpServers") || Map.get(plugin, "mcp_servers") || []

    IO.puts("""
    App-server plugin/read demo completed.
      marketplace: #{Map.get(plugin, "marketplaceName")}
      marketplace_path: #{Map.get(plugin, "marketplacePath")}
      id: #{Map.get(summary, "id")}
      name: #{Map.get(summary, "name")}
      display_name: #{Map.get(interface, "displayName") || Map.get(summary, "name")}
      installed: #{inspect(Map.get(summary, "installed"))}
      enabled: #{inspect(Map.get(summary, "enabled"))}
      install_policy: #{inspect(Map.get(summary, "installPolicy"))}
      auth_policy: #{inspect(Map.get(summary, "authPolicy"))}
    """)

    if description = Map.get(plugin, "description") do
      IO.puts("Description:\n#{description}\n")
    end

    IO.puts("Skills:")

    if skills == [] do
      IO.puts("  (none)")
    else
      Enum.each(skills, fn skill ->
        IO.puts("  - #{skill["name"]}: #{skill["description"]}")
      end)
    end

    IO.puts("\nApps:")

    if apps == [] do
      IO.puts("  (none)")
    else
      Enum.each(apps, fn app ->
        IO.puts(
          "  - #{app["name"] || app["id"]} (id=#{app["id"]}, installUrl=#{inspect(app["installUrl"])})"
        )
      end)
    end

    IO.puts("\nMCP servers:")

    if mcp_servers == [] do
      IO.puts("  (none)")
    else
      Enum.each(mcp_servers, &IO.puts("  - #{&1}"))
    end
  end

  defp fetch_codex_path do
    case System.get_env("CODEX_PATH") || System.find_executable("codex") do
      nil ->
        {:skip, "install the `codex` CLI or set CODEX_PATH before running this example"}

      path ->
        {:ok, path}
    end
  end

  defp ensure_app_server_supported(codex_path) do
    {_output, status} = System.cmd(codex_path, ["app-server", "--help"], stderr_to_stdout: true)

    if status != 0 do
      {:skip, "your `codex` CLI does not support `codex app-server`; upgrade it and retry"}
    else
      :ok
    end
  end

  defp ensure_auth_available do
    if Codex.Auth.api_key() || Codex.Auth.chatgpt_access_token() do
      :ok
    else
      {:skip, "authenticate with `codex login` or set CODEX_API_KEY before running this example"}
    end
  end
end

CodexExamples.LiveAppServerPlugins.main(System.argv())
