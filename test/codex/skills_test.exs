defmodule Codex.SkillsTest do
  use ExUnit.Case, async: true

  alias Codex.Skills

  defmodule FakeAppServer do
    def skills_list(_conn, _opts) do
      {:ok, %{"data" => [%{"skills" => []}]}}
    end
  end

  setup do
    tmp = Path.join(System.tmp_dir!(), "codex_skills_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)

    on_exit(fn -> File.rm_rf(tmp) end)

    {:ok, tmp: tmp}
  end

  test "list returns error when skills are disabled" do
    assert {:error, :skills_disabled} = Skills.list(self(), skills_enabled: false)
  end

  test "list delegates to app-server when enabled" do
    assert {:ok, %{"data" => [%{"skills" => []}]}} =
             Skills.list(self(), skills_enabled: true, app_server: FakeAppServer)
  end

  test "load reads skill content when enabled", %{tmp: tmp} do
    path = Path.join(tmp, "SKILL.md")
    File.write!(path, "Skill body")

    assert {:ok, "Skill body"} = Skills.load(path, skills_enabled: true)
  end

  test "load returns error when path is missing" do
    assert {:error, :missing_path} = Skills.load(%{}, skills_enabled: true)
  end

  test "load returns error when skills are disabled", %{tmp: tmp} do
    path = Path.join(tmp, "SKILL.md")
    File.write!(path, "Skill body")

    assert {:error, :skills_disabled} = Skills.load(path, skills_enabled: false)
  end
end
