defmodule Codex.ForbiddenTokensTest do
  use ExUnit.Case, async: true

  @project_root Path.expand("../..", __DIR__)
  @legacy_backend Enum.join(["erl", "exec"])
  @paths [
    "lib",
    "test",
    "README.md",
    "guides",
    "docs"
  ]

  test "shared CLI surfaces do not mention the legacy backend token" do
    Enum.each(expanded_files(), fn path ->
      if path != __ENV__.file do
        refute File.read!(path) =~ @legacy_backend,
               "unexpected legacy backend token in #{Path.relative_to(path, @project_root)}"
      end
    end)
  end

  defp expanded_files do
    @paths
    |> Enum.flat_map(fn relative ->
      full_path = Path.join(@project_root, relative)

      cond do
        File.regular?(full_path) ->
          [full_path]

        File.dir?(full_path) ->
          Path.wildcard(Path.join(full_path, "**/*"))
          |> Enum.filter(&File.regular?/1)

        true ->
          []
      end
    end)
  end
end
