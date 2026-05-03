defmodule Codex.LiveAppServerTest do
  use ExUnit.Case, async: false

  alias CliSubprocessCore.CommandSpec
  alias Codex.Items
  alias Codex.Options
  alias Codex.RunResultStreaming

  @moduletag :live
  @moduletag timeout: 120_000

  @live_enabled System.get_env("CODEX_TEST_LIVE")
                |> to_string()
                |> String.downcase()
                |> then(&(&1 in ["1", "true", "yes"]))

  if not @live_enabled do
    @moduletag skip:
                 "Live tests are opt-in. Run with CODEX_TEST_LIVE=true mix test --only live --include live (requires codex CLI + auth)."
  end

  setup_all do
    if @live_enabled do
      ensure_real_app_server_available()
    else
      :ok
    end
  end

  test "live: app-server transport executes against real CLI" do
    prompt = "Reply with exactly ok and nothing else."

    assert {:ok, codex_opts} = fetch_codex_options()
    assert {:ok, conn} = Codex.AppServer.connect(codex_opts, init_timeout_ms: 30_000)
    on_exit(fn -> Codex.AppServer.disconnect(conn) end)

    assert {:ok, thread} =
             Codex.start_thread(codex_opts, %{transport: {:app_server, conn}})

    assert {:ok, result} = Codex.Thread.run(thread, prompt, %{timeout_ms: 120_000})

    assert text = extract_text(result.final_response)
    assert normalized_ok?(text)
  end

  test "live: app-server streaming yields a turn completion" do
    prompt = "Reply with exactly ok and nothing else."

    assert {:ok, codex_opts} = fetch_codex_options()
    assert {:ok, conn} = Codex.AppServer.connect(codex_opts, init_timeout_ms: 30_000)
    on_exit(fn -> Codex.AppServer.disconnect(conn) end)

    assert {:ok, thread} =
             Codex.start_thread(codex_opts, %{transport: {:app_server, conn}})

    assert {:ok, stream_result} =
             Codex.Thread.run_streamed(thread, prompt, %{timeout_ms: 120_000})

    events =
      stream_result
      |> RunResultStreaming.raw_events()
      |> Enum.to_list()

    assert Enum.any?(events, &match?(%Codex.Events.TurnCompleted{}, &1))
  end

  defp ensure_real_app_server_available do
    with {:ok, codex_opts} <- resolve_codex_options(),
         {:ok, spec} <- Options.codex_command_spec(codex_opts),
         :ok <- reject_fixture_script(spec),
         :ok <- ensure_app_server_supported(spec) do
      verify_codex_version(spec)
    else
      {:error, reason} -> raise reason
    end
  end

  defp resolve_codex_options do
    with {:ok, codex_opts} <- Options.new(%{}),
         {:ok, _spec} <- Options.codex_command_spec(codex_opts) do
      {:ok, codex_opts}
    else
      {:error, :codex_binary_not_found} ->
        {:error, "Unable to locate the `codex` CLI. Install it or set CODEX_PATH."}

      {:error, reason} ->
        {:error, "Unable to resolve a runnable `codex` CLI: #{inspect(reason)}"}
    end
  end

  defp fetch_codex_options do
    case resolve_codex_options() do
      {:ok, codex_opts} -> {:ok, codex_opts}
      {:error, reason} -> raise reason
    end
  end

  defp reject_fixture_script(%CommandSpec{program: program} = _spec) do
    if fixture_script?(program) do
      {:error,
       "Resolved `codex` CLI to a fixture script at #{inspect(program)}. Unset CODEX_PATH and ensure a real codex binary is on PATH."}
    else
      :ok
    end
  end

  defp ensure_app_server_supported(%CommandSpec{} = spec) do
    {_output, status} = run_command_spec(spec, ["app-server", "--help"])

    if status == 0 do
      :ok
    else
      {:error,
       "`codex app-server` is not available. Upgrade via `npm install -g @openai/codex` and retry."}
    end
  end

  defp verify_codex_version(%CommandSpec{} = spec) do
    {output, status} = run_command_spec(spec, ["--version"])

    cond do
      status != 0 ->
        {:error,
         "Unable to run `codex --version` via #{inspect(spec.program)} (exit #{status}): #{inspect(output)}"}

      String.contains?(output, "codex") ->
        :ok

      true ->
        {:error,
         "Unexpected `codex --version` output from #{inspect(spec.program)}: #{inspect(output)}"}
    end
  end

  defp fixture_script?(path) when is_binary(path) do
    String.starts_with?(Path.basename(path), "mock_codex_")
  end

  defp run_command_spec(%CommandSpec{} = spec, args) when is_list(args) do
    System.cmd(spec.program, CommandSpec.command_args(spec, args), stderr_to_stdout: true)
  end

  defp extract_text(%Items.AgentMessage{text: text}) when is_binary(text), do: text
  defp extract_text(%{"type" => "text", "text" => text}) when is_binary(text), do: text
  defp extract_text(%{type: "text", text: text}) when is_binary(text), do: text
  defp extract_text(other) when is_binary(other), do: other
  defp extract_text(other), do: inspect(other)

  defp normalized_ok?(text) when is_binary(text) do
    text
    |> String.trim()
    |> String.trim("\"")
    |> String.trim_trailing(".")
    |> String.trim_trailing("!")
    |> String.downcase()
    |> Kernel.==("ok")
  end

  defp normalized_ok?(_text), do: false
end
