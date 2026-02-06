defmodule Codex.Approvals.RegistryTest do
  use ExUnit.Case, async: false

  alias Codex.Approvals.Registry

  setup do
    # Keep global registry state deterministic across tests.
    _ = Registry.cleanup_expired(0)
    :ok
  end

  test "cleanup_expired/1 deletes only entries older than max_age" do
    old_ref = make_ref()
    fresh_ref = make_ref()

    assert :ok = Registry.register(old_ref, %{kind: :old})
    Process.sleep(5)
    assert :ok = Registry.register(fresh_ref, %{kind: :fresh})

    assert 1 == Registry.cleanup_expired(2)
    assert {:error, :not_found} = Registry.lookup(old_ref)
    assert {:ok, %{kind: :fresh}} = Registry.lookup(fresh_ref)
  end

  test "cleanup_expired/1 can prune large registries" do
    for _ <- 1..20_000 do
      assert :ok = Registry.register(make_ref(), %{})
    end

    deleted = Registry.cleanup_expired(0)
    assert deleted > 0
  end
end
