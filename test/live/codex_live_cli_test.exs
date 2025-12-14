defmodule Codex.LiveCLITest do
  use ExUnit.Case, async: false

  alias Codex.Items
  alias Codex.RunResultStreaming

  @moduletag :live
  @moduletag timeout: 120_000

  setup do
    if live_enabled?() do
      ensure_real_codex_available()
    else
      {:skip,
       "Live tests are opt-in. Run with CODEX_TEST_LIVE=true mix test --only live --include live (requires codex CLI + auth)."}
    end
  end

  test "live: Codex.Thread.run executes against real CLI" do
    prompt = "Reply with exactly ok and nothing else."

    assert {:ok, thread} = Codex.start_thread(%{})
    assert {:ok, result} = Codex.Thread.run(thread, prompt, %{timeout_ms: 120_000})

    assert text = extract_text(result.final_response)
    assert normalized_ok?(text)
  end

  test "live: Codex.Thread.run_streamed yields a turn completion" do
    prompt = "Reply with exactly ok and nothing else."

    assert {:ok, thread} = Codex.start_thread(%{})

    assert {:ok, stream_result} =
             Codex.Thread.run_streamed(thread, prompt, %{timeout_ms: 120_000})

    events =
      stream_result
      |> RunResultStreaming.raw_events()
      |> Enum.to_list()

    assert Enum.any?(events, &match?(%Codex.Events.TurnCompleted{}, &1))
  end

  defp live_enabled? do
    System.get_env("CODEX_TEST_LIVE")
    |> to_string()
    |> String.downcase()
    |> then(&(&1 in ["1", "true", "yes"]))
  end

  defp ensure_real_codex_available do
    with {:ok, path} <- resolve_codex_path(),
         :ok <- reject_fixture_script(path) do
      verify_codex_version(path)
    end
  end

  defp resolve_codex_path do
    case System.get_env("CODEX_PATH") || System.find_executable("codex") do
      path when is_binary(path) and path != "" ->
        {:ok, path}

      _ ->
        {:skip, "Unable to locate the `codex` CLI. Install it or set CODEX_PATH."}
    end
  end

  defp reject_fixture_script(path) when is_binary(path) do
    if fixture_script?(path) do
      {:skip,
       "Resolved `codex` CLI to a fixture script at #{inspect(path)}. Unset CODEX_PATH and ensure a real codex binary is on PATH."}
    else
      :ok
    end
  end

  defp verify_codex_version(path) when is_binary(path) do
    {output, status} = System.cmd(path, ["--version"], stderr_to_stdout: true)

    cond do
      status != 0 ->
        {:skip,
         "Unable to run `codex --version` via #{inspect(path)} (exit #{status}): #{inspect(output)}"}

      String.contains?(output, "codex") ->
        :ok

      true ->
        {:skip, "Unexpected `codex --version` output from #{inspect(path)}: #{inspect(output)}"}
    end
  end

  defp fixture_script?(path) when is_binary(path) do
    String.starts_with?(Path.basename(path), "mock_codex_")
  end

  defp extract_text(%Items.AgentMessage{text: text}) when is_binary(text), do: text
  defp extract_text(%{"type" => "text", "text" => text}) when is_binary(text), do: text
  defp extract_text(%{type: "text", text: text}) when is_binary(text), do: text
  defp extract_text(other) when is_binary(other), do: other
  defp extract_text(other), do: inspect(other)

  defp normalized_ok?(text) when is_binary(text) do
    String.trim(text) =~ ~r/\A\"?ok[.!]?\"?\z/i
  end

  defp normalized_ok?(_text), do: false
end
