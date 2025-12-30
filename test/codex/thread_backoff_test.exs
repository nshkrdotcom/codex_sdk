defmodule Codex.ThreadBackoffTest do
  use ExUnit.Case, async: true

  alias Codex.Thread.Backoff

  test "delay_ms clamps large attempts without overflow" do
    assert Backoff.delay_ms(1) == 100
    assert Backoff.delay_ms(10_000) == 5_000
  end

  test "delay_ms returns 0 for invalid attempts" do
    assert Backoff.delay_ms(0) == 0
    assert Backoff.delay_ms(-5) == 0
  end
end
