defmodule Codex.Protocol.SessionSourceTest do
  use ExUnit.Case, async: true

  alias Codex.Protocol.SessionSource
  alias Codex.Protocol.SubAgentSource

  test "subagents: parses thread_spawn source" do
    data = %{
      "subAgent" => %{
        "thread_spawn" => %{
          "parent_thread_id" => "thr_parent",
          "depth" => 1,
          "agent_nickname" => "Atlas",
          "agent_role" => "explorer"
        }
      }
    }

    assert %SessionSource{
             kind: :sub_agent,
             sub_agent: %SubAgentSource{
               variant: :thread_spawn,
               parent_thread_id: "thr_parent",
               depth: 1,
               agent_nickname: "Atlas",
               agent_role: "explorer"
             }
           } = SessionSource.from_map(data)

    assert SessionSource.source_kind(data) == :sub_agent_thread_spawn
  end

  test "subagents: parses supported session source kinds" do
    assert %SessionSource{kind: :cli} = SessionSource.from_map("cli")
    assert %SessionSource{kind: :vscode} = SessionSource.from_map("vscode")
    assert %SessionSource{kind: :exec} = SessionSource.from_map("exec")
    assert %SessionSource{kind: :app_server} = SessionSource.from_map("appServer")
    assert %SessionSource{kind: :unknown} = SessionSource.from_map("unknown")
  end

  test "subagents: parses subagent variants" do
    assert %SessionSource{sub_agent: %SubAgentSource{variant: :review}} =
             SessionSource.from_map(%{"subAgent" => "review"})

    assert %SessionSource{sub_agent: %SubAgentSource{variant: :compact}} =
             SessionSource.from_map(%{"subAgent" => "compact"})

    assert %SessionSource{sub_agent: %SubAgentSource{variant: :memory_consolidation}} =
             SessionSource.from_map(%{"subAgent" => "memory_consolidation"})

    assert %SessionSource{sub_agent: %SubAgentSource{variant: :other, other: "custom"}} =
             SessionSource.from_map(%{"subAgent" => %{"other" => "custom"}})
  end

  test "subagents: normalizes source kinds for list filters" do
    assert SessionSource.normalize_source_kind(:cli) == :cli
    assert SessionSource.normalize_source_kind("vscode") == :vscode
    assert SessionSource.normalize_source_kind("appServer") == :app_server
    assert SessionSource.normalize_source_kind("subAgent") == :sub_agent
    assert SessionSource.normalize_source_kind("subAgentReview") == :sub_agent_review
    assert SessionSource.normalize_source_kind("subAgentCompact") == :sub_agent_compact
    assert SessionSource.normalize_source_kind("subAgentThreadSpawn") == :sub_agent_thread_spawn
    assert SessionSource.normalize_source_kind("subAgentOther") == :sub_agent_other
    assert SessionSource.normalize_source_kind("unknown") == :unknown
  end
end
