defmodule Codex.ItemsMetadataTest do
  use ExUnit.Case, async: true

  alias Codex.Items

  test "mcp tool call preserves app resource uri through parse and to_map" do
    item =
      Items.parse!(%{
        "type" => "mcp_tool_call",
        "id" => "mcp_1",
        "server" => "codex_apps",
        "tool" => "lookup",
        "arguments" => %{"id" => "123"},
        "mcp_app_resource_uri" => "ui://widget/lookup.html",
        "status" => "completed"
      })

    assert %Items.McpToolCall{
             id: "mcp_1",
             server: "codex_apps",
             tool: "lookup",
             mcp_app_resource_uri: "ui://widget/lookup.html",
             status: :completed
           } = item

    assert %{
             "type" => "mcp_tool_call",
             "id" => "mcp_1",
             "server" => "codex_apps",
             "tool" => "lookup",
             "mcp_app_resource_uri" => "ui://widget/lookup.html",
             "status" => "completed"
           } = Items.to_map(item)
  end
end
