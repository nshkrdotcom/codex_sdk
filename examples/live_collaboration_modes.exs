Mix.Task.run("app.start")

alias Codex.{AppServer, Items, Models, Options, Thread}
alias Codex.Protocol.CollaborationMode

defmodule LiveCollaborationModes do
  @moduledoc false

  @default_prompt "Give a 3-step plan to add coverage for the core modules."
  @preferred_modes [:pair_programming, :code, :default, :plan, :execute, :custom]

  def main(argv) do
    case run(argv) do
      :ok ->
        :ok

      {:skip, reason} ->
        IO.puts("SKIPPED: #{reason}")

      {:error, reason} ->
        IO.puts("Failed to run collaboration mode example: #{inspect(reason)}")
        System.halt(1)
    end
  end

  defp run(argv) do
    prompt = parse_prompt(argv)
    codex_path = fetch_codex_path!()
    ensure_app_server_supported!(codex_path)

    with {:ok, codex_opts} <- Options.new(%{codex_path_override: codex_path}),
         {:ok, conn} <- AppServer.connect(codex_opts, init_timeout_ms: 30_000) do
      try do
        IO.puts("collaboration_mode/list:")

        with {:ok, available_modes} <- list_supported_modes(conn),
             {:ok, selected_mode} <- choose_mode(available_modes) do
          run_turn(codex_opts, conn, prompt, selected_mode)
        end
      after
        :ok = AppServer.disconnect(conn)
      end
    end
  end

  defp list_supported_modes(conn) do
    case AppServer.collaboration_mode_list(conn) do
      {:ok, response} ->
        IO.inspect(response)
        {:ok, extract_mode_atoms(response)}

      {:error, %{"code" => -32600, "message" => message}} when is_binary(message) ->
        if unsupported_capability?(message) do
          {:skip,
           "collaborationMode/list requires experimental API support in this Codex CLI build"}
        else
          {:error, {:collaboration_mode_list_failed, message}}
        end

      {:error, reason} ->
        {:error, {:collaboration_mode_list_failed, reason}}
    end
  end

  defp run_turn(codex_opts, conn, prompt, selected_mode) do
    model = Models.default_model()
    effort = Models.default_reasoning_effort(model)

    mode = %CollaborationMode{
      mode: selected_mode,
      model: model,
      reasoning_effort: effort,
      developer_instructions: "Keep output brief and practical."
    }

    with {:ok, thread} <-
           Codex.start_thread(codex_opts, %{
             transport: {:app_server, conn},
             working_directory: File.cwd!()
           }),
         {:ok, result} <-
           Thread.run(thread, prompt, %{collaboration_mode: mode, timeout_ms: 120_000}) do
      IO.puts("""
      Turn completed with collaboration_mode=#{mode.mode}.
        model: #{mode.model}
        reasoning_effort: #{mode.reasoning_effort || "none"}
        final_response: #{extract_text(result.final_response)}
      """)

      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp choose_mode(available_modes) when is_list(available_modes) do
    case Enum.find(@preferred_modes, &(&1 in available_modes)) do
      nil ->
        {:skip, "no supported collaboration mode was advertised by this Codex build"}

      mode ->
        {:ok, mode}
    end
  end

  defp choose_mode(_), do: {:skip, "unable to determine supported collaboration modes"}

  defp extract_mode_atoms(%{"data" => data}) when is_list(data), do: normalize_mode_entries(data)
  defp extract_mode_atoms(%{data: data}) when is_list(data), do: normalize_mode_entries(data)
  defp extract_mode_atoms(_), do: []

  defp normalize_mode_entries(entries) do
    entries
    |> Enum.flat_map(&normalize_mode_entry/1)
    |> Enum.uniq()
  end

  defp normalize_mode_entry(entry) when is_binary(entry) do
    case normalize_mode_value(entry) do
      nil -> []
      mode -> [mode]
    end
  end

  defp normalize_mode_entry(%{} = entry) do
    [
      Map.get(entry, "mode"),
      Map.get(entry, :mode),
      Map.get(entry, "id"),
      Map.get(entry, :id),
      Map.get(entry, "name"),
      Map.get(entry, :name),
      get_in(entry, ["preset", "mode"]),
      get_in(entry, [:preset, :mode])
    ]
    |> Enum.map(&normalize_mode_value/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_mode_entry(_), do: []

  defp normalize_mode_value(value) when is_atom(value),
    do: normalize_mode_value(Atom.to_string(value))

  defp normalize_mode_value(value) when is_binary(value) do
    case String.downcase(String.trim(value)) do
      "pair_programming" -> :pair_programming
      "pairprogramming" -> :pair_programming
      "pair-programming" -> :pair_programming
      "code" -> :code
      "default" -> :default
      "plan" -> :plan
      "execute" -> :execute
      "custom" -> :custom
      _ -> nil
    end
  end

  defp normalize_mode_value(_), do: nil

  defp unsupported_capability?(message) do
    lowered = String.downcase(message)

    String.contains?(lowered, "experimentalapi") or
      String.contains?(lowered, "requires experimentalapi capability") or
      String.contains?(lowered, "method not found")
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
