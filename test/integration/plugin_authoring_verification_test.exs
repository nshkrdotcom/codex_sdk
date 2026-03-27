defmodule Codex.Integration.PluginAuthoringVerificationTest do
  use ExUnit.Case, async: false

  alias Codex.AppServer
  alias Codex.Protocol.Plugin
  alias Codex.Plugins

  @moduletag :integration

  test "local scaffold output remains separate from runtime verification and is readable through app-server" do
    case codex_path() do
      {:skip, reason} ->
        ExUnit.Callbacks.skip(reason)

      {:ok, codex_path} ->
        temp_root = temp_root("plugin_authoring_verification")
        repo_root = Path.join(temp_root, "repo")
        home_root = Path.join(temp_root, "home")
        codex_home = Path.join(home_root, ".codex")

        File.mkdir_p!(Path.join(repo_root, ".git"))
        File.mkdir_p!(codex_home)

        assert {:ok, scaffold} =
                 Plugins.scaffold(
                   cwd: repo_root,
                   plugin_name: "demo-plugin",
                   with_marketplace: true,
                   skill: [name: "hello-world", description: "Greets the user"]
                 )

        {:ok, codex_opts} = Codex.Options.new(%{codex_path_override: codex_path})

        {:ok, conn} =
          AppServer.connect(codex_opts,
            cwd: repo_root,
            process_env: %{
              "CODEX_HOME" => codex_home,
              "HOME" => home_root,
              "USERPROFILE" => home_root
            },
            init_timeout_ms: 30_000
          )

        on_exit(fn ->
          if Process.alive?(conn) do
            :ok = AppServer.disconnect(conn)
          end
        end)

        case AppServer.plugin_list_typed(conn, cwds: [repo_root]) do
          {:ok, %Plugin.ListResponse{marketplaces: marketplaces}} ->
            assert marketplace = Enum.find(marketplaces, &(&1.path == scaffold.marketplace_path))
            assert plugin = Enum.find(marketplace.plugins, &(&1.name == "demo-plugin"))

            assert {:ok, %Plugin.ReadResponse{plugin: detail}} =
                     AppServer.plugin_read_typed(conn, marketplace.path, plugin.name)

            assert detail.summary.name == "demo-plugin"
            assert Enum.any?(detail.skills, &(&1.name == "demo-plugin:hello-world"))

          {:error, %{"code" => code, "message" => message}}
          when code in [-32_601, -32_600, -32601, -32600] ->
            ExUnit.Callbacks.skip(
              "connected codex app-server build does not advertise plugin verification APIs: #{message}"
            )

          {:error, reason} ->
            flunk("expected plugin verification to succeed, got: #{inspect(reason)}")
        end
    end
  end

  defp codex_path do
    case System.find_executable("codex") do
      nil ->
        {:skip, "codex CLI is not installed"}

      path ->
        case System.cmd(path, ["app-server", "--help"], stderr_to_stdout: true) do
          {_output, 0} -> {:ok, path}
          _ -> {:skip, "codex CLI does not support app-server"}
        end
    end
  end

  defp temp_root(prefix) do
    Path.join(System.tmp_dir!(), "#{prefix}_#{System.unique_integer([:positive])}")
  end
end
