defmodule Codex.Config.OptionNormalizersTest do
  use ExUnit.Case, async: true

  alias Codex.Config.OptionNormalizers

  describe "normalize_reasoning_summary/2" do
    test "normalizes supported values" do
      assert {:ok, "auto"} = OptionNormalizers.normalize_reasoning_summary(:auto)
      assert {:ok, "concise"} = OptionNormalizers.normalize_reasoning_summary("  CONCISE  ")
      assert {:ok, nil} = OptionNormalizers.normalize_reasoning_summary(" ")
    end

    test "returns tagged error for unsupported values" do
      assert {:error, {:invalid_model_reasoning_summary, "loud"}} =
               OptionNormalizers.normalize_reasoning_summary("loud")

      assert {:error, {:invalid_reasoning_summary, "loud"}} =
               OptionNormalizers.normalize_reasoning_summary("loud", :invalid_reasoning_summary)
    end
  end

  describe "normalize_model_verbosity/2" do
    test "normalizes supported values" do
      assert {:ok, "low"} = OptionNormalizers.normalize_model_verbosity(:low)
      assert {:ok, "high"} = OptionNormalizers.normalize_model_verbosity(" HIGH ")
      assert {:ok, nil} = OptionNormalizers.normalize_model_verbosity(" ")
    end

    test "returns tagged error for unsupported values" do
      assert {:error, {:invalid_model_verbosity, "extreme"}} =
               OptionNormalizers.normalize_model_verbosity("extreme")

      assert {:error, {:invalid_verbosity, "extreme"}} =
               OptionNormalizers.normalize_model_verbosity("extreme", :invalid_verbosity)
    end
  end

  describe "normalize_history_persistence/2" do
    test "normalizes supported values" do
      assert {:ok, nil} = OptionNormalizers.normalize_history_persistence(nil)
      assert {:ok, "local"} = OptionNormalizers.normalize_history_persistence(:local)
      assert {:ok, "remote"} = OptionNormalizers.normalize_history_persistence(" remote ")
      assert {:ok, nil} = OptionNormalizers.normalize_history_persistence(" ")
    end

    test "returns tagged error for unsupported values" do
      assert {:error, {:invalid_history_persistence, 123}} =
               OptionNormalizers.normalize_history_persistence(123)

      assert {:error, {:invalid_persistence, 123}} =
               OptionNormalizers.normalize_history_persistence(123, :invalid_persistence)
    end
  end
end
