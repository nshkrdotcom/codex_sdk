#!/usr/bin/env mix run

# SDK-direct Codex promotion-path verifier.
#
# Usage:
#   mix run examples/promotion_path/sdk_direct_codex.exs -- \
#     --model gpt-5.4 \
#     --prompt "Reply with exactly: codex sdk direct ok"
#
# Optional:
#   --codex-path /path/to/codex
#   --cwd /path/to/workdir

defmodule CodexPromotionPath.Direct do
  @moduledoc false

  alias Codex.Items

  @switches [
    codex_path: :string,
    cwd: :string,
    model: :string,
    prompt: :string
  ]

  def main(argv) do
    {opts, args, invalid} = OptionParser.parse(argv, strict: @switches)
    reject_invalid!(invalid)

    model = required!(opts, :model)
    prompt = Keyword.get(opts, :prompt) || Enum.join(args, " ")
    prompt = if String.trim(prompt) == "", do: "Reply with exactly: codex sdk direct ok", else: prompt

    with {:ok, codex_opts} <-
           Codex.Options.new(%{
             model: model,
             codex_path_override: Keyword.get(opts, :codex_path),
             execution_surface: [
               surface_kind: :local_subprocess,
               observability: %{suite: :promotion_path, lane: :sdk_direct, provider: :codex}
             ]
           }),
         {:ok, thread_opts} <-
           Codex.Thread.Options.new(%{
             sandbox: :read_only,
             skip_git_repo_check: true,
             working_directory: Keyword.get(opts, :cwd)
           }),
         {:ok, thread} <- Codex.start_thread(codex_opts, thread_opts),
         {:ok, result} <- Codex.Thread.run(thread, prompt) do
      IO.puts(render_response(result.final_response))
    else
      {:error, reason} ->
        IO.puts(:stderr, "Codex SDK-direct example failed: #{inspect(reason)}")
        System.halt(1)
    end
  end

  defp render_response(%Items.AgentMessage{text: text}) when is_binary(text), do: text
  defp render_response(%{"text" => text}) when is_binary(text), do: text
  defp render_response(other), do: inspect(other)

  defp reject_invalid!([]), do: :ok

  defp reject_invalid!(invalid) do
    raise ArgumentError, "invalid options: #{inspect(invalid)}"
  end

  defp required!(opts, key) do
    case Keyword.get(opts, key) do
      value when is_binary(value) ->
        if String.trim(value) == "" do
          missing_required!(key)
        else
          value
        end

      _ ->
        missing_required!(key)
    end
  end

  defp missing_required!(key) do
    IO.puts(:stderr, "Missing required --#{String.replace(to_string(key), "_", "-")}.")
    System.halt(64)
  end
end

CodexPromotionPath.Direct.main(System.argv())
