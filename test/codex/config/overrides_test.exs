defmodule Codex.Config.OverridesTest do
  use ExUnit.Case, async: false

  alias Codex.Config.Overrides
  alias Codex.Options
  alias Codex.Thread.Options, as: ThreadOptions

  test "merge_config does not intern atoms from untrusted provider ids" do
    provider_id = fresh_missing_key("provider")
    override_key = "model_providers.#{provider_id}.request_max_retries"
    refute atom_exists?(override_key)

    thread_opts = %ThreadOptions{model_provider: provider_id, request_max_retries: 3}

    merged = Overrides.merge_config(%{}, %Options{}, thread_opts)

    assert merged[override_key] == 3
    refute atom_exists?(provider_id)
    refute atom_exists?(override_key)
  end

  test "merge_config applies options-level config overrides when missing" do
    {:ok, codex_opts} =
      Options.new(%{
        config: %{"sandbox_workspace_write" => %{"network_access" => true}}
      })

    merged = Overrides.merge_config(%{}, codex_opts, %ThreadOptions{})

    assert merged["sandbox_workspace_write.network_access"] == true
  end

  test "merge_config preserves derived precedence over options-level config overrides" do
    {:ok, codex_opts} =
      Options.new(%{
        model_personality: :pragmatic,
        config: %{"model_personality" => "friendly"}
      })

    merged = Overrides.merge_config(%{}, codex_opts, %ThreadOptions{})

    assert merged["model_personality"] == "pragmatic"
  end

  describe "flatten_config_map/1" do
    test "flattens nested maps to dotted key tuples" do
      input = %{
        "model" => %{
          "personality" => "friendly",
          "context_window" => 8192
        },
        "features" => %{
          "web_search_request" => true
        }
      }

      result = Overrides.flatten_config_map(input)

      assert {"model.personality", "friendly"} in result
      assert {"model.context_window", 8192} in result
      assert {"features.web_search_request", true} in result
    end

    test "passes through flat key-value pairs without change" do
      input = %{"model_personality" => "friendly", "timeout" => 5000}
      result = Overrides.flatten_config_map(input)

      assert {"model_personality", "friendly"} in result
      assert {"timeout", 5000} in result
    end

    test "handles deeply nested maps" do
      input = %{
        "a" => %{
          "b" => %{
            "c" => 42
          }
        }
      }

      result = Overrides.flatten_config_map(input)
      assert [{"a.b.c", 42}] == result
    end

    test "handles atom keys by converting to strings" do
      input = %{model: %{personality: "friendly"}}
      result = Overrides.flatten_config_map(input)
      assert {"model.personality", "friendly"} in result
    end

    test "returns empty list for empty map" do
      assert [] == Overrides.flatten_config_map(%{})
    end

    test "returns empty list for nil" do
      assert [] == Overrides.flatten_config_map(nil)
    end
  end

  describe "normalize_config_overrides/1 with nested maps" do
    test "thread options accept nested config override maps and flatten them" do
      {:ok, opts} =
        Codex.Thread.Options.new(%{
          config_overrides: %{
            "model" => %{
              "personality" => "friendly"
            },
            "timeout" => 5000
          }
        })

      # Should be flattened to dotted-path tuples
      assert {"model.personality", "friendly"} in opts.config_overrides
      assert {"timeout", 5000} in opts.config_overrides
    end
  end

  describe "normalize_config_overrides/1 value validation" do
    test "accepts valid nested values" do
      assert {:ok, normalized} =
               Overrides.normalize_config_overrides(%{
                 "sandbox_workspace_write" => %{
                   "network_access" => true,
                   "writable_roots" => ["/tmp"]
                 }
               })

      assert {"sandbox_workspace_write.network_access", true} in normalized
      assert {"sandbox_workspace_write.writable_roots", ["/tmp"]} in normalized
    end

    test "rejects nil value" do
      assert {:error, {:invalid_config_override_value, "features.web_search_request", nil}} =
               Overrides.normalize_config_overrides(%{
                 "features" => %{"web_search_request" => nil}
               })
    end

    test "rejects unsupported value type" do
      assert {:error, {:invalid_config_override_value, "retry_budget", {:tuple, 1}}} =
               Overrides.normalize_config_overrides(%{"retry_budget" => {:tuple, 1}})
    end
  end

  defp unique_key(prefix) do
    suffix = :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
    "#{prefix}_#{suffix}"
  end

  defp fresh_missing_key(prefix) do
    key = unique_key(prefix)

    if atom_exists?(key) do
      fresh_missing_key(prefix)
    else
      key
    end
  end

  defp atom_exists?(key) do
    _ = String.to_existing_atom(key)
    true
  rescue
    ArgumentError -> false
  end
end
