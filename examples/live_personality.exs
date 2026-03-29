Mix.Task.run("app.start")

Code.require_file(Path.expand("support/example_helper.exs", __DIR__))

alias CodexExamples.Support

Support.init!()

alias Codex.{AppServer, Items, Options, Thread}

defmodule LivePersonality do
  @moduledoc false

  @default_prompt "Describe this repository in one paragraph."

  def main(argv) do
    prompt = parse_prompt(argv)

    case Support.ensure_remote_working_directory() do
      :ok ->
        :ok

      {:skip, reason} ->
        IO.puts("SKIPPED: #{reason}")
        System.halt(0)
    end

    codex_opts = Support.codex_options!()
    :ok = Support.ensure_app_server_supported(codex_opts)
    {:ok, conn} = AppServer.connect(codex_opts, init_timeout_ms: 30_000)

    try do
      {:ok, thread} =
        Codex.start_thread(
          codex_opts,
          Support.thread_opts!(%{
            transport: {:app_server, conn},
            working_directory: Support.example_working_directory(),
            personality: :friendly
          })
        )

      {friendly, thread} = run_turn(thread, prompt, %{timeout_ms: 120_000})

      {pragmatic, thread} =
        run_turn(thread, prompt, %{personality: :pragmatic, timeout_ms: 120_000})

      {none_resp, _thread} =
        run_turn(thread, prompt, %{personality: :none, timeout_ms: 120_000})

      IO.puts("""
      Friendly response:
      #{friendly}

      Pragmatic response:
      #{pragmatic}

      None (:none personality) response:
      #{none_resp}
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

  defp extract_text(%Items.AgentMessage{text: text}) when is_binary(text), do: text
  defp extract_text(%{"type" => "text", "text" => text}) when is_binary(text), do: text
  defp extract_text(%{type: "text", text: text}) when is_binary(text), do: text
  defp extract_text(other) when is_binary(other), do: other
  defp extract_text(other), do: inspect(other)
end

LivePersonality.main(System.argv())
