defmodule Codex.Integration.AttachmentPipelineTest do
  use ExUnit.Case, async: false

  alias Codex.Thread.Options, as: ThreadOptions
  alias Codex.TestSupport.FixtureScripts
  alias Codex.{Files, Options, Thread}

  @moduletag :integration

  setup do
    Files.reset!()
    on_exit(fn -> Files.reset!() end)
  end

  test "staged attachments are forwarded to codex executable" do
    source = tmp_file!("doc.txt", "attachment body")

    {:ok, attachment} = Files.stage(source)
    {:ok, thread_opts} = ThreadOptions.new(%{})
    thread_opts = Files.attach(thread_opts, attachment)

    capture_path =
      Path.join(System.tmp_dir!(), "codex_exec_args_#{System.unique_integer([:positive])}.txt")

    script_path =
      FixtureScripts.capture_args("thread_basic.jsonl", capture_path)
      |> tap(&on_exit(fn -> File.rm_rf(&1) end))

    on_exit(fn -> File.rm_rf(capture_path) end)

    {:ok, codex_opts} =
      Options.new(%{api_key: "test", codex_path_override: script_path})

    thread = Thread.build(codex_opts, thread_opts)

    {:ok, _result} = Thread.run(thread, "Hello")

    args = capture_path |> File.read!() |> String.trim()

    assert String.contains?(args, "--attachment")
    assert String.contains?(args, attachment.path)
    assert String.contains?(args, attachment.checksum)
  end

  defp tmp_file!(name, contents) do
    dir = Path.join(System.tmp_dir!(), "codex_attach_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    path = Path.join(dir, name)
    File.write!(path, contents)
    path
  end
end
