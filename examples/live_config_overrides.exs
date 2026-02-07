Mix.Task.run("app.start")

alias Codex.{Options, Thread}

defmodule LiveConfigOverrides do
  @moduledoc false

  def main do
    codex_path = fetch_codex_path!()

    {:ok, codex_opts} = Options.new(%{codex_path_override: codex_path})

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

    {:ok, thread} = Codex.start_thread(codex_opts, thread_opts)

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

  defp fetch_codex_path! do
    System.get_env("CODEX_PATH") ||
      System.find_executable("codex") ||
      Mix.raise("""
      Unable to locate the `codex` CLI.
      Install the Codex CLI and ensure it is on your PATH or set CODEX_PATH.
      """)
  end

  defp extract_text(%Codex.Items.AgentMessage{text: text}) when is_binary(text), do: text
  defp extract_text(%{"type" => "text", "text" => text}) when is_binary(text), do: text
  defp extract_text(%{type: "text", text: text}) when is_binary(text), do: text
  defp extract_text(other) when is_binary(other), do: other
  defp extract_text(other), do: inspect(other)
end

LiveConfigOverrides.main()
