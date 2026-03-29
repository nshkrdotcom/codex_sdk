defmodule Codex.LiveSSHTest do
  use ExUnit.Case, async: false

  alias CliSubprocessCore.TestSupport.LiveSSH
  alias Codex.Items

  @moduletag :live_ssh
  @moduletag timeout: 120_000

  @live_ssh_enabled LiveSSH.enabled?()

  if not @live_ssh_enabled do
    @moduletag skip: LiveSSH.skip_reason()
  end

  setup_all do
    if @live_ssh_enabled and not LiveSSH.runnable?("codex") do
      raise "Remote SSH target #{inspect(LiveSSH.destination())} does not have a runnable `codex --version`."
    end

    :ok
  end

  test "live SSH: Codex.CLI.run executes against the remote codex binary" do
    assert {:ok, %{stdout: stdout, success: true}} =
             Codex.CLI.run(["--version"], execution_surface: LiveSSH.execution_surface())

    assert String.contains?(String.downcase(stdout), "codex")
  end

  test "live SSH: Codex.Thread.run executes against the remote codex binary" do
    prompt = "Reply with exactly: CODEX_LIVE_SSH_OK"

    assert {:ok, thread} =
             Codex.start_thread(
               %{execution_surface: LiveSSH.execution_surface()},
               %{
                 skip_git_repo_check: true,
                 dangerously_bypass_approvals_and_sandbox: true
               }
             )

    assert {:ok, result} = Codex.Thread.run(thread, prompt, %{timeout_ms: 120_000})
    assert extract_text(result.final_response) =~ "CODEX_LIVE_SSH_OK"
  end

  defp extract_text(%Items.AgentMessage{text: text}) when is_binary(text), do: text
  defp extract_text(%{"type" => "text", "text" => text}) when is_binary(text), do: text
  defp extract_text(%{type: "text", text: text}) when is_binary(text), do: text
  defp extract_text(other) when is_binary(other), do: other
  defp extract_text(other), do: inspect(other)
end
