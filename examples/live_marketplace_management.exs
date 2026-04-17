Mix.Task.run("app.start")

Code.require_file(Path.expand("support/example_helper.exs", __DIR__))

alias CodexExamples.Support

Support.init!()

defmodule CodexExamples.LiveMarketplaceManagement do
  @moduledoc false

  alias Codex.{AppServer, CLI}

  def main(_argv) do
    case run() do
      :ok ->
        :ok

      {:skip, reason} ->
        IO.puts("SKIPPED: #{reason}")

      {:error, reason} ->
        Mix.raise("Marketplace management example failed: #{inspect(reason)}")
    end
  end

  defp run do
    with :ok <-
           Support.ensure_local_execution_surface(
             "this example provisions host-local marketplace fixtures and does not support --ssh-host"
           ),
         {:ok, codex_opts} <- Support.codex_options(%{}, missing_cli: :skip),
         {:ok, fixture} <- build_fixture() do
      try do
        run_cli_flow(codex_opts, fixture)
        run_app_server_flow(codex_opts, fixture)
      after
        cleanup_fixture(fixture)
      end
    end
  end

  defp run_cli_flow(codex_opts, fixture) do
    IO.puts("CLI marketplace/add:")

    case CLI.marketplace_add("./source-marketplace",
           codex_opts: codex_opts,
           cwd: fixture.temp_root,
           env: isolated_env(fixture.cli_codex_home)
         ) do
      {:ok, result} ->
        stdout = String.trim(result.stdout)

        if stdout == "" do
          IO.puts("  completed with no stdout")
        else
          IO.puts(stdout)
        end

        :ok

      {:error, reason} ->
        {:error, {:marketplace_cli_failed, reason}}
    end
  end

  defp run_app_server_flow(codex_opts, fixture) do
    case Support.ensure_app_server_supported(codex_opts) do
      :ok ->
        with {:ok, conn} <-
               AppServer.connect(codex_opts,
                 cwd: fixture.temp_root,
                 process_env: isolated_env(fixture.app_codex_home),
                 init_timeout_ms: 30_000
               ) do
          try do
            IO.puts("\nApp-server marketplace/add:")

            case AppServer.marketplace_add(conn, "./source-marketplace") do
              {:ok, response} ->
                IO.inspect(response)
                :ok

              {:error, %{"code" => code, "message" => message}}
              when code in [-32_601, -32_600, -32601, -32600] ->
                IO.puts("SKIPPED app-server marketplace/add: #{message}")
                :ok

              {:error, reason} ->
                {:error, {:marketplace_app_server_failed, reason}}
            end
          after
            :ok = AppServer.disconnect(conn)
          end
        end

      {:skip, reason} ->
        IO.puts("\nSKIPPED app-server flow: #{reason}")
        :ok
    end
  end

  defp build_fixture do
    temp_root =
      Path.join(System.tmp_dir!(), "codex_marketplace_example_#{System.unique_integer([:positive])}")

    source_root = Path.join(temp_root, "source-marketplace")
    home_root = Path.join(temp_root, "home")
    cli_codex_home = Path.join(home_root, "cli/.codex")
    app_codex_home = Path.join(home_root, "app/.codex")

    with :ok <- File.mkdir_p(Path.join(source_root, ".git")),
         :ok <- File.mkdir_p(cli_codex_home),
         :ok <- File.mkdir_p(app_codex_home),
         {:ok, _result} <-
           Codex.Plugins.scaffold(
             cwd: source_root,
             plugin_name: "demo-plugin",
             with_marketplace: true,
             marketplace_name: "debug",
             marketplace_display_name: "Debug Plugins",
             category: "Productivity",
             manifest: [
               description: "Disposable marketplace fixture for the Codex SDK example",
               interface: [
                 display_name: "Demo Plugin",
                 short_description: "Temporary marketplace fixture"
               ]
             ]
           ) do
      {:ok,
       %{
         temp_root: temp_root,
         source_root: source_root,
         cli_codex_home: cli_codex_home,
         app_codex_home: app_codex_home
       }}
    else
      {:error, reason} ->
        cleanup_fixture(%{temp_root: temp_root})
        {:error, {:marketplace_fixture_setup_failed, reason}}
    end
  end

  defp cleanup_fixture(%{temp_root: temp_root}) when is_binary(temp_root),
    do: File.rm_rf(temp_root)

  defp cleanup_fixture(_fixture), do: :ok

  defp isolated_env(codex_home) when is_binary(codex_home) do
    home_root = Path.dirname(codex_home)

    %{
      "CODEX_HOME" => codex_home,
      "HOME" => home_root,
      "USERPROFILE" => home_root
    }
  end
end

CodexExamples.LiveMarketplaceManagement.main(System.argv())
