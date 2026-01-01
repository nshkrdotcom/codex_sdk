defmodule Codex.Tools.RegistryTest do
  use ExUnit.Case, async: false

  alias Codex.Tools
  alias Codex.Tools.ShellCommandTool
  alias Codex.Tools.ShellTool

  setup do
    Tools.reset!()
    Tools.reset_metrics()

    on_exit(fn ->
      Tools.reset!()
      Tools.reset_metrics()
    end)

    :ok
  end

  test "container.exec aliases to shell" do
    executor = fn _args, _ctx, _meta -> {:ok, %{"output" => "ok", "exit_code" => 0}} end
    {:ok, _} = Tools.register(ShellTool, executor: executor)

    assert {:ok, result} = Tools.invoke("container.exec", %{"command" => ["echo", "ok"]}, %{})
    assert result["success"] == true

    assert {:ok, info} = Tools.lookup("container.exec")
    assert info.module == ShellTool
    assert info.name == "shell"
  end

  test "shell_command aliases to shell when not registered" do
    executor = fn _args, _ctx, _meta -> {:ok, %{"output" => "ok", "exit_code" => 0}} end
    {:ok, _} = Tools.register(ShellTool, executor: executor)

    assert {:ok, result} = Tools.invoke("shell_command", %{"command" => ["echo", "ok"]}, %{})
    assert result["success"] == true
  end

  test "shell_command uses shell_command tool when registered" do
    executor = fn _args, _ctx, _meta -> {:ok, %{"output" => "ok", "exit_code" => 0}} end
    {:ok, _} = Tools.register(ShellCommandTool, executor: executor)

    assert {:ok, result} = Tools.invoke("shell_command", %{"command" => "echo ok"}, %{})
    assert result["success"] == true

    assert {:ok, info} = Tools.lookup("shell_command")
    assert info.module == ShellCommandTool
  end
end
