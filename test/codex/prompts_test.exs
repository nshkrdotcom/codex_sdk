defmodule Codex.PromptsTest do
  use ExUnit.Case, async: true

  alias Codex.Prompts

  setup do
    tmp = Path.join(System.tmp_dir!(), "codex_prompts_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)

    on_exit(fn -> File.rm_rf(tmp) end)

    {:ok, tmp: tmp}
  end

  test "list returns empty when directory is missing" do
    missing =
      Path.join(System.tmp_dir!(), "codex_prompts_missing_#{System.unique_integer([:positive])}")

    assert {:ok, []} = Prompts.list(dir: missing)
  end

  test "list discovers markdown prompts and parses frontmatter", %{tmp: tmp} do
    File.write!(Path.join(tmp, "b.md"), "b")

    File.write!(
      Path.join(tmp, "a.md"),
      "---\n" <>
        "description: \"Quick review\"\n" <>
        "argument-hint: FILE=<path>\n" <>
        "---\n" <>
        "Review $FILE\n"
    )

    File.write!(Path.join(tmp, "skip.txt"), "ignored")

    assert {:ok, prompts} = Prompts.list(dir: tmp)
    assert Enum.map(prompts, & &1.name) == ["a", "b"]

    prompt = Enum.find(prompts, &(&1.name == "a"))
    assert prompt.description == "Quick review"
    assert prompt.argument_hint == "FILE=<path>"
    assert prompt.content == "Review $FILE\n"
  end

  test "list skips invalid utf-8 files", %{tmp: tmp} do
    File.write!(Path.join(tmp, "good.md"), "ok")
    File.write!(Path.join(tmp, "bad.md"), <<0xFF, 0xFE, 0x0A>>)

    assert {:ok, prompts} = Prompts.list(dir: tmp)
    assert Enum.map(prompts, & &1.name) == ["good"]
  end

  test "expand replaces named placeholders" do
    prompt = %{name: "ticket", content: "Review $USER on $BRANCH"}

    assert {:ok, "Review Alice on main"} =
             Prompts.expand(prompt, "USER=Alice BRANCH=main")
  end

  test "expand accepts quoted values" do
    prompt = %{name: "ticket", content: "Pair $USER with $BRANCH"}

    assert {:ok, "Pair Alice Smith with dev-main"} =
             Prompts.expand(prompt, "USER=\"Alice Smith\" BRANCH=dev-main")
  end

  test "expand reports invalid args for named placeholders" do
    prompt = %{name: "ticket", content: "Review $USER"}

    assert {:error, %{type: :invalid_args, message: message}} =
             Prompts.expand(prompt, "USER=Alice stray")

    assert message =~ "expected key=value"
  end

  test "expand reports missing required args" do
    prompt = %{name: "ticket", content: "Review $USER on $BRANCH"}

    assert {:error, %{type: :missing_args, missing: missing}} =
             Prompts.expand(prompt, "USER=Alice")

    assert "BRANCH" in missing
  end

  test "expand replaces numeric placeholders" do
    prompt = %{name: "review", content: "First: $1 Args: $ARGUMENTS Ninth: $9"}

    assert {:ok, "First: one Args: one two Ninth: "} =
             Prompts.expand(prompt, "one two")
  end

  test "expand preserves literal double dollars" do
    prompt = %{name: "price", content: "Cost: $$ and first: $1"}

    assert {:ok, "Cost: $$ and first: 9"} = Prompts.expand(prompt, ["9"])
  end
end
