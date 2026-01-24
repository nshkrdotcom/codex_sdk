defmodule Codex.ErrorTest do
  use ExUnit.Case, async: true

  alias Codex.{Error, Options, Thread}
  alias Codex.Thread.Options, as: ThreadOptions

  test "non-zero codex exit normalizes into Codex.Error" do
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

    assert {:error, {:exec_failed, %Error{} = error}} = Thread.run(thread, "failure test")
    assert error.details[:exit_status] == 21
  end

  test "normalize/1 preserves additional error details" do
    payload = %{
      "message" => "stream failed",
      "additional_details" => "upstream timeout",
      "codex_error_info" => %{"code" => "rate_limit"}
    }

    error = Error.normalize(payload)

    assert error.message == "stream failed"
    assert error.details.additional_details == "upstream timeout"
    assert error.details.codex_error_info == %{"code" => "rate_limit"}
  end

  defp temp_script(contents) do
    path = Path.join(System.tmp_dir!(), "codex_error_#{System.unique_integer([:positive])}")
    File.write!(path, contents)
    File.chmod!(path, 0o755)
    path
  end
end
