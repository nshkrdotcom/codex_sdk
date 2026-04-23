Mix.Task.run("app.start")

Code.require_file(Path.expand("support/example_helper.exs", __DIR__))

alias CodexExamples.Support

Support.init!()

alias Codex.Items.AgentMessage

defmodule CodexExamples.LiveAppServerBasic do
  @moduledoc false

  @default_prompt "Reply with exactly ok and nothing else."

  def main(argv) do
    case run(argv) do
      :ok ->
        :ok

      {:skip, reason} ->
        IO.puts("SKIPPED: #{reason}")
    end
  end

  defp run(argv) do
    prompt =
      case argv do
        [] -> @default_prompt
        values -> Enum.join(values, " ")
      end

    with {:ok, codex_opts} <- Support.codex_options(%{}, missing_cli: :skip),
         :ok <- Support.ensure_auth_available(),
         :ok <- Support.ensure_app_server_supported(codex_opts),
         :ok <- Support.ensure_remote_working_directory(),
         {:ok, conn} <- Codex.AppServer.connect(codex_opts, init_timeout_ms: 30_000) do
      try do
        personality = :friendly

        {:ok, thread} =
          Codex.start_thread(
            codex_opts,
            Support.thread_opts!(%{
              transport: {:app_server, conn},
              working_directory: Support.example_working_directory(),
              personality: personality
            })
          )

        {:ok, result} = Codex.Thread.run(thread, prompt, %{timeout_ms: 120_000})

        IO.puts("""
        App-server turn completed.
          personality: #{personality}
          thread_id: #{inspect(result.thread.thread_id)}
          final_response: #{extract_text(result.final_response)}
        """)

        IO.puts("""
        approvals_reviewer note:
          set `approvals_reviewer: :user`, `:auto_review`, or `:guardian_subagent` on `Codex.start_thread/2`
          and create the connection with `experimental_api: true` when you want upstream guardian
          review routing on newer app-server builds.
        """)

        IO.puts("\nskills/list:")

        skills_opts =
          case Support.example_working_directory() do
            cwd when is_binary(cwd) and cwd != "" -> [cwds: [cwd]]
            _ -> []
          end

        skills_result = Codex.AppServer.skills_list(conn, skills_opts)

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

        IO.puts("""

        Additional app-server demos:
          mix run examples/live_app_server_filesystem.exs
          mix run examples/live_app_server_plugins.exs
        """)

        :ok
      after
        :ok = Codex.AppServer.disconnect(conn)
      end
    end
  end

  defp extract_text(%AgentMessage{text: text}) when is_binary(text), do: text
  defp extract_text(%{"type" => "text", "text" => text}) when is_binary(text), do: text
  defp extract_text(%{type: "text", text: text}) when is_binary(text), do: text
  defp extract_text(other) when is_binary(other), do: other
  defp extract_text(other), do: inspect(other)
end

CodexExamples.LiveAppServerBasic.main(System.argv())
