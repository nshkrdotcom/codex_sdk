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
         {:ok, fixture} <- build_demo_plugin_fixture() do
      try do
        with {:ok, codex_opts} <-
               Codex.Options.new(%{
                 codex_path_override: codex_path
               }),
             {:ok, conn} <-
               Codex.AppServer.connect(codex_opts,
                 cwd: fixture.repo_root,
                 process_env: isolated_process_env(fixture),
                 init_timeout_ms: 30_000
               ) do
          try do
            with :ok <- ensure_plugin_read_supported(conn),
                 {:ok, %{"marketplaces" => marketplaces} = list_result} <-
                   call_with_timeout(
                     fn ->
                       request_or_skip(
                         Codex.AppServer.plugin_list(conn, cwds: [fixture.repo_root]),
                         "plugin"
                       )
                     end,
                     10_000,
                     "plugin/list timed out while loading the temporary local marketplace"
                   ),
                 {:ok, marketplace, plugin_summary} <-
                   pick_demo_plugin(marketplaces, list_result, fixture),
                 marketplace_path when is_binary(marketplace_path) <-
                   Map.get(marketplace, "path"),
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
                     "plugin/read timed out while loading the temporary plugin details"
                   ) do
              print_plugin_detail(plugin_detail, fixture)
              :ok
            end
          after
            :ok = Codex.AppServer.disconnect(conn)
          end
        end
      after
        cleanup_fixture(fixture)
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

  defp build_demo_plugin_fixture do
    suffix = System.unique_integer([:positive])
    temp_root = Path.join(System.tmp_dir!(), "codex_plugin_example_#{suffix}")
    repo_root = Path.join(temp_root, "repo")
    home_root = Path.join(temp_root, "home")
    codex_home = Path.join(home_root, ".codex")
    marketplace_name = "codex-sdk-demo-marketplace-#{suffix}"
    plugin_name = "codex-sdk-demo-plugin-#{suffix}"
    plugin_root = Path.join(repo_root, "plugins/#{plugin_name}")
    marketplace_path = Path.join(repo_root, ".agents/plugins/marketplace.json")

    marketplace_json = """
    {
      "name": "#{marketplace_name}",
      "interface": {
        "displayName": "Codex SDK Demo Marketplace"
      },
      "plugins": [
        {
          "name": "#{plugin_name}",
          "source": {
            "source": "local",
            "path": "./plugins/#{plugin_name}"
          },
          "policy": {
            "installation": "AVAILABLE",
            "authentication": "ON_INSTALL"
          },
          "category": "Design"
        }
      ]
    }
    """

    plugin_json = """
    {
      "name": "#{plugin_name}",
      "description": "Local Codex SDK demo plugin loaded from a disposable fixture",
      "interface": {
        "displayName": "Codex SDK Demo Plugin",
        "shortDescription": "Disposable plugin fixture for plugin/read parity checks",
        "longDescription": "This plugin bundle is created under the system temp directory so the example can exercise plugin/list and plugin/read without mutating your real Codex home.",
        "developerName": "OpenAI",
        "category": "Productivity"
      }
    }
    """

    app_json = """
    {
      "apps": {
        "gmail": {
          "id": "gmail"
        }
      }
    }
    """

    mcp_json = """
    {
      "mcpServers": {
        "demo": {
          "command": "demo-server"
        }
      }
    }
    """

    with :ok <- File.mkdir_p(Path.join(repo_root, ".git")),
         :ok <- File.mkdir_p(codex_home),
         :ok <- File.mkdir_p(Path.join(repo_root, ".agents/plugins")),
         :ok <- File.mkdir_p(Path.join(plugin_root, ".codex-plugin")),
         :ok <- File.mkdir_p(Path.join(plugin_root, "skills/thread-summarizer")),
         :ok <- File.write(marketplace_path, marketplace_json),
         :ok <- File.write(Path.join(plugin_root, ".codex-plugin/plugin.json"), plugin_json),
         :ok <-
           File.write(
             Path.join(plugin_root, "skills/thread-summarizer/SKILL.md"),
             """
             ---
             name: thread-summarizer
             description: Summarize email threads
             ---

             # Thread Summarizer
             """
           ),
         :ok <- File.write(Path.join(plugin_root, ".app.json"), app_json),
         :ok <- File.write(Path.join(plugin_root, ".mcp.json"), mcp_json) do
      {:ok,
       %{
         temp_root: temp_root,
         repo_root: repo_root,
         home_root: home_root,
         codex_home: codex_home,
         marketplace_name: marketplace_name,
         marketplace_path: marketplace_path,
         plugin_name: plugin_name
       }}
    else
      {:error, reason} ->
        cleanup_fixture(%{temp_root: temp_root})
        {:error, {:plugin_fixture_setup_failed, reason}}
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

  defp pick_demo_plugin(marketplaces, %{"remoteSyncError" => remote_sync_error}, fixture)
       when is_list(marketplaces) do
    case Enum.find(marketplaces, &(Map.get(&1, "path") == fixture.marketplace_path)) do
      nil when is_binary(remote_sync_error) and remote_sync_error != "" ->
        {:skip,
         "plugin/list did not surface the temporary marketplace and reported remoteSyncError: #{remote_sync_error}"}

      nil ->
        {:skip,
         "plugin/list did not surface the temporary repo-local marketplace; this build may lack repo marketplace discovery parity"}

      %{"plugins" => plugins} = marketplace when is_list(plugins) ->
        case Enum.find(plugins, &(Map.get(&1, "name") == fixture.plugin_name)) do
          nil ->
            {:skip,
             "plugin/list returned the temporary marketplace but not the expected demo plugin"}

          plugin ->
            {:ok, marketplace, plugin}
        end
    end
  end

  defp pick_demo_plugin(marketplaces, _response, fixture) when is_list(marketplaces) do
    pick_demo_plugin(marketplaces, %{}, fixture)
  end

  defp print_plugin_detail(%{} = plugin, fixture) do
    summary = Map.get(plugin, "summary") || %{}
    interface = Map.get(summary, "interface") || %{}
    skills = Map.get(plugin, "skills") || []
    apps = Map.get(plugin, "apps") || []
    mcp_servers = Map.get(plugin, "mcpServers") || Map.get(plugin, "mcp_servers") || []

    needs_auth =
      Map.get(summary, "needsAuth") ||
        Map.get(summary, "needs_auth") ||
        Map.get(plugin, "needsAuth") ||
        Map.get(plugin, "needs_auth")

    IO.puts("""
    App-server plugin/read demo completed.
      fixture_root: #{fixture.temp_root}
      app_server_cwd: #{fixture.repo_root}
      isolated_codex_home: #{fixture.codex_home}
      marketplace: #{Map.get(plugin, "marketplaceName")}
      marketplace_path: #{Map.get(plugin, "marketplacePath")}
      id: #{Map.get(summary, "id")}
      name: #{Map.get(summary, "name")}
      display_name: #{Map.get(interface, "displayName") || Map.get(summary, "name")}
      installed: #{inspect(Map.get(summary, "installed"))}
      enabled: #{inspect(Map.get(summary, "enabled"))}
      install_policy: #{inspect(Map.get(summary, "installPolicy"))}
      auth_policy: #{inspect(Map.get(summary, "authPolicy"))}
      needs_auth: #{inspect(needs_auth)}
    """)

    IO.puts("""
    Note: this example launches `codex app-server` with an isolated child `cwd` and
    temporary `CODEX_HOME`, so it never touches your real Codex config. Because it only
    exercises `plugin/list` + `plugin/read` and does not install the plugin, `installed`
    and `enabled` should usually remain false. When upstream includes `needsAuth`, that
    field is surfaced verbatim so you can see whether an install would require auth.
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

  defp cleanup_fixture(%{temp_root: temp_root}) when is_binary(temp_root),
    do: File.rm_rf(temp_root)

  defp cleanup_fixture(_fixture), do: :ok

  defp isolated_process_env(fixture) do
    %{}
    |> maybe_put("CODEX_HOME", fixture.codex_home)
    |> maybe_put("HOME", System.get_env("HOME") || System.user_home!())
    |> maybe_put("USERPROFILE", System.get_env("USERPROFILE"))
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end

CodexExamples.LiveAppServerPlugins.main(System.argv())
