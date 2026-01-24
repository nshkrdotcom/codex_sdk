Mix.Task.run("app.start")

alias Codex.{AppServer, Items, Options, Thread}

defmodule LivePersonality do
  @moduledoc false

  @default_prompt "Describe this repository in one paragraph."

  def main(argv) do
    prompt = parse_prompt(argv)

    codex_path = fetch_codex_path!()
    ensure_app_server_supported!(codex_path)

    {:ok, codex_opts} = Options.new(%{codex_path_override: codex_path})
    {:ok, conn} = AppServer.connect(codex_opts, init_timeout_ms: 30_000)

    try do
      {:ok, thread} =
        Codex.start_thread(codex_opts, %{
          transport: {:app_server, conn},
          working_directory: File.cwd!(),
          personality: :friendly
        })

      {friendly, thread} = run_turn(thread, prompt, %{timeout_ms: 120_000})

      {pragmatic, _thread} =
        run_turn(thread, prompt, %{personality: :pragmatic, timeout_ms: 120_000})

      IO.puts("""
      Friendly response:
      #{friendly}

      Pragmatic response:
      #{pragmatic}
      """)
    after
      :ok = AppServer.disconnect(conn)
    end
  end

  defp run_turn(thread, prompt, opts) do
    case Thread.run(thread, prompt, opts) do
      {:ok, result} -> {extract_text(result.final_response), result.thread}
      {:error, reason} -> {"<error: #{inspect(reason)}>", thread}
    end
  end

  defp parse_prompt([prompt | _]), do: prompt
  defp parse_prompt(_argv), do: @default_prompt

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

  defp extract_text(%Items.AgentMessage{text: text}) when is_binary(text), do: text
  defp extract_text(%{"type" => "text", "text" => text}) when is_binary(text), do: text
  defp extract_text(%{type: "text", text: text}) when is_binary(text), do: text
  defp extract_text(other) when is_binary(other), do: other
  defp extract_text(other), do: inspect(other)
end

LivePersonality.main(System.argv())
