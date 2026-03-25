Mix.Task.run("app.start")

defmodule CodexExamples.LiveCLIDemo do
  def main(argv) do
    question =
      case argv do
        [] -> "What is the capital of France?"
        values -> Enum.join(values, " ")
      end

    opts = %{
      api_key: fetch_api_key(),
      codex_path_override: fetch_codex_path()
    }

    with {:ok, thread} <- Codex.start_thread(opts),
         {:ok, result} <- Codex.Thread.run(thread, question) do
      answer =
        case result.final_response do
          %{"type" => "text", "text" => text} -> text
          other -> inspect(other)
        end

      IO.puts("""
      Question: #{question}
      Answer: #{answer}
      """)
    else
      {:error, reason} ->
        Mix.raise("Live Codex run failed: #{inspect(reason)}")
    end
  end

  defp fetch_codex_path do
    System.get_env("CODEX_PATH") ||
      System.find_executable("codex") ||
      Mix.raise("""
      Unable to locate the `codex` CLI.
      Install the Codex CLI and ensure it is on your PATH or set CODEX_PATH.
      """)
  end

  defp fetch_api_key do
    case System.get_env("CODEX_API_KEY") do
      key when is_binary(key) and key != "" ->
        key

      _ ->
        fallback_token()
    end
  end

  defp fallback_token do
    cli_paths = [
      [".config", "codex", "credentials.json"],
      [".config", "openai", "codex.json"],
      [".codex", "credentials.json"]
    ]

    cli_paths
    |> Enum.map(fn segments ->
      System.user_home!()
      |> Path.join(Enum.join(segments, "/"))
    end)
    |> Enum.find_value(&read_access_token/1)
  end

  defp read_access_token(path) do
    with true <- File.exists?(path),
         {:ok, contents} <- File.read(path),
         {:ok, %{"access_token" => token}} <- Jason.decode(contents),
         true <- token not in [nil, ""] do
      token
    else
      _ -> nil
    end
  end
end

CodexExamples.LiveCLIDemo.main(System.argv())
