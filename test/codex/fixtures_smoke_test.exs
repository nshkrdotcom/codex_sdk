defmodule Codex.FixturesSmokeTest do
  use ExUnit.Case, async: true

  alias Codex.AppServer.NotificationAdapter
  alias Codex.Events
  alias Codex.Protocol.Plugin

  @baseline_dir "test/support/fixtures/codex_0_144_1"
  @post_0144_dir "test/support/fixtures/codex_post_0144"

  test "exec fixtures remain parseable as additive event maps" do
    for {dir, file} <- [
          {@baseline_dir, "exec_turn_completed.jsonl"},
          {@baseline_dir, "exec_turn_failed.jsonl"},
          {@post_0144_dir, "exec_turn_completed_timing.jsonl"},
          {@post_0144_dir, "exec_turn_completed_error.jsonl"},
          {@post_0144_dir, "exec_turn_aborted_timing.jsonl"},
          {@post_0144_dir, "response_item_prefixed_id.jsonl"}
        ],
        frame <- read_frames(dir, file) do
      assert %{__struct__: _} = Events.parse!(frame)
    end
  end

  test "app-server turn fixtures remain parseable with unknown fields" do
    for {dir, file} <- [
          {@baseline_dir, "app_server_turn_completed.jsonl"},
          {@post_0144_dir, "app_server_turn_completed_timing.jsonl"}
        ],
        %{"method" => method, "params" => params} <- read_frames(dir, file) do
      assert {:ok, %{__struct__: _}} = NotificationAdapter.to_event(method, params)
    end
  end

  test "plugin fixtures preserve fields not typed by the current parser" do
    for {dir, file} <- [
          {@baseline_dir, "plugin_read_response.jsonl"},
          {@post_0144_dir, "plugin_detail_scheduled_tasks.jsonl"}
        ],
        frame <- read_frames(dir, file) do
      parsed = Plugin.ReadResponse.from_map(frame)
      encoded = Plugin.ReadResponse.to_map(parsed)

      assert encoded["plugin"]["scheduledTasks"] == frame["plugin"]["scheduledTasks"]
    end
  end

  test "schema-only fixtures decode without atomizing wire keys" do
    for file <- [
          "login_account_bedrock.jsonl",
          "rollout_line_ordinal.jsonl"
        ],
        frame <- read_frames(@post_0144_dir, file) do
      assert string_keyed?(frame)
    end
  end

  defp read_frames(dir, file) do
    dir
    |> Path.join(file)
    |> File.stream!([], :line)
    |> Stream.map(&String.trim/1)
    |> Stream.reject(&(&1 == "" or String.starts_with?(&1, "#")))
    |> Enum.map(&Jason.decode!/1)
  end

  defp string_keyed?(%{} = value) do
    Enum.all?(value, fn {key, nested} -> is_binary(key) and string_keyed?(nested) end)
  end

  defp string_keyed?(value) when is_list(value), do: Enum.all?(value, &string_keyed?/1)
  defp string_keyed?(_value), do: true
end
