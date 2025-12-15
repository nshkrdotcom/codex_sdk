Mix.Task.run("app.start")

alias Codex.Items.AgentMessage

defmodule CodexExamples.LiveAppServerBasic do
  @moduledoc false

  @default_prompt "Reply with exactly ok and nothing else."

  def main(argv) do
    prompt =
      case argv do
        [] -> @default_prompt
        values -> Enum.join(values, " ")
      end

    codex_path = fetch_codex_path!()
    ensure_app_server_supported!(codex_path)

    {:ok, codex_opts} =
      Codex.Options.new(%{
        codex_path_override: codex_path
      })

    {:ok, conn} = Codex.AppServer.connect(codex_opts, init_timeout_ms: 30_000)

    try do
      {:ok, thread} =
        Codex.start_thread(codex_opts, %{
          transport: {:app_server, conn},
          working_directory: File.cwd!()
        })

      {:ok, result} = Codex.Thread.run(thread, prompt, %{timeout_ms: 120_000})

      IO.puts("""
      App-server turn completed.
        thread_id: #{inspect(result.thread.thread_id)}
        final_response: #{extract_text(result.final_response)}
      """)

      IO.puts("\nskills/list:")
      skills_result = Codex.AppServer.skills_list(conn, cwds: [File.cwd!()])

      case skills_result do
        {:error, %{"code" => -32600, "message" => message}} ->
          IO.puts("""
          skills/list is not supported by this `codex app-server` build.
          Upgrade your Codex CLI and retry.
          Raw error: #{message}
          """)

        other ->
          IO.inspect(other)
      end

      IO.puts("\nmodel/list (limit 5):")
      IO.inspect(Codex.AppServer.model_list(conn, limit: 5))

      IO.puts("\nthread/list (limit 3):")
      IO.inspect(Codex.AppServer.thread_list(conn, limit: 3))
    after
      :ok = Codex.AppServer.disconnect(conn)
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

  defp ensure_app_server_supported!(codex_path) do
    {_output, status} = System.cmd(codex_path, ["app-server", "--help"], stderr_to_stdout: true)

    if status != 0 do
      Mix.raise("""
      Your `codex` CLI does not appear to support `codex app-server`.
      Upgrade via `npm install -g @openai/codex` and retry.
      """)
    end
  end

  defp extract_text(%AgentMessage{text: text}) when is_binary(text), do: text
  defp extract_text(%{"type" => "text", "text" => text}) when is_binary(text), do: text
  defp extract_text(%{type: "text", text: text}) when is_binary(text), do: text
  defp extract_text(other) when is_binary(other), do: other
  defp extract_text(other), do: inspect(other)
end

CodexExamples.LiveAppServerBasic.main(System.argv())
