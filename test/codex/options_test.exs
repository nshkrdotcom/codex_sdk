defmodule Codex.OptionsTest do
  use ExUnit.Case, async: true

  alias Codex.Options

  describe "new/1" do
    test "builds options from map" do
      {:ok, opts} =
        Options.new(%{
          api_key: "test",
          base_url: "https://example.com",
          telemetry_prefix: [:codex, :test]
        })

      assert opts.api_key == "test"
      assert opts.base_url == "https://example.com"
      assert opts.telemetry_prefix == [:codex, :test]
    end

    test "requires API key" do
      assert {:error, :missing_api_key} = Options.new(%{})
    end
  end
end
