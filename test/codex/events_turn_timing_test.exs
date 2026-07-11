defmodule Codex.EventsTurnTimingTest do
  use ExUnit.Case, async: true

  alias Codex.AppServer.NotificationAdapter
  alias Codex.Events

  @baseline_dir "test/support/fixtures/codex_0_144_1"
  @post_0144_dir "test/support/fixtures/codex_post_0144"

  test "core turn completion projection parses timing and terminal error fields" do
    completed =
      @post_0144_dir
      |> read_frame("exec_turn_completed_timing.jsonl")
      |> Events.parse!()

    assert %Events.TurnCompleted{
             started_at: 1_783_123_200,
             completed_at: 1_783_123_260,
             duration_ms: 60_000,
             time_to_first_token_ms: 850,
             error: nil
           } = completed

    failed =
      @post_0144_dir
      |> read_frame("exec_turn_completed_error.jsonl")
      |> Events.parse!()

    assert %Events.TurnCompleted{
             duration_ms: 5_000,
             time_to_first_token_ms: nil,
             error: %{"message" => "provider failed"}
           } = failed
  end

  test "live exec JSONL baseline keeps timing fields absent" do
    event =
      @baseline_dir
      |> read_frame("exec_turn_completed.jsonl")
      |> Events.parse!()

    assert %Events.TurnCompleted{
             started_at: nil,
             completed_at: nil,
             duration_ms: nil,
             time_to_first_token_ms: nil,
             error: nil
           } = event
  end

  test "app-server turn completion maps live timing and synthetic terminal error" do
    %{"method" => live_method, "params" => live_params} =
      read_frame(@baseline_dir, "app_server_turn_completed.jsonl")

    assert {:ok,
            %Events.TurnCompleted{
              started_at: 1_783_790_242,
              completed_at: 1_783_790_247,
              duration_ms: 4_532,
              time_to_first_token_ms: nil,
              error: nil
            }} = NotificationAdapter.to_event(live_method, live_params)

    %{"method" => method, "params" => params} =
      read_frame(@post_0144_dir, "app_server_turn_completed_timing.jsonl")

    assert {:ok,
            %Events.TurnCompleted{
              started_at: 1_783_123_200,
              completed_at: 1_783_123_205,
              duration_ms: 5_000,
              error: %{
                "message" => "provider failed",
                "additionalDetails" => "request id synthetic"
              }
            }} = NotificationAdapter.to_event(method, params)
  end

  test "core turn aborted projection parses timing without changing the reason" do
    event =
      @post_0144_dir
      |> read_frame("exec_turn_aborted_timing.jsonl")
      |> Events.parse!()

    assert %Events.TurnAborted{
             turn_id: "turn_synthetic_aborted",
             reason: "interrupted",
             started_at: 1_783_123_200,
             completed_at: 1_783_123_202,
             duration_ms: 2_000
           } = event
  end

  test "turn_duration_ms/1 prefers explicit duration and falls back to timestamps" do
    assert Events.turn_duration_ms(%Events.TurnCompleted{
             duration_ms: 321,
             started_at: 10,
             completed_at: 20
           }) == 321

    assert Events.turn_duration_ms(%Events.TurnCompleted{started_at: 10, completed_at: 12}) ==
             2_000

    assert Events.turn_duration_ms(%Events.TurnAborted{started_at: 10, completed_at: 13}) ==
             3_000

    assert Events.turn_duration_ms(%Events.TurnCompleted{started_at: 10}) == nil
  end

  defp read_frame(dir, file) do
    dir
    |> Path.join(file)
    |> File.stream!([], :line)
    |> Stream.map(&String.trim/1)
    |> Enum.find(&(&1 != "" and not String.starts_with?(&1, "#")))
    |> Jason.decode!()
  end
end
