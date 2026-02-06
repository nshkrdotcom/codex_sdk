defmodule Codex.Config.BaseURLTest do
  use ExUnit.Case, async: false

  alias Codex.Config.BaseURL

  setup do
    original = System.get_env("OPENAI_BASE_URL")

    on_exit(fn ->
      case original do
        nil -> System.delete_env("OPENAI_BASE_URL")
        value -> System.put_env("OPENAI_BASE_URL", value)
      end
    end)

    :ok
  end

  test "resolve/1 prefers explicit option over env" do
    System.put_env("OPENAI_BASE_URL", "https://env.example.com/v1")

    assert BaseURL.resolve(%{base_url: "https://explicit.example.com/v1"}) ==
             "https://explicit.example.com/v1"
  end

  test "resolve/1 falls back to env" do
    System.put_env("OPENAI_BASE_URL", "https://env.example.com/v1")
    assert BaseURL.resolve(%{}) == "https://env.example.com/v1"
  end

  test "resolve/1 falls back to default" do
    System.delete_env("OPENAI_BASE_URL")
    assert BaseURL.resolve(%{}) == BaseURL.default()
  end
end
