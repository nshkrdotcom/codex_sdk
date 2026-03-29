Mix.Task.run("app.start")

Code.require_file(Path.expand("support/example_helper.exs", __DIR__))

alias CodexExamples.Support

Support.init!()

defmodule CodexExamples.LiveCLIDemo do
  def main(argv) do
    question =
      case argv do
        [] -> "What is the capital of France?"
        values -> Enum.join(values, " ")
      end

    opts = Support.codex_options!()

    with {:ok, thread} <- Codex.start_thread(opts, Support.thread_opts!()),
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
end

CodexExamples.LiveCLIDemo.main(System.argv())
