defmodule Codex.Contract.ThreadParityTest do
  use Codex.ContractCase

  describe "thread_basic.jsonl" do
    test "captures python reference sequence" do
      events =
        "python/thread_basic.jsonl"
        |> fixture_path!()
        |> load_jsonl_fixture()

      assert Enum.count(events) == 5

      assert %{
               "type" => "thread.started",
               "thread_id" => "thread_abc123",
               "metadata" => %{
                 "labels" => %{"topic" => "demo"}
               }
             } = Enum.fetch!(events, 0)

      assert %{
               "type" => "turn.started",
               "turn_id" => "turn_def456",
               "thread_id" => "thread_abc123"
             } = Enum.fetch!(events, 1)

      assert %{
               "type" => "turn.completed",
               "final_response" => %{"text" => "Hello from Python Codex!"},
               "usage" => %{
                 "input_tokens" => 12,
                 "output_tokens" => 9,
                 "total_tokens" => 21
               }
             } = List.last(events)
    end
  end
end
