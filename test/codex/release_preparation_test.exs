defmodule Codex.ReleasePreparationTest do
  use ExUnit.Case, async: true

  @repo_root Path.expand("../..", __DIR__)

  test "package and HexDocs expose only public release presentation files" do
    project = Mix.Project.config()
    package_files = project[:package][:files]

    assert project[:version] == "0.22.0"
    assert project[:docs][:source_ref] == "v0.22.0"
    assert project[:docs][:homepage_url] == "https://hexdocs.pm/codex_sdk"
    assert project[:docs][:assets] == %{"assets" => "assets"}
    assert project[:docs][:logo] == "assets/codex_sdk.svg"

    for required <-
          ~w(lib assets guides examples mix.exs README.md LICENSE CHANGELOG.md VERSION) do
      assert required in package_files
    end

    extras = Enum.map(project[:docs][:extras], fn {path, _opts} -> to_string(path) end)

    assert Enum.sort(extras -- ~w(README.md CHANGELOG.md LICENSE)) ==
             Enum.sort(Path.wildcard("guides/[0-9]*.md"))

    assert ~w(README.md CHANGELOG.md LICENSE) -- extras == []
    assert project[:docs][:api_reference] == false
    refute project[:docs][:filter_modules].(Codex, %{})
    refute Enum.any?(package_files, &(&1 == "docs" or String.starts_with?(&1, "docs/")))

    refute "build_support" in package_files

    assert project[:package][:links]["License"] ==
             "https://github.com/nshkrdotcom/codex_sdk/blob/main/LICENSE"

    refute ".formatter.exs" in package_files
  end

  test "README has the centered 200px logo and GitHub and MIT badges" do
    readme = File.read!(Path.join(@repo_root, "README.md"))
    header = readme |> String.split("\n") |> Enum.take(20) |> Enum.join("\n")

    assert header =~ ~s(src="assets/codex_sdk.svg")
    assert header =~ ~s(width="200")
    assert header =~ ~s(href="https://github.com/nshkrdotcom/codex_sdk")
    assert header =~ ~s(href="https://github.com/nshkrdotcom/codex_sdk/blob/main/LICENSE")
    assert length(String.split(header, "img.shields.io")) - 1 == 2
  end
end
