defmodule Codex.RuntimeExecRenderTest do
  use ExUnit.Case, async: true

  alias Codex.{Exec, Options, Runtime, Thread}

  test "renders Codex-native exec flags without resolving or spawning the CLI" do
    {:ok, codex_opts} =
      Options.new(%{
        api_key: "test-key",
        base_url: "https://api.openai.com/v1",
        model: "gpt-5.5",
        execution_surface: [
          surface_kind: :local_subprocess,
          observability: %{suite: :promotion_path}
        ]
      })

    {:ok, thread_opts} =
      Thread.Options.new(%{
        sandbox: :read_only,
        additional_directories: ["/tmp/docs"],
        skip_git_repo_check: true,
        working_directory: "/tmp/work"
      })

    thread = Thread.build(codex_opts, thread_opts)

    {:ok, exec_opts} =
      Exec.Options.new(%{
        codex_opts: codex_opts,
        thread: thread,
        env: %{"CODEX_TEST_RENDER" => "1"},
        clear_env?: true,
        output_schema_path: "schema.json"
      })

    {:ok, render} = Runtime.Exec.render_for_test(exec_opts: exec_opts, input: "hello")

    assert render.provider == :codex
    assert render.stdin == "hello"
    assert render.execution_surface.observability == %{suite: :promotion_path}
    assert render.env["CODEX_TEST_RENDER"] == "1"
    assert render.clear_env? == true
    assert render.provider_native.sandbox == :read_only
    assert render.provider_native.additional_directories == ["/tmp/docs"]
    assert render.provider_native.skip_git_repo_check == true
    assert render.provider_native.output_schema == "schema.json"

    args = render.args
    assert Enum.take(args, 2) == ["exec", "--json"]
    assert flag_value(args, "--model") == "gpt-5.5"
    assert flag_value(args, "--sandbox") == "read-only"
    assert flag_value(args, "--cd") == "/tmp/work"
    assert repeated_values(args, "--add-dir") == ["/tmp/docs"]
    assert "--skip-git-repo-check" in args
    assert flag_value(args, "--output-schema") == "schema.json"
  end

  defp flag_value(args, flag) do
    case Enum.find_index(args, &(&1 == flag)) do
      nil -> nil
      idx -> Enum.at(args, idx + 1)
    end
  end

  defp repeated_values(args, flag) do
    args
    |> Enum.with_index()
    |> Enum.filter(fn {value, _index} -> value == flag end)
    |> Enum.map(fn {_value, index} -> Enum.at(args, index + 1) end)
  end
end
