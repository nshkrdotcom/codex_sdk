defmodule Codex.ErrorTest do
  use ExUnit.Case, async: true

  alias Codex.Thread.Options, as: ThreadOptions
  alias Codex.{Options, Thread, TransportError}

  test "non-zero codex exit returns transport error" do
    script_body = """
    #!/usr/bin/env bash
    exit 21
    """

    script_path = temp_script(script_body)
    on_exit(fn -> File.rm_rf(script_path) end)

    {:ok, codex_opts} =
      Options.new(%{api_key: "test", codex_path_override: script_path})

    {:ok, thread_opts} = ThreadOptions.new(%{})
    thread = Thread.build(codex_opts, thread_opts)

    assert {:error, %TransportError{exit_status: 21}} = Thread.run(thread, "failure test")
  end

  defp temp_script(contents) do
    path = Path.join(System.tmp_dir!(), "codex_error_#{System.unique_integer([:positive])}")
    File.write!(path, contents)
    File.chmod!(path, 0o755)
    path
  end
end
