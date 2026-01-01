defmodule Codex.Tools.WriteStdinToolTest do
  use ExUnit.Case, async: false

  alias Codex.Options
  alias Codex.Thread
  alias Codex.Thread.Options, as: ThreadOptions
  alias Codex.Tool
  alias Codex.Tools
  alias Codex.Tools.WriteStdinTool

  setup do
    Tools.reset!()
    Tools.reset_metrics()

    on_exit(fn ->
      Tools.reset!()
      Tools.reset_metrics()
    end)

    :ok
  end

  describe "metadata/0" do
    test "returns valid tool metadata" do
      meta = WriteStdinTool.metadata()
      assert meta.name == "write_stdin"
      assert meta.schema["required"] == ["session_id"]
      assert meta.schema["properties"]["session_id"]["type"] == "integer"
      assert meta.schema["properties"]["chars"]["type"] == "string"
      assert meta.schema["properties"]["yield_time_ms"]["type"] == "integer"
      assert meta.schema["properties"]["max_output_tokens"]["type"] == "integer"
    end

    test "Tool.metadata/1 returns module metadata" do
      assert Tool.metadata(WriteStdinTool)[:name] == "write_stdin"
    end
  end

  describe "enablement gating" do
    test "disabled without app_server transport" do
      {:ok, _} = Tools.register(WriteStdinTool, executor: fn _, _, _ -> {:ok, %{}} end)

      assert {:error, {:tool_disabled, "write_stdin"}} =
               Tools.invoke("write_stdin", %{"session_id" => 1}, %{})
    end
  end

  describe "invoke/2 with custom executor" do
    test "invokes executor when enabled" do
      parent = self()

      executor = fn args, _ctx, _meta ->
        send(parent, {:write_called, args})
        {:ok, %{"ok" => true}}
      end

      {:ok, _} = Tools.register(WriteStdinTool, executor: executor)

      {:ok, thread_opts} = ThreadOptions.new(%{transport: {:app_server, self()}})
      {:ok, codex_opts} = Options.new(%{api_key: "test"})
      thread = Thread.build(codex_opts, thread_opts)

      assert {:ok, %{"ok" => true}} =
               Tools.invoke(
                 "write_stdin",
                 %{"session_id" => 123, "chars" => "hi"},
                 %{thread: thread}
               )

      assert_receive {:write_called, %{"session_id" => 123, "chars" => "hi"}}
    end

    test "requires session_id" do
      {:ok, _} = Tools.register(WriteStdinTool, executor: fn _, _, _ -> {:ok, %{}} end)

      {:ok, thread_opts} = ThreadOptions.new(%{transport: {:app_server, self()}})
      {:ok, codex_opts} = Options.new(%{api_key: "test"})
      thread = Thread.build(codex_opts, thread_opts)

      assert {:error, {:missing_argument, :session_id}} =
               Tools.invoke("write_stdin", %{}, %{thread: thread})
    end
  end
end
