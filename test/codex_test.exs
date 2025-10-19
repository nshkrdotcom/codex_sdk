defmodule CodexTest do
  use ExUnit.Case, async: true

  describe "start_thread/2" do
    test "returns thread struct with options" do
      assert {:ok, thread} =
               Codex.start_thread(%{
                 api_key: "test-key",
                 codex_path_override: System.find_executable("cat") || "/bin/cat"
               })

      assert thread.thread_id == nil
      assert thread.codex_opts.api_key == "test-key"
    end
  end

  describe "resume_thread/3" do
    test "restores thread id" do
      {:ok, thread} =
        Codex.resume_thread("thread_123", %{
          api_key: "test",
          codex_path_override: System.find_executable("cat") || "/bin/cat"
        })

      assert thread.thread_id == "thread_123"
    end
  end
end
