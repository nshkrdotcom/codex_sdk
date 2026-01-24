Mix.Task.run("app.start")

alias Codex.{AppServer, Items, Options, Thread}

defmodule LiveThreadManagement do
  @moduledoc false

  @default_prompt "Say hello in one sentence."

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
          working_directory: File.cwd!()
        })

      {:ok, result} = Thread.run(thread, prompt, %{timeout_ms: 120_000})
      thread_id = result.thread.thread_id

      IO.puts("""
      Thread started: #{inspect(thread_id)}
      Final response: #{extract_text(result.final_response)}
      """)

      IO.puts("thread/read:")
      IO.inspect(AppServer.thread_read(conn, thread_id, include_turns: true))

      IO.puts("\nthread/fork:")
      print_result_or_warning(AppServer.thread_fork(conn, thread_id), "thread/fork")

      IO.puts("\nthread/rollback (1 turn):")
      print_result_or_warning(AppServer.thread_rollback(conn, thread_id, 1), "thread/rollback")

      IO.puts("\nthread/loaded/list:")
      IO.inspect(AppServer.thread_loaded_list(conn))
    after
      :ok = AppServer.disconnect(conn)
    end
  end

  defp print_result_or_warning({:error, %{"code" => -32600, "message" => message}}, name) do
    IO.puts("#{name} is not supported by this codex app-server build.")
    IO.puts("Raw error: #{message}")
  end

  defp print_result_or_warning(other, _name), do: IO.inspect(other)

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

LiveThreadManagement.main(System.argv())
