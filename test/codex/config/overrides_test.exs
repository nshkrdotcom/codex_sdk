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
