defmodule Codex.ItemsCollabTest do
  use ExUnit.Case, async: true

  alias Codex.Items
  alias Codex.Protocol.CollabAgentState

  test "items: parses wait tool aliases for collab items" do
    item =
      Items.parse!(%{
        "type" => "collab_agent_tool_call",
        "id" => "collab_wait_1",
        "tool" => "waitAgent",
        "status" => "completed",
        "sender_thread_id" => "thr_parent",
        "receiver_thread_ids" => ["thr_child"],
        "agents_states" => %{"thr_child" => %{"completed" => "done"}}
      })

    assert %Items.CollabAgentToolCall{
             id: "collab_wait_1",
             tool: "waitAgent",
             tool_kind: :wait,
             status: :completed,
             sender_thread_id: "thr_parent",
             receiver_thread_ids: ["thr_child"],
             agents_states: %{
               "thr_child" => %CollabAgentState{status: :completed, message: "done"}
             }
           } = item
  end

  test "items: parses legacy singular collab item fields" do
    item =
      Items.parse!(%{
        "type" => "collab_agent_tool_call",
        "id" => "collab_spawn_legacy",
        "tool" => "spawnAgent",
        "status" => "completed",
        "sender_thread_id" => "thr_parent",
        "new_thread_id" => "thr_child",
        "agent_status" => %{"completed" => "done"}
      })

    assert %Items.CollabAgentToolCall{
             id: "collab_spawn_legacy",
             tool: "spawnAgent",
             tool_kind: :spawn_agent,
             status: :completed,
             sender_thread_id: "thr_parent",
             receiver_thread_ids: ["thr_child"],
             agents_states: %{
               "thr_child" => %CollabAgentState{status: :completed, message: "done"}
             }
           } = item

    send_item =
      Items.parse!(%{
        "type" => "collab_agent_tool_call",
        "id" => "collab_send_legacy",
        "tool" => "send_input",
        "status" => "completed",
        "sender_thread_id" => "thr_parent",
        "receiver_thread_id" => "thr_child",
        "agent_status" => "running"
      })

    assert %Items.CollabAgentToolCall{
             id: "collab_send_legacy",
             tool: "send_input",
             tool_kind: :send_input,
             status: :completed,
             sender_thread_id: "thr_parent",
             receiver_thread_ids: ["thr_child"],
             agents_states: %{
               "thr_child" => %CollabAgentState{status: :running, message: nil}
             }
           } = send_item
  end
end
