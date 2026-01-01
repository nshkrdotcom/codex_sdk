defmodule Codex.MCP.ConfigTest do
  use ExUnit.Case, async: true

  alias Codex.MCP.Config

  defmodule FakeAppServer do
    def config_read(_conn, _opts) do
      {:ok, %{"config" => %{"mcp_servers" => %{"alpha" => %{"command" => "npx"}}}}}
    end

    def config_write(_conn, key_path, value, _opts) do
      Process.put(:last_config_write, {key_path, value})
      {:ok, %{"status" => "ok"}}
    end
  end

  test "list_servers extracts mcp_servers from config" do
    assert {:ok, servers} = Config.list_servers(self(), app_server: FakeAppServer)
    assert %{"alpha" => %{"command" => "npx"}} = servers
  end

  test "add_server writes mcp_servers entry" do
    assert {:ok, %{"status" => "ok"}} =
             Config.add_server(
               self(),
               "docs",
               [command: "npx", args: ["-y", "docs-mcp"], envVars: ["API_KEY"]],
               app_server: FakeAppServer
             )

    assert {"mcp_servers.docs", value} = Process.get(:last_config_write)
    assert value["command"] == "npx"
    assert value["args"] == ["-y", "docs-mcp"]
    assert value["env_vars"] == ["API_KEY"]
  end

  test "add_server returns error when transport is missing" do
    assert {:error, :missing_server_config} =
             Config.add_server(self(), "bad", [], app_server: FakeAppServer)
  end

  test "remove_server clears mcp_servers entry" do
    assert {:ok, %{"status" => "ok"}} =
             Config.remove_server(self(), "docs", app_server: FakeAppServer)

    assert {"mcp_servers.docs", nil} = Process.get(:last_config_write)
  end
end
