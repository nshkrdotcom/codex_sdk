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
          "Give a tiny summary of this repository."

        values ->
          Enum.join(values, " ")
      end

    {:ok, attachment} = stage_demo_attachment()

    Tools.reset!()

    {:ok, _} =
      Tools.register(CodexExamples.AttachmentEchoTool,
        attachment: attachment
      )

    {:ok, _} =
      Codex.Tools.VectorStoreSearchTool
      |> Tools.register(Keyword.merge([name: "file_search"], file_search_options()))

    {:ok, file_search} =
      FileSearch.new(%{
        vector_store_ids: ["docs-store"],
        filters: %{"tag" => "parity"},
        include_search_results: true
      })

    {:ok, agent} =
      Agent.new(%{
        name: "AttachmentAgent",
        instructions: "Provide a short summary. Use hosted tools only if they are available.",
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
        tool_outputs = result.raw[:tool_outputs] || []
        print_outputs(tool_outputs)

        if tool_outputs == [] do
          demo_tool_invocations()
        end

        IO.puts("Usage: #{inspect(result.thread.usage || %{})}")
        IO.puts("Final response: #{render_response(result.final_response)}")

      {:error, reason} ->
        Mix.raise("Run failed: #{inspect(reason)}")
    end
  end

  defp stage_demo_attachment do
    path = Path.join(System.tmp_dir!(), "codex_demo_attachment.png")

    File.write!(
      path,
      Base.decode64!(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO3Z6xQAAAAASUVORK5CYII="
      )
    )

    Codex.Files.stage(path, name: "demo_attachment.png")
  end

  defp file_search_options do
    [
      searcher: fn args, _context, _metadata ->
        {:ok,
         %{
           "query" => Map.get(args, "query"),
           "results" => [
             %{"title" => "vector hit", "score" => 0.88, "filters" => args["filters"]}
           ]
         }}
      end
    ]
  end

  defp demo_tool_invocations do
    IO.puts("No tool calls observed; invoking tools locally.")

    case Tools.invoke("attachment_echo", %{}, %{}) do
      {:ok, output} -> IO.puts("attachment_echo output: #{inspect(output)}")
      {:error, reason} -> IO.puts("attachment_echo error: #{inspect(reason)}")
    end

    case Tools.invoke("file_search", %{"query" => "docs parity"}, %{}) do
      {:ok, output} -> IO.puts("file_search output: #{inspect(output)}")
      {:error, reason} -> IO.puts("file_search error: #{inspect(reason)}")
    end
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
