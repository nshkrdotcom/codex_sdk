defmodule Codex.Plugins.ManifestTest do
  use ExUnit.Case, async: true

  alias Codex.Plugins.Manifest

  test "minimal valid manifest parses and preserves unknown fields" do
    payload = %{
      "name" => "demo-plugin",
      "skills" => "./skills/",
      "interface" => %{
        "displayName" => "Demo Plugin",
        "composerIcon" => "./assets/icon.png",
        "futureInterfaceField" => true
      },
      "futureManifestField" => "kept"
    }

    assert {:ok,
            %Manifest{
              name: "demo-plugin",
              skills: "./skills/",
              extra: %{"futureManifestField" => "kept"},
              interface: %{
                display_name: "Demo Plugin",
                composer_icon: "./assets/icon.png",
                extra: %{"futureInterfaceField" => true}
              }
            }} = Manifest.parse(payload)

    assert %{
             "name" => "demo-plugin",
             "skills" => "./skills/",
             "futureManifestField" => "kept",
             "interface" => %{
               "displayName" => "Demo Plugin",
               "composerIcon" => "./assets/icon.png",
               "futureInterfaceField" => true
             }
           } = Manifest.to_map(Manifest.from_map(payload))
  end

  test "relative component and asset paths reject absolute or escaping paths" do
    payload = %{
      "name" => "demo-plugin",
      "skills" => "/tmp/skills",
      "apps" => "../apps.json",
      "mcpServers" => "./../mcp.json",
      "interface" => %{
        "composerIcon" => "/tmp/icon.png",
        "logo" => "./../logo.png",
        "screenshots" => ["./assets/ok.png", "../outside.png"]
      }
    }

    assert {:error, {:invalid_plugin_manifest, details}} = Manifest.parse(payload)

    issue_paths = Enum.map(details.issues, & &1.path)

    assert ["skills"] in issue_paths
    assert ["apps"] in issue_paths
    assert ["mcpServers"] in issue_paths
    assert ["interface", "composerIcon"] in issue_paths
    assert ["interface", "logo"] in issue_paths
    assert ["interface", "screenshots", 1] in issue_paths
  end

  test "defaultPrompt enforces the upstream stable length and count limits" do
    too_many_prompts = [
      "Summarize the inbox",
      "Draft a reply",
      "Create follow-up tasks",
      "One prompt too many"
    ]

    assert {:error, {:invalid_plugin_manifest, details}} =
             Manifest.parse(%{
               "name" => "demo-plugin",
               "interface" => %{"defaultPrompt" => too_many_prompts}
             })

    assert Enum.any?(details.issues, fn issue ->
             issue.path == ["interface", "defaultPrompt"] and
               String.contains?(issue.message, "at most 3 prompts")
           end)

    overlong_prompt = String.duplicate("a", 129)

    assert {:error, {:invalid_plugin_manifest, details}} =
             Manifest.parse(%{
               "name" => "demo-plugin",
               "interface" => %{"defaultPrompt" => [overlong_prompt]}
             })

    assert Enum.any?(details.issues, fn issue ->
             issue.path == ["interface", "defaultPrompt"] and
               String.contains?(issue.message, "at most 128 characters")
           end)
  end
end
