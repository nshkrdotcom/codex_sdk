defmodule CodexSdkTest do
  use ExUnit.Case, async: true

  test "delegates start_thread/2 to Codex module" do
    codex_path = System.find_executable("cat") || "/bin/cat"

    assert {:ok, %Codex.Thread{} = thread} =
             CodexSdk.start_thread(%{api_key: "test", codex_path_override: codex_path})

    assert thread.codex_opts.api_key == "test"
  end
end
