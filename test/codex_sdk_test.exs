defmodule CodexSdkTest do
  use ExUnit.Case
  doctest CodexSdk

  test "greets the world" do
    assert CodexSdk.hello() == :world
  end
end
