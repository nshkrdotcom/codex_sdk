defmodule Codex.ModelsTest do
  use ExUnit.Case, async: true

  alias Codex.Models

  test "exposes supported models with defaults and tool flags" do
    models = Models.list()

    assert Enum.any?(models, fn
             %{id: "gpt-5.1-codex-max", default_reasoning_effort: :medium, tool_enabled?: true} ->
               true

             _ ->
               false
           end)

    assert Enum.any?(models, fn
             %{id: "gpt-5.1-codex", default_reasoning_effort: :medium, tool_enabled?: true} ->
               true

             _ ->
               false
           end)

    assert Enum.any?(models, fn
             %{id: "gpt-5.1-codex-mini", default_reasoning_effort: :medium, tool_enabled?: true} ->
               true

             _ ->
               false
           end)

    assert Enum.any?(models, fn
             %{id: "gpt-5.1", default_reasoning_effort: :medium, tool_enabled?: tool_enabled?} ->
               tool_enabled? == false

             _ ->
               false
           end)
  end

  test "returns default model and reasoning effort" do
    assert Models.default_model() == "gpt-5.1-codex-max"
    assert Models.default_reasoning_effort() == :medium
    assert Models.default_reasoning_effort("gpt-5.1-codex-mini") == :medium
  end

  test "honors OPENAI_DEFAULT_MODEL override" do
    original = System.get_env("OPENAI_DEFAULT_MODEL")
    System.put_env("OPENAI_DEFAULT_MODEL", "custom-model")

    try do
      assert Models.default_model() == "custom-model"
    after
      if original,
        do: System.put_env("OPENAI_DEFAULT_MODEL", original),
        else: System.delete_env("OPENAI_DEFAULT_MODEL")
    end
  end

  test "identifies tool-enabled models" do
    assert Models.tool_enabled?("gpt-5.1-codex-max")
    assert Models.tool_enabled?("gpt-5.1-codex-mini")
    refute Models.tool_enabled?("gpt-5.1")
  end
end
