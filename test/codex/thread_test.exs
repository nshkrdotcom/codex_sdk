defmodule Codex.ThreadTest do
  use ExUnit.Case, async: true

  alias Codex.Thread.Options, as: ThreadOptions
  alias Codex.{Options, Thread}

  describe "run/3" do
    test "returns turn result and updates thread metadata" do
      codex_path = fixture_script_path("thread_basic.jsonl")

      {:ok, codex_opts} =
        Options.new(%{
          api_key: "test",
          codex_path_override: codex_path
        })

      {:ok, thread_opts} = ThreadOptions.new(%{})
      thread = Thread.build(codex_opts, thread_opts)

      {:ok, result} = Thread.run(thread, "Hello Codex")

      assert result.thread.thread_id == "thread_abc123"
      assert result.final_response == %{"type" => "text", "text" => "Hello from Python Codex!"}

      assert result.usage == %{
               "input_tokens" => 12,
               "cached_input_tokens" => 0,
               "output_tokens" => 9,
               "total_tokens" => 21
             }

      assert length(result.events) == 5
    end
  end

  describe "run_streamed/3" do
    test "lazy stream yields events" do
      codex_path = fixture_script_path("thread_basic.jsonl")

      {:ok, codex_opts} =
        Options.new(%{
          api_key: "test",
          codex_path_override: codex_path
        })

      {:ok, thread_opts} = ThreadOptions.new(%{})
      thread = Thread.build(codex_opts, thread_opts)

      {:ok, stream} = Thread.run_streamed(thread, "Hello")

      assert is_function(stream, 2)
      events = Enum.to_list(stream)
      assert length(events) == 5
      assert Enum.any?(events, &(&1["type"] == "turn.completed"))
    end
  end

  defp fixture_script_path(fixture_name) do
    path = Path.join([File.cwd!(), "integration", "fixtures", "python", fixture_name])

    script = """
    #!/usr/bin/env bash
    cat "#{path}"
    """

    tmp_path = Path.join(System.tmp_dir!(), "mock_codex_#{System.unique_integer([:positive])}")
    File.write!(tmp_path, script)
    File.chmod!(tmp_path, 0o755)
    on_exit(fn -> File.rm_rf(tmp_path) end)
    tmp_path
  end
end
