defmodule Codex.Tools.ShellCommandToolTest do
  use ExUnit.Case, async: false

  alias Codex.Tool
  alias Codex.Tools
  alias Codex.Tools.ShellCommandTool

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
      meta = ShellCommandTool.metadata()
      assert meta.name == "shell_command"
      assert meta.description == "Execute shell scripts"
      assert meta.schema["required"] == ["command"]
      assert meta.schema["properties"]["command"]["type"] == "string"
      assert meta.schema["properties"]["workdir"]["type"] == "string"
      assert meta.schema["properties"]["login"]["type"] == "boolean"
      assert meta.schema["properties"]["timeout_ms"]["type"] == "integer"
    end

    test "Tool.metadata/1 returns module metadata" do
      assert Tool.metadata(ShellCommandTool)[:name] == "shell_command"
    end
  end

  describe "invoke/2 with custom executor" do
    test "passes normalized command and context" do
      parent = self()

      approval = fn cmd, _ctx ->
        send(parent, {:approved_command, cmd})
        :ok
      end

      executor = fn _args, ctx, _meta ->
        send(parent, {:executor_context, ctx})
        {:ok, %{"output" => "ok", "exit_code" => 0}}
      end

      {:ok, _} = Tools.register(ShellCommandTool, executor: executor, approval: approval)

      assert {:ok, result} =
               Tools.invoke(
                 "shell_command",
                 %{"command" => ["echo", "hello"], "workdir" => "/tmp", "login" => false},
                 %{}
               )

      assert result["success"] == true
      assert_receive {:approved_command, "echo hello"}
      assert_receive {:executor_context, ctx}
      assert ctx.cwd == "/tmp"
      assert ctx.login == false
    end

    test "rejects missing command" do
      assert {:error, {:invalid_argument, :command}} = ShellCommandTool.invoke(%{}, %{})
    end
  end
end
