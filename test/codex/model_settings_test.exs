defmodule Codex.ModelSettingsTest do
  use ExUnit.Case, async: true

  alias Codex.ModelSettings
  alias Codex.RunConfig

  test "builds and merges model settings with validation" do
    assert {:ok, settings} =
             ModelSettings.new(%{
               temperature: 0.7,
               top_p: 0.9,
               max_tokens: 256,
               provider: :responses
             })

    assert settings.temperature == 0.7
    assert settings.top_p == 0.9
    assert settings.max_tokens == 256

    assert {:ok, merged} = ModelSettings.merge(settings, %{max_tokens: 512, tool_choice: "auto"})
    assert merged.max_tokens == 512
    assert merged.tool_choice == "auto"
    assert merged.temperature == 0.7

    assert {:error, {:invalid_temperature, _}} = ModelSettings.new(%{temperature: 3.5})
  end

  test "RunConfig converts model_settings map into struct" do
    assert {:ok, %RunConfig{model_settings: %ModelSettings{} = settings}} =
             RunConfig.new(%{model_settings: %{temperature: 0.1, provider: "chat"}})

    assert settings.provider == :chat
  end
end
