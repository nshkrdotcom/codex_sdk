Mix.Task.run("app.start")

defmodule CodexExamples.PluginScaffold do
  @moduledoc false

  def main(_argv) do
    temp_root =
      Path.join(System.tmp_dir!(), "codex_plugin_scaffold_#{System.unique_integer([:positive])}")

    repo_root = Path.join(temp_root, "repo")

    File.mkdir_p!(Path.join(repo_root, ".git"))

    case Codex.Plugins.scaffold(
           cwd: repo_root,
           plugin_name: "demo-plugin",
           with_marketplace: true,
           skill: [name: "hello-world", description: "Greets the user"]
         ) do
      {:ok, result} ->
        IO.puts("""
        Local plugin scaffold completed.
          temp_root: #{temp_root}
          repo_root: #{repo_root}
          plugin_root: #{result.plugin_root}
          manifest_path: #{result.manifest_path}
          marketplace_path: #{result.marketplace_path}
          skill_paths: #{Enum.join(result.skill_paths, ", ")}
        """)

        IO.puts("""
        This example uses local file IO only. It does not launch `codex app-server`
        and it does not route authoring through `fs/*`. Use
        `examples/live_app_server_plugins.exs` later if you want runtime
        verification against a running app-server.
        """)

      {:error, reason} ->
        Mix.raise("Plugin scaffold example failed: #{inspect(reason)}")
    end
  end
end

CodexExamples.PluginScaffold.main(System.argv())
