Mix.Task.run("app.start")

Code.require_file(Path.expand("support/example_helper.exs", __DIR__))

alias CodexExamples.Support

Support.init!()

alias Codex.{Options, Thread}
alias Codex.Config.LayerStack

defmodule LiveOptionsConfigOverrides do
  @moduledoc false

  @default_prompt "Reply with exactly: options config overrides work"

  def main(argv) do
    demo_layered_provider_config()
    prompt = parse_prompt(argv)

    codex_opts =
      Support.codex_options!(%{
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

    {:ok, thread} = Codex.start_thread(codex_opts, Support.thread_opts!(thread_opts))

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

  defp demo_layered_provider_config do
    tmp_home =
      Path.join(System.tmp_dir!(), "codex_options_config_#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_home)

    try do
      File.write!(
        Path.join(tmp_home, "config.toml"),
        """
        openai_base_url = "https://gateway.example.com/v1"

        [model_providers.gateway_provider]
        name = "Gateway Provider"
        base_url = "https://gateway.example.com/v1"
        env_key = "OPENAI_API_KEY"
        wire_api = "responses"
        """
      )

      {:ok, layers} = LayerStack.load(tmp_home, File.cwd!())
      config = LayerStack.effective_config(layers)

      IO.puts("Config.toml parity note:")
      IO.puts("  openai_base_url: #{config["openai_base_url"]}")
      IO.puts("  provider ids: #{inspect(Map.keys(config["model_providers"] || %{}))}")
      IO.puts("  reserved ids like openai/ollama/lmstudio cannot be redefined.")
    after
      File.rm_rf(tmp_home)
    end
  end

  defp parse_prompt([prompt | _]), do: prompt
  defp parse_prompt(_), do: @default_prompt

  defp extract_text(%Codex.Items.AgentMessage{text: text}) when is_binary(text), do: text
  defp extract_text(%{"type" => "text", "text" => text}) when is_binary(text), do: text
  defp extract_text(%{type: "text", text: text}) when is_binary(text), do: text
  defp extract_text(other) when is_binary(other), do: other
  defp extract_text(other), do: inspect(other)
end

LiveOptionsConfigOverrides.main(System.argv())
