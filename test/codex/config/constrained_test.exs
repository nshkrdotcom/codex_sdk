defmodule Codex.Config.ConstrainedTest do
  use ExUnit.Case, async: true

  alias Codex.Config.Constrained
  alias Codex.Config.ConstraintError

  describe "allow_any/1" do
    test "creates a constrained value that accepts any input" do
      constrained = Constrained.allow_any(:initial)
      assert constrained.value == :initial
      assert constrained.constraint == :any
    end

    test "can_set? returns true for any value" do
      constrained = Constrained.allow_any(:initial)
      assert Constrained.can_set?(constrained, :foo)
      assert Constrained.can_set?(constrained, :bar)
      assert Constrained.can_set?(constrained, "string")
      assert Constrained.can_set?(constrained, 123)
    end

    test "set/2 succeeds for any value" do
      constrained = Constrained.allow_any(:initial)
      assert {:ok, updated} = Constrained.set(constrained, :new_value)
      assert updated.value == :new_value
      assert updated.constraint == :any
    end
  end

  describe "allow_only/2" do
    test "creates a constrained value with allowed list" do
      constrained = Constrained.allow_only(:foo, [:foo, :bar, :baz])
      assert constrained.value == :foo
      assert constrained.constraint == {:only, [:foo, :bar, :baz]}
    end

    test "can_set? returns true for values in allowed list" do
      constrained = Constrained.allow_only(:foo, [:foo, :bar])
      assert Constrained.can_set?(constrained, :foo)
      assert Constrained.can_set?(constrained, :bar)
    end

    test "can_set? returns false for values not in allowed list" do
      constrained = Constrained.allow_only(:foo, [:foo, :bar])
      refute Constrained.can_set?(constrained, :baz)
      refute Constrained.can_set?(constrained, :other)
    end

    test "set/2 succeeds for allowed values" do
      constrained = Constrained.allow_only(:foo, [:foo, :bar])
      assert {:ok, updated} = Constrained.set(constrained, :bar)
      assert updated.value == :bar
    end

    test "set/2 returns error for disallowed values" do
      constrained = Constrained.allow_only(:foo, [:foo, :bar])
      assert {:error, %ConstraintError{} = error} = Constrained.set(constrained, :baz)
      assert error.type == :invalid_value
      assert error.candidate == ":baz"
    end
  end

  describe "allow_not/2" do
    test "creates a constrained value with disallowed list" do
      constrained = Constrained.allow_not(:safe, [:dangerous])
      assert constrained.value == :safe
      assert constrained.constraint == {:not, [:dangerous]}
    end

    test "can_set? returns true for values not in disallowed list" do
      constrained = Constrained.allow_not(:safe, [:dangerous, :risky])
      assert Constrained.can_set?(constrained, :safe)
      assert Constrained.can_set?(constrained, :okay)
    end

    test "can_set? returns false for values in disallowed list" do
      constrained = Constrained.allow_not(:safe, [:dangerous, :risky])
      refute Constrained.can_set?(constrained, :dangerous)
      refute Constrained.can_set?(constrained, :risky)
    end

    test "set/2 succeeds for non-disallowed values" do
      constrained = Constrained.allow_not(:safe, [:dangerous])
      assert {:ok, updated} = Constrained.set(constrained, :okay)
      assert updated.value == :okay
    end

    test "set/2 returns error for disallowed values" do
      constrained = Constrained.allow_not(:safe, [:dangerous])
      assert {:error, %ConstraintError{} = error} = Constrained.set(constrained, :dangerous)
      assert error.type == :invalid_value
      assert error.candidate == ":dangerous"
    end
  end

  describe "value/1" do
    test "returns the current value" do
      constrained = Constrained.allow_any(:test_value)
      assert Constrained.value(constrained) == :test_value
    end
  end

  describe "integration with sandbox modes" do
    test "constrains sandbox modes to allowed list" do
      # Simulates allowed_sandbox_modes from requirements.toml
      constrained = Constrained.allow_only(:workspace_write, [:read_only, :workspace_write])

      assert Constrained.can_set?(constrained, :read_only)
      assert Constrained.can_set?(constrained, :workspace_write)
      refute Constrained.can_set?(constrained, :danger_full_access)
      refute Constrained.can_set?(constrained, :external_sandbox)
    end

    test "constrains approval policies" do
      constrained = Constrained.allow_only(:on_failure, [:on_failure, :never])

      assert {:ok, _} = Constrained.set(constrained, :never)
      assert {:error, _} = Constrained.set(constrained, :untrusted)
    end
  end
end
