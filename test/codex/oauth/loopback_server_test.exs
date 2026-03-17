defmodule Codex.OAuth.LoopbackServerTest do
  use ExUnit.Case, async: false

  alias Codex.OAuth.LoopbackServer

  test "binds loopback only with a random port and accepts the exact callback path" do
    {:ok, server} =
      LoopbackServer.start(callback_path: "/auth/callback", expected_state: "state-123")

    assert server.callback_url =~ "http://localhost:"
    assert server.callback_url =~ "/auth/callback"

    wrong_path_url = String.replace(server.callback_url, "/auth/callback", "/wrong")
    assert {:ok, %Req.Response{status: 404}} = Req.get(wrong_path_url)

    assert {:ok, %Req.Response{status: 200}} =
             Req.get(server.callback_url, params: [code: "auth-code", state: "state-123"])

    assert {:ok, %{code: "auth-code", state: "state-123"}} =
             LoopbackServer.await_result(server, 1_000)
  end

  test "rejects state mismatch and shuts down" do
    {:ok, server} =
      LoopbackServer.start(callback_path: "/auth/callback", expected_state: "good-state")

    assert {:ok, %Req.Response{status: 400}} =
             Req.get(server.callback_url, params: [code: "auth-code", state: "bad-state"])

    assert {:error, {:state_mismatch, %{expected: "good-state", received: "bad-state"}}} =
             LoopbackServer.await_result(server, 1_000)
  end

  test "cancel/1 terminates a pending listener" do
    {:ok, server} =
      LoopbackServer.start(callback_path: "/auth/callback", expected_state: "state-123")

    assert :ok = LoopbackServer.cancel(server)
    assert {:error, :cancelled} = LoopbackServer.await_result(server, 1_000)
  end

  test "returns an error when the callback port is already in use" do
    {:ok, socket} =
      :gen_tcp.listen(0, [:binary, {:active, false}, {:reuseaddr, true}, {:ip, {127, 0, 0, 1}}])

    on_exit(fn -> :gen_tcp.close(socket) end)

    {:ok, {{127, 0, 0, 1}, port}} = :inet.sockname(socket)

    assert {:error, _reason} =
             LoopbackServer.start(
               callback_path: "/auth/callback",
               expected_state: "state-123",
               port: port
             )
  end
end
