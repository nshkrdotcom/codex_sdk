defmodule Codex.Exec.OptionsTest do
  use ExUnit.Case, async: true

  alias CliSubprocessCore.ExecutionSurface
  alias Codex.Exec.Options, as: ExecOptions
  alias Codex.Options

  test "inherits execution_surface from codex options by default" do
    {:ok, codex_opts} =
      Options.new(%{
        execution_surface: [
          surface_kind: :ssh_exec,
          transport_options: [destination: "exec-options.test.example", port: 2222]
        ]
      })

    assert {:ok, %ExecOptions{execution_surface: %ExecutionSurface{} = execution_surface}} =
             ExecOptions.new(%{codex_opts: codex_opts})

    assert execution_surface.surface_kind == :ssh_exec
    assert execution_surface.transport_options[:destination] == "exec-options.test.example"
  end

  test "accepts explicit execution_surface overrides" do
    {:ok, codex_opts} = Options.new(%{})

    assert {:ok, %ExecOptions{execution_surface: %ExecutionSurface{} = execution_surface}} =
             ExecOptions.new(%{
               codex_opts: codex_opts,
               execution_surface: [
                 surface_kind: :ssh_exec,
                 transport_options: [destination: "override.test.example"]
               ]
             })

    assert execution_surface.surface_kind == :ssh_exec
    assert execution_surface.transport_options[:destination] == "override.test.example"
  end
end
