defmodule Codex.Integration.PluginAuthoringVerificationTest do
  use ExUnit.Case, async: false

  alias CliSubprocessCore.CommandSpec
  alias Codex.AppServer
  alias Codex.Options
  alias Codex.Plugins
  alias Codex.Protocol.Plugin
  alias Codex.TestSupport.TempDir

  @moduletag :integration

  test "local scaffold output remains separate from runtime verification and is readable through app-server" do
    case codex_options() do
      {:skip, _reason} ->
        :ok

      {:ok, codex_opts} ->
        temp_root =
          TempDir.create!("plugin_authoring_verification")
          |> tap(&on_exit(fn -> File.rm_rf!(&1) end))

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

            case AppServer.plugin_read_typed(conn, marketplace.path, plugin.name) do
              {:ok, %Plugin.ReadResponse{plugin: detail}} ->
                assert detail.summary.name == "demo-plugin"
                assert Enum.any?(detail.skills, &(&1.name == "demo-plugin:hello-world"))

              {:error, {:invalid_plugin_read_response, details}} ->
                assert missing_enabled_issue?(details)
                :ok

              {:error, %{"code" => code}}
              when code in [-32_601, -32_600] ->
                :ok

              {:error, reason} ->
                flunk("expected plugin/read verification to succeed, got: #{inspect(reason)}")
            end

          {:error, %{"code" => code, "message" => message}}
          when code in [-32_601, -32_600] ->
            assert is_binary(message)
            :ok

          {:error, reason} ->
            flunk("expected plugin verification to succeed, got: #{inspect(reason)}")
        end
    end
  end

  defp codex_options do
    with {:ok, codex_opts} <- Options.new(%{}),
         {:ok, spec} <- Options.codex_command_spec(codex_opts) do
      case run_command_spec(spec, ["app-server", "--help"]) do
        {_output, 0} -> {:ok, codex_opts}
        _ -> {:skip, "codex CLI does not support app-server"}
      end
    else
      {:error, :codex_binary_not_found} ->
        {:skip, "codex CLI is not installed"}

      {:error, reason} ->
        {:skip, "codex CLI is not runnable: #{inspect(reason)}"}
    end
  end

  defp run_command_spec(%CommandSpec{} = spec, args) when is_list(args) do
    System.cmd(spec.program, CommandSpec.command_args(spec, args), stderr_to_stdout: true)
  end

  defp missing_enabled_issue?(%{issues: issues}) when is_list(issues) do
    Enum.any?(issues, &(&1[:code] == :required and &1[:path] == ["enabled"]))
  end

  defp missing_enabled_issue?(_details), do: false
end
