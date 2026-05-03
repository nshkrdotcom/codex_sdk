defmodule Codex.ExecReasoningEffortTest do
  use ExUnit.Case, async: false

  alias Codex.{Options, Thread}
  alias Codex.TestSupport.FixtureScripts
  alias Codex.Thread.Options, as: ThreadOptions

  test "uses the resolved model payload reasoning effort" do
    codex_home = Path.join(System.tmp_dir!(), "codex_home_#{System.unique_integer([:positive])}")
    File.mkdir_p!(codex_home)
    File.write!(Path.join(codex_home, "config.toml"), "model_reasoning_effort = \"xhigh\"\n")

    previous_home = System.get_env("CODEX_HOME")
    System.put_env("CODEX_HOME", codex_home)

    on_exit(fn ->
      case previous_home do
        nil -> System.delete_env("CODEX_HOME")
        value -> System.put_env("CODEX_HOME", value)
      end

      File.rm_rf(codex_home)
    end)

    capture_path =
      Path.join(
        System.tmp_dir!(),
        "codex_exec_effort_args_#{System.unique_integer([:positive])}"
      )

    script_path =
      "thread_basic.jsonl"
      |> FixtureScripts.capture_args(capture_path)
      |> tap(fn path ->
        on_exit(fn ->
          File.rm_rf(path)
          File.rm_rf(capture_path)
        end)
      end)

    {:ok, codex_opts} =
      Options.new(%{
        api_key: "test",
        codex_path_override: script_path,
        model: "gpt-5.4-mini",
        reasoning_effort: :medium
      })

    {:ok, thread_opts} = ThreadOptions.new(%{})
    thread = Thread.build(codex_opts, thread_opts)

    assert {:ok, _} = Thread.run(thread, "config effort")

    configs =
      capture_path
      |> File.read!()
      |> String.trim()
      |> Codex.StringScan.split_ascii_whitespace()
      |> flag_values("--config")

    assert ~s(model_reasoning_effort="medium") in configs
  end

  defp flag_values(args, flag) do
    args
    |> Enum.with_index()
    |> Enum.filter(fn {value, _idx} -> value == flag end)
    |> Enum.map(fn {_value, idx} -> Enum.at(args, idx + 1) end)
  end
end
