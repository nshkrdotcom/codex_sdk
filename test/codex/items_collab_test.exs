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
end
