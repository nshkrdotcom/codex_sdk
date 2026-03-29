Mix.Task.run("app.start")

Code.require_file(Path.expand("support/example_helper.exs", __DIR__))

alias CodexExamples.Support

Support.init!()

alias Codex.{AppServer, Items, Options, Thread}
alias Codex.Models

defmodule LiveThreadManagement do
  @moduledoc false

  @default_prompt "Say hello in one sentence."

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
            working_directory: Support.example_working_directory()
          })
        )

      {:ok, result} = Thread.run(thread, prompt, %{timeout_ms: 120_000})
      thread_id = result.thread.thread_id

      IO.puts("""
      Thread started: #{inspect(thread_id)}
      Final response: #{extract_text(result.final_response)}
      """)

      IO.puts("thread/read:")
      IO.inspect(AppServer.thread_read(conn, thread_id, include_turns: true))

      IO.puts("\nthread/fork:")

      fork_params =
        %{}
        |> maybe_put(:model, codex_opts.model)
        |> maybe_put(:config, fork_config(codex_opts.reasoning_effort))

      print_result_or_warning(AppServer.thread_fork(conn, thread_id, fork_params), "thread/fork")

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

  defp fork_config(nil), do: nil

  defp fork_config(effort) do
    %{"model_reasoning_effort" => Models.reasoning_effort_to_string(effort)}
  end

  defp parse_prompt([prompt | _]), do: prompt
  defp parse_prompt(_argv), do: @default_prompt

  defp extract_text(%Items.AgentMessage{text: text}) when is_binary(text), do: text
  defp extract_text(%{"type" => "text", "text" => text}) when is_binary(text), do: text
  defp extract_text(%{type: "text", text: text}) when is_binary(text), do: text
  defp extract_text(other) when is_binary(other), do: other
  defp extract_text(other), do: inspect(other)

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end

LiveThreadManagement.main(System.argv())
