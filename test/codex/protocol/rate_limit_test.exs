defmodule Codex.Protocol.RateLimitTest do
  use ExUnit.Case, async: true

  alias Codex.Protocol.RateLimit

  test "window from_map handles camelCase fields" do
    data = %{"usedPercent" => 12.5, "windowDurationMins" => 15, "resetsAt" => 123}
    window = RateLimit.Window.from_map(data)

    assert %RateLimit.Window{used_percent: 12.5, window_minutes: 15, resets_at: 123} = window

    assert %{"used_percent" => 12.5, "window_minutes" => 15, "resets_at" => 123} =
             RateLimit.Window.to_map(window)
  end

  test "credits snapshot decodes alternate keys" do
    data = %{"hasCredits" => true, "isUnlimited" => false, "balance" => "$10"}
    snapshot = RateLimit.CreditsSnapshot.from_map(data)

    assert %RateLimit.CreditsSnapshot{has_credits: true, unlimited: false, balance: "$10"} =
             snapshot
  end

  test "snapshot parses plan type and nested windows" do
    data = %{
      "primary" => %{"used_percent" => 5.0, "window_minutes" => 60},
      "planType" => "pro"
    }

    snapshot = RateLimit.Snapshot.from_map(data)

    assert %RateLimit.Snapshot{
             plan_type: :pro,
             primary: %RateLimit.Window{used_percent: 5.0, window_minutes: 60}
           } = snapshot

    assert %{"plan_type" => "pro"} = RateLimit.Snapshot.to_map(snapshot)
  end
end
