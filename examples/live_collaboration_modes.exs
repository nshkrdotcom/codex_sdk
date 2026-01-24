Mix.Task.run("app.start")

alias Codex.{AppServer, Items, Models, Options, Thread}
alias Codex.Protocol.CollaborationMode

defmodule LiveCollaborationModes do
  @moduledoc false

  @default_prompt "Give a 3-step plan to add coverage for the core modules."

  def main(argv) do
    prompt = parse_prompt(argv)

    codex_path = fetch_codex_path!()
    ensure_app_server_supported!(codex_path)

    {:ok, codex_opts} = Options.new(%{codex_path_override: codex_path})
    {:ok, conn} = AppServer.connect(codex_opts, init_timeout_ms: 30_000)

    try do
      IO.puts("collaboration_mode/list:")

      case AppServer.collaboration_mode_list(conn) do
        {:error, %{"code" => -32600, "message" => message}} ->
          IO.puts("""
          collaboration_mode/list is not supported by this codex app-server build.
          Upgrade your Codex CLI and retry.
          Raw error: #{message}
          """)

        other ->
          IO.inspect(other)
      end

      model = Models.default_model()
      effort = Models.default_reasoning_effort(model)

      mode = %CollaborationMode{
        mode: :pair_programming,
        model: model,
        reasoning_effort: effort,
        developer_instructions: "Keep output brief and practical."
      }

      {:ok, thread} =
        Codex.start_thread(codex_opts, %{
          transport: {:app_server, conn},
          working_directory: File.cwd!()
        })

      case Thread.run(thread, prompt, %{collaboration_mode: mode, timeout_ms: 120_000}) do
        {:ok, result} ->
          IO.puts("""
          Turn completed with collaboration_mode=#{mode.mode}.
            model: #{mode.model}
            reasoning_effort: #{mode.reasoning_effort || "none"}
            final_response: #{extract_text(result.final_response)}
          """)

        {:error, reason} ->
          IO.puts("Failed to run collaboration mode example: #{inspect(reason)}")
      end
    after
      :ok = AppServer.disconnect(conn)
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

LiveCollaborationModes.main(System.argv())
