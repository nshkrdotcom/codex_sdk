defmodule Codex.EventsTest do
  use ExUnit.Case, async: true

  alias Codex.{Events, Items}

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

    test "parses item.started and item.updated events into typed structs" do
      started =
        Events.parse!(%{
          "type" => "item.started",
          "item" => %{
            "id" => "item_1",
            "type" => "command_execution",
            "command" => "mix test",
            "aggregated_output" => "",
            "status" => "in_progress"
          }
        })

      assert %Events.ItemStarted{
               item: %Items.CommandExecution{
                 id: "item_1",
                 command: "mix test",
                 aggregated_output: "",
                 status: :in_progress,
                 exit_code: nil
               }
             } = started

      updated =
        Events.parse!(%{
          "type" => "item.updated",
          "item" => %{
            "id" => "item_1",
            "type" => "command_execution",
            "command" => "mix test",
            "aggregated_output" => "Running",
            "status" => "in_progress"
          }
        })

      assert %Events.ItemUpdated{
               item: %Items.CommandExecution{
                 id: "item_1",
                 command: "mix test",
                 aggregated_output: "Running",
                 status: :in_progress,
                 exit_code: nil
               }
             } = updated
    end

    test "parses item.completed events for todo list and file change" do
      todo_event =
        Events.parse!(%{
          "type" => "item.completed",
          "item" => %{
            "id" => "todo_1",
            "type" => "todo_list",
            "items" => [
              %{"text" => "step 1", "completed" => true},
              %{"text" => "step 2", "completed" => false}
            ]
          }
        })

      assert %Events.ItemCompleted{
               item: %Items.TodoList{
                 id: "todo_1",
                 items: [%{text: "step 1", completed: true}, %{text: "step 2", completed: false}]
               }
             } = todo_event

      file_event =
        Events.parse!(%{
          "type" => "item.completed",
          "item" => %{
            "id" => "patch_1",
            "type" => "file_change",
            "status" => "completed",
            "changes" => [
              %{"path" => "lib/app.ex", "kind" => "update"},
              %{"path" => "lib/new.ex", "kind" => "add"}
            ]
          }
        })

      assert %Events.ItemCompleted{
               item: %Items.FileChange{
                 id: "patch_1",
                 status: :completed,
                 changes: [
                   %{path: "lib/app.ex", kind: :update},
                   %{path: "lib/new.ex", kind: :add}
                 ]
               }
             } = file_event
    end

    test "parses MCP tool calls and web search items" do
      mcp_event =
        Events.parse!(%{
          "type" => "item.started",
          "item" => %{
            "id" => "mcp_1",
            "type" => "mcp_tool_call",
            "server" => "example",
            "tool" => "inspect",
            "status" => "in_progress"
          }
        })

      assert %Events.ItemStarted{
               item: %Items.McpToolCall{
                 id: "mcp_1",
                 server: "example",
                 tool: "inspect",
                 status: :in_progress
               }
             } = mcp_event

      web_event =
        Events.parse!(%{
          "type" => "item.completed",
          "item" => %{
            "id" => "search_1",
            "type" => "web_search",
            "query" => "elixir json decode"
          }
        })

      assert %Events.ItemCompleted{
               item: %Items.WebSearch{id: "search_1", query: "elixir json decode"}
             } = web_event
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

    test "item events serialise back to protocol maps" do
      event = %Events.ItemCompleted{
        item: %Items.CommandExecution{
          id: "cmd_1",
          command: "mix test",
          aggregated_output: "ok",
          exit_code: 0,
          status: :completed
        }
      }

      assert %{
               "type" => "item.completed",
               "item" => %{
                 "id" => "cmd_1",
                 "type" => "command_execution",
                 "command" => "mix test",
                 "aggregated_output" => "ok",
                 "exit_code" => 0,
                 "status" => "completed"
               }
             } = Events.to_map(event)
    end
  end
end
