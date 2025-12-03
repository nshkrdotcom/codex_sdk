# Covers ADR-012 (attachments, structured file outputs, file_search)
Mix.Task.run("app.start")

alias Codex.{Agent, AgentRunner, FileSearch, RunConfig, Tools}
alias Codex.Items.AgentMessage
alias Codex.ToolOutput

defmodule CodexExamples.AttachmentEchoTool do
  @moduledoc false
  use Codex.Tool, name: "attachment_echo", description: "Returns staged attachments"

  @impl true
  def invoke(_args, %{metadata: %{attachment: attachment}}) do
    {:ok,
     [
       attachment,
       attachment,
       ToolOutput.file(%{
         data: Base.encode64("inline file payload"),
         filename: "inline.txt",
         mime_type: "text/plain"
       })
     ]}
  end
end

defmodule CodexExamples.LiveAttachmentsAndSearch do
  @moduledoc false

  def main(argv) do
    prompt =
      case argv do
        [] ->
          "Call attachment_echo once and file_search for 'docs parity'. Return a tiny summary."

        values ->
          Enum.join(values, " ")
      end

    {:ok, attachment} = stage_demo_attachment()

    Tools.reset!()

    {:ok, _} =
      Tools.register(CodexExamples.AttachmentEchoTool,
        metadata: %{attachment: attachment}
      )

    {:ok, _} =
      Tools.register(Codex.Tools.FileSearchTool,
        name: "file_search",
        metadata: file_search_metadata()
      )

    {:ok, file_search} =
      FileSearch.new(%{
        vector_store_ids: ["docs-store"],
        filters: %{"tag" => "parity"},
        include_search_results: true
      })

    {:ok, agent} =
      Agent.new(%{
        name: "AttachmentAgent",
        instructions:
          "Use attachment_echo to return the staged files (dedupe outputs) and call file_search once with the provided filters. Keep the final summary short.",
        tools: ["attachment_echo", "file_search"],
        reset_tool_choice: true
      })

    {:ok, run_config} =
      RunConfig.new(%{
        max_turns: 2,
        file_search: file_search
      })

    {:ok, codex_opts} =
      Codex.Options.new(%{
        codex_path_override: fetch_codex_path!()
      })

    {:ok, thread_opts} =
      Codex.Thread.Options.new(%{
        attachments: [attachment],
        file_search: file_search
      })

    {:ok, thread} = Codex.start_thread(codex_opts, thread_opts)

    IO.puts("""
    Attachments + search demo (live Codex CLI)
      Prompt: #{prompt}
      Staged attachment: #{attachment.name} (#{attachment.size} bytes)
      File search: #{inspect(file_search)}
    """)

    case AgentRunner.run(thread, prompt, %{agent: agent, run_config: run_config}) do
      {:ok, result} ->
        print_outputs(result.raw[:tool_outputs] || [])
        IO.puts("Usage: #{inspect(result.thread.usage || %{})}")
        IO.puts("Final response: #{render_response(result.final_response)}")

      {:error, reason} ->
        Mix.raise("Run failed: #{inspect(reason)}")
    end
  end

  defp stage_demo_attachment do
    path = Path.join(System.tmp_dir!(), "codex_demo_attachment.txt")
    File.write!(path, "codex attachments demo")
    Codex.Files.stage(path, name: "demo_attachment.txt")
  end

  defp file_search_metadata do
    %{
      searcher: fn args, _context, _metadata ->
        {:ok,
         %{
           "query" => Map.get(args, "query"),
           "results" => [
             %{"title" => "vector hit", "score" => 0.88, "filters" => args["filters"]}
           ]
         }}
      end
    }
  end

  defp print_outputs(outputs) do
    outputs
    |> List.wrap()
    |> Enum.each(fn output ->
      IO.puts("Structured output: #{inspect(output)}")
    end)
  end

  defp render_response(%AgentMessage{text: text}), do: text
  defp render_response(%{"text" => text}), do: text
  defp render_response(nil), do: "<no response>"
  defp render_response(other), do: inspect(other)

  defp fetch_codex_path! do
    System.get_env("CODEX_PATH") ||
      System.find_executable("codex") ||
      Mix.raise("""
      Unable to locate the `codex` CLI.
      Install the Codex CLI and ensure it is on your PATH or set CODEX_PATH.
      """)
  end
end

CodexExamples.LiveAttachmentsAndSearch.main(System.argv())
