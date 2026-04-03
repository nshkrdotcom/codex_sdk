Mix.Task.run("app.start")

Code.require_file(Path.expand("support/example_helper.exs", __DIR__))

alias CodexExamples.Support

Support.init!()

alias Codex.Thread
alias Codex.Config.LayerStack

defmodule LiveConfigOverrides do
  @moduledoc false

  def main do
    demo_layered_provider_config()

    codex_opts = Support.codex_options!()

    # Demonstrate nested map auto-flattening for config overrides.
    # These nested maps are flattened to dotted-path keys before being
    # forwarded as --config flags to the Codex CLI.
    #
    # Example: %{"features" => %{"web_search_request" => true}}
    # becomes: --config features.web_search_request=true
    {:ok, thread_opts} =
      Thread.Options.new(%{
        config_overrides: %{
          "features" => %{
            "web_search_request" => true
          }
        }
      })

    {:ok, thread} = Codex.start_thread(codex_opts, Support.thread_opts!(thread_opts))

    IO.puts("Running turn with nested config overrides (features.web_search_request=true)...")

    case Thread.run(thread, "Reply with exactly: config override works", %{timeout_ms: 60_000}) do
      {:ok, result} ->
        text = extract_text(result.final_response)
        IO.puts("Response: #{text}")

      {:error, reason} ->
        IO.puts("Error: #{inspect(reason)}")
    end

    # Also show turn-level nested overrides with shell_environment_policy
    IO.puts("\nRunning turn with turn-level nested config overrides...")

    turn_opts = %{
      config_overrides: %{
        "shell_environment_policy" => %{
          "inherit" => "core"
        }
      },
      timeout_ms: 60_000
    }

    case Thread.run(thread, "Reply with exactly: turn override works", turn_opts) do
      {:ok, result} ->
        text = extract_text(result.final_response)
        IO.puts("Response: #{text}")

      {:error, reason} ->
        IO.puts("Error: #{inspect(reason)}")
    end
  end

  defp demo_layered_provider_config do
    tmp_home =
      Path.join(System.tmp_dir!(), "codex_config_example_#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_home)

    try do
      File.write!(
        Path.join(tmp_home, "config.toml"),
        """
        openai_base_url = "https://gateway.example.com/v1"

        [model_providers.openai_custom]
        name = "OpenAI Custom"
        base_url = "https://gateway.example.com/v1"
        env_key = "OPENAI_API_KEY"
        wire_api = "responses"
        """
      )

      {:ok, layers} = LayerStack.load(tmp_home, File.cwd!())
      config = LayerStack.effective_config(layers)

      IO.puts("""
      Layered config parity demo:
        openai_base_url: #{config["openai_base_url"]}
        model_providers: #{inspect(Map.keys(config["model_providers"] || %{}))}
      """)
    after
      File.rm_rf(tmp_home)
    end
  end

  defp extract_text(%Codex.Items.AgentMessage{text: text}) when is_binary(text), do: text
  defp extract_text(%{"type" => "text", "text" => text}) when is_binary(text), do: text
  defp extract_text(%{type: "text", text: text}) when is_binary(text), do: text
  defp extract_text(other) when is_binary(other), do: other
  defp extract_text(other), do: inspect(other)
end

LiveConfigOverrides.main()
