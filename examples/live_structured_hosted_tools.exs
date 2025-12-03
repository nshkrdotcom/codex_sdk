# Covers ADR-004, ADR-005, ADR-012 (function tools, hosted tools, structured outputs)
Mix.Task.run("app.start")

alias Codex.{Agent, AgentRunner, FileSearch, RunConfig, ToolOutput, Tools}
alias Codex.FunctionTool
alias Codex.Items.AgentMessage

defmodule CodexExamples.StructuredBundleTool do
  use FunctionTool,
    name: "structured_bundle",
    description: "Returns structured text, image, and file outputs for a topic",
    parameters: %{topic: :string},
    handler: fn %{"topic" => topic}, _ctx ->
      {:ok,
       [
         ToolOutput.text("Structured summary for #{topic}"),
         ToolOutput.image(%{
           url: "https://example.com/#{topic}.png",
           detail: "low"
         }),
         ToolOutput.file(%{
           data: Base.encode64("demo file payload for #{topic}"),
           filename: "#{topic}.txt",
           mime_type: "text/plain"
         })
       ]}
    end
end

defmodule CodexExamples.LiveStructuredHostedTools do
  @moduledoc false

  def main(argv) do
    prompt =
      case argv do
        [] ->
          "Call the structured_bundle tool for \"codex repo\", run one safe shell echo, and include the file_search context."

        values ->
          Enum.join(values, " ")
      end

    Tools.reset!()
    {:ok, _} = Tools.register(CodexExamples.StructuredBundleTool)

    {:ok, _} =
      Tools.register(Codex.Tools.ShellTool, name: "hosted_shell", metadata: shell_metadata())

    {:ok, _} =
      Tools.register(Codex.Tools.ApplyPatchTool,
        name: "apply_patch",
        metadata: apply_patch_metadata()
      )

    {:ok, _} =
      Tools.register(Codex.Tools.ComputerTool, name: "computer", metadata: computer_metadata())

    {:ok, _} =
      Tools.register(Codex.Tools.FileSearchTool,
        name: "file_search",
        metadata: file_search_metadata()
      )

    {:ok, _} =
      Tools.register(Codex.Tools.ImageGenerationTool,
        name: "image_generation",
        metadata: image_metadata()
      )

    {:ok, file_search} =
      FileSearch.new(%{
        vector_store_ids: ["demo-store"],
        filters: %{"source" => "docs"},
        include_search_results: true
      })

    {:ok, agent} =
      Agent.new(%{
        name: "StructuredHostAgent",
        instructions:
          "Use structured_bundle first. If you need a quick command output, call hosted_shell with a single echo. Mention file_search configuration briefly.",
        tools: [
          "structured_bundle",
          "hosted_shell",
          "apply_patch",
          "computer",
          "file_search",
          "image_generation"
        ],
        reset_tool_choice: true
      })

    {:ok, run_config} =
      RunConfig.new(%{
        max_turns: 3,
        file_search: file_search
      })

    {:ok, codex_opts} =
      Codex.Options.new(%{
        codex_path_override: fetch_codex_path!()
      })

    {:ok, thread_opts} =
      Codex.Thread.Options.new(%{
        file_search: file_search
      })

    {:ok, thread} = Codex.start_thread(codex_opts, thread_opts)

    IO.puts("""
    Running live structured/hosted tools demo.
      Prompt: #{prompt}
      File search: #{inspect(file_search)}
    """)

    case AgentRunner.run(thread, prompt, %{agent: agent, run_config: run_config}) do
      {:ok, result} ->
        print_tool_outputs(result.raw[:tool_outputs] || [])
        IO.puts("Usage: #{inspect(result.thread.usage || %{})}")
        IO.puts("Final response:\n#{render_response(result.final_response)}")

      {:error, reason} ->
        Mix.raise("Run failed: #{inspect(reason)}")
    end
  end

  defp print_tool_outputs(outputs) do
    outputs
    |> List.wrap()
    |> Enum.each(fn output ->
      IO.puts("Tool output: #{inspect(output)}")
    end)
  end

  defp render_response(%AgentMessage{text: text}), do: text
  defp render_response(%{"text" => text}), do: text
  defp render_response(nil), do: "<no response>"
  defp render_response(other), do: inspect(other)

  defp shell_metadata do
    %{
      executor: fn %{"command" => command}, _context ->
        {:ok, %{"command" => command, "stdout" => "simulated shell: #{command}"}}
      end,
      approval: fn %{"command" => command}, _context, _metadata ->
        if String.contains?(command, "rm"), do: {:deny, "blocked dangerous command"}, else: :allow
      end,
      max_output_bytes: 400
    }
  end

  defp apply_patch_metadata do
    %{
      editor: fn %{"patch" => patch}, _context ->
        {:ok, %{"applied" => String.slice(patch, 0, 60)}}
      end
    }
  end

  defp computer_metadata do
    %{
      safety: fn args, _context, _metadata ->
        action = Map.get(args, "action", "")

        if String.contains?(action, "destructive") do
          {:deny, "computer action blocked"}
        else
          :ok
        end
      end,
      executor: fn args, _context ->
        {:ok, %{"action" => Map.get(args, "action", "noop"), "status" => "simulated"}}
      end
    }
  end

  defp file_search_metadata do
    %{
      searcher: fn args, _context, _metadata ->
        {:ok,
         %{
           "query" => Map.get(args, "query"),
           "results" => [%{"title" => "demo result", "score" => 0.99}]
         }}
      end
    }
  end

  defp image_metadata do
    %{
      generator: fn args, _context, _metadata ->
        {:ok,
         %{"prompt" => Map.get(args, "prompt"), "url" => "https://example.com/generated.png"}}
      end
    }
  end

  defp fetch_codex_path! do
    System.get_env("CODEX_PATH") ||
      System.find_executable("codex") ||
      Mix.raise("""
      Unable to locate the `codex` CLI.
      Install the Codex CLI and ensure it is on your PATH or set CODEX_PATH.
      """)
  end
end

CodexExamples.LiveStructuredHostedTools.main(System.argv())
