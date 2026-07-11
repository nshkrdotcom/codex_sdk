defmodule Codex.Protocol.PluginScheduledTasksTest do
  use ExUnit.Case, async: true

  alias Codex.Protocol.Plugin

  @baseline_dir "test/support/fixtures/codex_0_144_1"
  @post_0144_dir "test/support/fixtures/codex_post_0144"

  test "synthetic plugin detail parses scheduled tasks into typed structs" do
    frame = read_frame(@post_0144_dir, "plugin_detail_scheduled_tasks.jsonl")
    parsed = Plugin.ReadResponse.from_map(frame)

    assert %Plugin.ReadResponse{
             plugin: %Plugin.Detail{
               scheduled_tasks: [
                 %Plugin.ScheduledTaskSummary{
                   key: "weekly-summary",
                   name: "Weekly summary",
                   prompt: "Summarize the week",
                   schedule: %Plugin.ScheduledTaskSchedule{
                     type: "weekly",
                     days: ["MO", "WE"],
                     time: "09:00"
                   }
                 }
               ]
             }
           } = parsed

    assert Plugin.ReadResponse.to_map(parsed) == frame
  end

  test "all schedule variants round-trip with exact wire casing" do
    schedules = [
      %{"type" => "hourly", "intervalHours" => 2, "days" => nil},
      %{"type" => "daily", "time" => "09:00"},
      %{"type" => "weekdays", "time" => "10:30"},
      %{"type" => "weekly", "days" => ["MO", "WE", "FR"], "time" => "11:15"}
    ]

    for wire <- schedules do
      parsed = Plugin.ScheduledTaskSchedule.from_map(wire)
      assert Plugin.ScheduledTaskSchedule.to_map(parsed) == wire
    end
  end

  test "unknown schedule tags and keys remain string-keyed and lossless" do
    wire = %{
      "type" => "lunar",
      "days" => ["MO"],
      "phase" => "full",
      "futureScheduleKey" => %{"value" => true}
    }

    assert %Plugin.ScheduledTaskSchedule{
             type: "lunar",
             days: ["MO"],
             extra: %{
               "phase" => "full",
               "futureScheduleKey" => %{"value" => true}
             }
           } = parsed = Plugin.ScheduledTaskSchedule.from_map(wire)

    assert Plugin.ScheduledTaskSchedule.to_map(parsed) == wire

    summary_wire = %{
      "key" => "future-task",
      "name" => "Future task",
      "prompt" => "Run later",
      "schedule" => wire,
      "futureSummaryKey" => %{"enabled" => true}
    }

    summary = Plugin.ScheduledTaskSummary.from_map(summary_wire)
    assert summary.extra == %{"futureSummaryKey" => %{"enabled" => true}}
    assert Plugin.ScheduledTaskSummary.to_map(summary) == summary_wire
  end

  test "missing and empty scheduled task metadata remain distinct" do
    baseline = read_frame(@baseline_dir, "plugin_read_response.jsonl")
    parsed = Plugin.ReadResponse.from_map(baseline)

    assert %Plugin.ReadResponse{plugin: %Plugin.Detail{scheduled_tasks: nil}} = parsed
    refute Map.has_key?(Plugin.ReadResponse.to_map(parsed)["plugin"], "scheduledTasks")

    empty = put_in(baseline, ["plugin", "scheduledTasks"], [])
    empty_parsed = Plugin.ReadResponse.from_map(empty)

    assert %Plugin.ReadResponse{plugin: %Plugin.Detail{scheduled_tasks: []}} = empty_parsed
    assert Plugin.ReadResponse.to_map(empty_parsed)["plugin"]["scheduledTasks"] == []
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
