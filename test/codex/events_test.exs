defmodule Codex.EventsTest do
  use ExUnit.Case, async: true

  alias Codex.Events

  describe "parse!/1" do
    test "converts thread.started event map into typed struct" do
      event =
        Events.parse!(%{
          "type" => "thread.started",
          "thread_id" => "thread_abc123",
          "metadata" => %{"labels" => %{"topic" => "demo"}}
        })

      assert %Events.ThreadStarted{
               thread_id: "thread_abc123",
               metadata: %{"labels" => %{"topic" => "demo"}}
             } = event
    end

    test "raises for unknown event type" do
      assert_raise ArgumentError, fn ->
        Events.parse!(%{"type" => "unknown.event"})
      end
    end
  end

  describe "round trip encoding" do
    test "thread_basic fixture encodes back to original maps" do
      raw_events =
        Path.join([File.cwd!(), "integration", "fixtures", "python", "thread_basic.jsonl"])
        |> File.stream!([], :line)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
        |> Enum.map(&Jason.decode!/1)

      for raw <- raw_events do
        parsed = Events.parse!(raw)
        assert raw == Events.to_map(parsed)
      end
    end
  end
end
