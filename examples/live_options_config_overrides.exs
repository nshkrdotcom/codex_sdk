Mix.Task.run("app.start")

alias Codex.{Options, Thread}

defmodule LiveOptionsConfigOverrides do
  @moduledoc false

  @default_prompt "Reply with exactly: options config overrides work"

  def main(argv) do
    prompt = parse_prompt(argv)
    codex_path = fetch_codex_path!()

    {:ok, codex_opts} =
      Options.new(%{
        codex_path_override: codex_path,
        config: %{
          "approval_policy" => "never",
          "model_reasoning_summary" => "concise"
        }
      })

    IO.puts("Options-level config overrides (global baseline):")
    IO.inspect(codex_opts.config_overrides)

    {:ok, thread_opts} =
      Thread.Options.new(%{
        config_overrides: %{"model_reasoning_summary" => "detailed"}
      })

    {:ok, thread} = Codex.start_thread(codex_opts, thread_opts)

    turn_opts = %{
      config_overrides: %{"model_reasoning_summary" => "none"},
      timeout_ms: 60_000
    }

    IO.puts("\nRunning turn with thread + turn overrides (turn wins last)...")

    case Thread.run(thread, prompt, turn_opts) do
      {:ok, result} ->
        IO.puts("Response: #{extract_text(result.final_response)}")

      {:error, reason} ->
        IO.puts("Error: #{inspect(reason)}")
    end

    IO.puts("\nDemonstrating runtime validation for invalid config values...")

    case Options.new(%{config: %{"features" => %{"web_search_request" => nil}}}) do
      {:ok, _opts} ->
        IO.puts("Unexpected success: nil values should be rejected.")

      {:error, reason} ->
        IO.puts("Expected validation error: #{inspect(reason)}")
    end
  end

  defp parse_prompt([prompt | _]), do: prompt
  defp parse_prompt(_), do: @default_prompt

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

LiveOptionsConfigOverrides.main(System.argv())
