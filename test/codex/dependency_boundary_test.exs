defmodule Codex.DependencyBoundaryTest do
  use ExUnit.Case, async: true

  @repo_root Path.expand("../..", __DIR__)

  @forbidden_deps [
    :agent_session_manager,
    :gemini_cli_sdk,
    :claude_agent_sdk,
    :amp_sdk,
    :inference
  ]

  test "codex_sdk does not declare ASM or sibling SDK deps" do
    assert_forbidden_deps_absent(Mix.Project.config()[:deps], @forbidden_deps)
  end

  test "publish mode resolves the released CLI core dependency" do
    assert [{:cli_subprocess_core, "~> 0.2.0"}] =
             DependencySources.deps(@repo_root, publish?: true)
  end

  test "release coordinates match the 0.17.0 package contract" do
    project = Mix.Project.config()

    assert project[:version] == "0.17.0"
    assert project[:elixir] == "~> 1.19"
  end

  test "provider package does not expose raw execution plane modules" do
    execution_plane_references =
      @repo_root
      |> Path.join("lib/**/*.ex")
      |> Path.wildcard()
      |> Enum.filter(fn path ->
        path
        |> File.read!()
        |> String.contains?("ExecutionPlane")
      end)

    assert execution_plane_references == []
  end

  defp assert_forbidden_deps_absent(deps, forbidden_deps) when is_list(deps) do
    declared = MapSet.new(Enum.map(deps, &dep_name/1))

    Enum.each(forbidden_deps, fn dep ->
      refute MapSet.member?(declared, dep),
             "codex_sdk must not declare dependency on #{inspect(dep)}"
    end)
  end

  defp dep_name({name, _requirement}), do: name
  defp dep_name({name, _requirement, _opts}), do: name
end
