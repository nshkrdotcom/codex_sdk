Mix.Task.run("app.start")

alias Codex.{AppServer, Items, Models, Options, Thread}
alias Codex.Protocol.CollaborationMode

defmodule LiveCollaborationModes do
  @moduledoc false

  @default_prompt """
  Give a 3-step plan for testing a CSV parser.
  Do not run commands, inspect files, or modify anything.
  """
  @preferred_modes [:plan, :pair_programming, :code, :default, :execute, :custom]

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

    with {:ok, codex_opts} <-
           Options.new(%{codex_path_override: codex_path, reasoning_effort: :low}),
         {:ok, conn, experimental_api?, fallback_reason} <-
           connect_for_collaboration_modes(codex_opts) do
      try do
        IO.puts("collaboration_mode/list:")

        if not experimental_api? do
          IO.puts("""
          experimentalApi initialize fallback:
            #{format_connect_reason(fallback_reason)}
          Reconnected without experimental app-server fields; this run will skip if the connected
          build still does not advertise `collaborationMode/list`.
          """)
        end

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
    {model, model_note} = resolve_selected_model(selected_mode)
    {effort, effort_note} = resolve_selected_effort(selected_mode, model)

    mode = %CollaborationMode{
      mode: selected_mode.mode,
      model: model,
      reasoning_effort: effort,
      developer_instructions: nil
    }

    IO.puts("""
    Using server-advertised collaboration preset:
      mode: #{mode.mode}
      model: #{mode.model}#{model_note}
      reasoning_effort: #{mode.reasoning_effort || "none"}#{effort_note}
      developer_instructions: built-in preset instructions (`settings.developer_instructions = null`)
    """)

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
        developer_instructions: built-in preset instructions
        final_response: #{format_final_response(result.final_response)}
      """)

      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp choose_mode(available_modes) when is_list(available_modes) do
    case Enum.find(@preferred_modes, fn preferred ->
           Enum.any?(available_modes, &(&1.mode == preferred))
         end) do
      nil ->
        {:skip, "no supported collaboration mode was advertised by this Codex build"}

      mode ->
        {:ok, Enum.find(available_modes, &(&1.mode == mode))}
    end
  end

  defp choose_mode(_), do: {:skip, "unable to determine supported collaboration modes"}

  defp extract_mode_atoms(%{"data" => data}) when is_list(data), do: normalize_mode_entries(data)
  defp extract_mode_atoms(%{data: data}) when is_list(data), do: normalize_mode_entries(data)
  defp extract_mode_atoms(_), do: []

  defp normalize_mode_entries(entries) do
    entries
    |> Enum.map(&normalize_mode_entry/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(& &1.mode)
  end

  defp normalize_mode_entry(entry) when is_binary(entry) do
    case normalize_mode_value(entry) do
      nil -> nil
      mode -> %{mode: mode, model: nil, reasoning_effort: nil}
    end
  end

  defp normalize_mode_entry(%{} = entry) do
    with mode when not is_nil(mode) <- normalize_mode_from_entry(entry) do
      %{
        mode: mode,
        model: extract_mode_model(entry),
        reasoning_effort: extract_mode_effort(entry)
      }
    end
  end

  defp normalize_mode_entry(_), do: nil

  defp normalize_mode_from_entry(entry) do
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
    |> Enum.find(& &1)
  end

  defp extract_mode_model(entry) do
    Map.get(entry, "model") ||
      Map.get(entry, :model) ||
      get_in(entry, ["settings", "model"]) ||
      get_in(entry, [:settings, :model])
  end

  defp extract_mode_effort(entry) do
    entry
    |> List.wrap()
    |> then(fn _ ->
      Map.get(entry, "reasoning_effort") ||
        Map.get(entry, :reasoning_effort) ||
        Map.get(entry, "reasoningEffort") ||
        Map.get(entry, :reasoningEffort) ||
        get_in(entry, ["settings", "reasoning_effort"]) ||
        get_in(entry, ["settings", "reasoningEffort"]) ||
        get_in(entry, [:settings, :reasoning_effort]) ||
        get_in(entry, [:settings, :reasoningEffort])
    end)
    |> normalize_effort_value()
  end

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

  defp normalize_effort_value(nil), do: nil

  defp normalize_effort_value(value) when is_atom(value) do
    case Models.normalize_reasoning_effort(value) do
      {:ok, effort} -> effort
      _ -> nil
    end
  end

  defp normalize_effort_value(value) when is_binary(value) do
    case Models.normalize_reasoning_effort(value) do
      {:ok, effort} -> effort
      _ -> nil
    end
  end

  defp normalize_effort_value(_), do: nil

  defp resolve_selected_model(selected_mode) do
    case selected_mode.model do
      model when is_binary(model) and model != "" ->
        {model, " (advertised by the server preset)"}

      _ ->
        {Models.default_model(), " (server omitted model; using the SDK default)"}
    end
  end

  defp resolve_selected_effort(selected_mode, model) do
    case selected_mode.reasoning_effort do
      effort when not is_nil(effort) ->
        note =
          if effort == :low do
            " (advertised by the server preset)"
          else
            " (advertised by the server preset; this intentionally overrides the global :low default)"
          end

        {effort, note}

      _ ->
        effort = Models.coerce_reasoning_effort(model, :low)

        note =
          if effort == :low do
            " (server omitted effort; using the global default)"
          else
            " (server omitted effort; using the model-coerced form of the global :low default)"
          end

        {effort, note}
    end
  end

  defp unsupported_capability?(message) do
    lowered = String.downcase(message)

    String.contains?(lowered, "experimentalapi") or
      String.contains?(lowered, "requires experimentalapi capability") or
      String.contains?(lowered, "method not found")
  end

  defp connect_for_collaboration_modes(codex_opts) do
    experimental_opts = [init_timeout_ms: 30_000, experimental_api: true]

    case AppServer.connect(codex_opts, experimental_opts) do
      {:ok, conn} ->
        {:ok, conn, true, nil}

      {:error, {:init_failed, reason}} ->
        if experimental_api_rejected?(reason) do
          case AppServer.connect(codex_opts, init_timeout_ms: 30_000) do
            {:ok, conn} ->
              {:ok, conn, false, reason}

            {:error, retry_reason} ->
              {:error, {:experimental_api_init_failed, reason, retry_reason}}
          end
        else
          {:error, {:init_failed, reason}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp experimental_api_rejected?(%{} = reason) do
    message =
      reason
      |> Map.get("message", Map.get(reason, :message, ""))
      |> to_string()
      |> String.downcase()

    String.contains?(message, "experimentalapi") or
      String.contains?(message, "experimental api") or
      (String.contains?(message, "capabilities") and
         (String.contains?(message, "unknown field") or
            String.contains?(message, "unexpected field") or
            String.contains?(message, "invalid params")))
  end

  defp experimental_api_rejected?(_reason), do: false

  defp format_connect_reason(%{} = reason) do
    reason
    |> Map.take(["code", "message"])
    |> inspect()
  end

  defp format_connect_reason(reason), do: inspect(reason)

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

  defp format_final_response(nil), do: "(no final assistant message returned)"
  defp format_final_response(response), do: extract_text(response)
end

LiveCollaborationModes.main(System.argv())
