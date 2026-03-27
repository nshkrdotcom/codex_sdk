defmodule Codex.AppServer.RemoteConnectionTest do
  use ExUnit.Case, async: false
  @moduletag capture_log: true
  @moduletag :requires_loopback

  import Plug.Conn

  alias Codex.AppServer

  defmodule RemoteAppServerPlug do
    import Plug.Conn

    def init(opts), do: opts

    def call(conn, opts) do
      send(Keyword.fetch!(opts, :owner), {:remote_upgrade_headers, headers_map(conn)})

      upgrade_adapter(
        conn,
        :websocket,
        {Codex.AppServer.RemoteConnectionTest.RemoteAppServerSocket, opts, []}
      )
    end

    defp headers_map(conn) do
      conn.req_headers
      |> Enum.group_by(fn {key, _value} -> key end, fn {_key, value} -> value end)
      |> Map.new(fn {key, values} -> {key, List.last(values)} end)
    end
  end

  defmodule RemoteAppServerSocket do
    @behaviour WebSock

    def init(opts) do
      send(Keyword.fetch!(opts, :owner), {:remote_socket_connected, self()})
      {:ok, %{owner: Keyword.fetch!(opts, :owner), opts: opts}}
    end

    def handle_in({payload, [opcode: :text]}, %{owner: owner, opts: opts} = state) do
      message = Jason.decode!(payload)
      send(owner, {:remote_socket_received, self(), message})

      case message do
        %{"method" => "initialize", "id" => id} ->
          frames =
            Keyword.get(opts, :initialize_messages, []) ++
              [%{"id" => id, "result" => %{"userAgent" => "codex/0.0.0"}}]

          {:push, Enum.map(frames, &{:text, Jason.encode!(&1)}), state}

        %{"method" => "initialized"} ->
          send(owner, {:remote_socket_initialized, self()})
          {:ok, state}

        %{"method" => "experimentalFeature/list", "id" => id} ->
          {:push,
           {:text,
            Jason.encode!(%{
              "id" => id,
              "result" => %{
                "data" => [
                  %{
                    "name" => "apps",
                    "stage" => "beta",
                    "displayName" => "Apps",
                    "description" => "Apps support",
                    "announcement" => nil,
                    "enabled" => true,
                    "defaultEnabled" => false
                  }
                ],
                "nextCursor" => nil
              }
            })}, state}

        _other ->
          {:ok, state}
      end
    end

    def handle_info({:push_json, payload}, state) when is_map(payload) do
      {:push, {:text, Jason.encode!(payload)}, state}
    end

    def handle_info(:close, state) do
      {:stop, :normal, state}
    end

    def terminate(reason, state) do
      send(state.owner, {:remote_socket_terminated, self(), reason})
      :ok
    end
  end

  setup do
    {:ok, bandit_pid} =
      Bandit.start_link(
        plug: {RemoteAppServerPlug, owner: self()},
        ip: {127, 0, 0, 1},
        port: 0
      )

    {:ok, {{127, 0, 0, 1}, port}} = ThousandIsland.listener_info(bandit_pid)
    url = "ws://127.0.0.1:#{port}"

    on_exit(fn ->
      try do
        _ = Supervisor.stop(bandit_pid)
      catch
        :exit, _ -> :ok
      end
    end)

    {:ok, url: url}
  end

  test "connect_remote/2 completes initialize/initialized and preserves init-time events", %{
    url: _url
  } do
    initialize_messages = [
      %{"method" => "thread/started", "params" => %{"threadId" => "thr_buffered"}},
      %{
        "id" => 91,
        "method" => "tool/requestUserInput",
        "params" => %{"questions" => [%{"header" => "Mode"}]}
      }
    ]

    {:ok, bandit_pid} =
      Bandit.start_link(
        plug: {RemoteAppServerPlug, owner: self(), initialize_messages: initialize_messages},
        ip: {127, 0, 0, 1},
        port: 0
      )

    {:ok, {{127, 0, 0, 1}, port}} = ThousandIsland.listener_info(bandit_pid)
    remote_url = "ws://127.0.0.1:#{port}"

    on_exit(fn ->
      try do
        _ = Supervisor.stop(bandit_pid)
      catch
        :exit, _ -> :ok
      end
    end)

    assert {:ok, conn} = AppServer.connect_remote(remote_url, init_timeout_ms: 500)
    assert AppServer.alive?(conn)

    assert_receive {:remote_socket_received, socket_pid, %{"method" => "initialize", "id" => 0}},
                   1_000

    assert_receive {:remote_socket_received, ^socket_pid, %{"method" => "initialized"}}, 1_000

    assert :ok = AppServer.subscribe(conn)

    assert_receive {:codex_notification, "thread/started", %{"threadId" => "thr_buffered"}}, 1_000

    assert_receive {:codex_request, 91, "tool/requestUserInput", %{"questions" => [_]}}, 1_000

    assert :ok = AppServer.respond(conn, 91, %{"answers" => [%{"value" => "pair"}]})

    assert_receive {:remote_socket_received, ^socket_pid,
                    %{"id" => 91, "result" => %{"answers" => [%{"value" => "pair"}]}}},
                   1_000
  end

  test "remote request round-trip works through existing AppServer helpers", %{url: url} do
    assert {:ok, conn} = AppServer.connect_remote(url, init_timeout_ms: 500)

    assert {:ok, %{"data" => [%{"name" => "apps"}], "nextCursor" => nil}} =
             AppServer.experimental_feature_list(conn, limit: 2)

    assert :ok = AppServer.disconnect(conn)
  end

  test "runtime notifications and server requests are delivered to subscribers", %{url: url} do
    assert {:ok, conn} = AppServer.connect_remote(url, init_timeout_ms: 500)
    assert :ok = AppServer.subscribe(conn)
    assert_receive {:remote_socket_connected, socket_pid}, 1_000

    send(
      socket_pid,
      {:push_json, %{"method" => "thread/started", "params" => %{"threadId" => "thr_1"}}}
    )

    assert_receive {:codex_notification, "thread/started", %{"threadId" => "thr_1"}}, 1_000

    send(
      socket_pid,
      {:push_json,
       %{
         "id" => 77,
         "method" => "account/chatgptAuthTokens/refresh",
         "params" => %{"reason" => "unauthorized"}
       }}
    )

    assert_receive {:codex_request, 77, "account/chatgptAuthTokens/refresh",
                    %{"reason" => "unauthorized"}},
                   1_000

    assert :ok = AppServer.respond(conn, 77, %{"accessToken" => "token"})

    assert_receive {:remote_socket_received, ^socket_pid,
                    %{"id" => 77, "result" => %{"accessToken" => "token"}}},
                   1_000
  end

  test "connect_remote/2 includes an authorization header for loopback ws auth tokens", %{
    url: url
  } do
    assert {:ok, conn} =
             AppServer.connect_remote(url, auth_token: "secret-token", init_timeout_ms: 500)

    assert_receive {:remote_upgrade_headers, headers}, 1_000
    assert headers["authorization"] == "Bearer secret-token"

    assert :ok = AppServer.disconnect(conn)
  end

  test "connect_remote/2 resolves auth_token_env from process_env", %{url: url} do
    assert {:ok, conn} =
             AppServer.connect_remote(url,
               auth_token_env: "CODEX_REMOTE_TOKEN",
               process_env: %{"CODEX_REMOTE_TOKEN" => "env-secret"},
               init_timeout_ms: 500
             )

    assert_receive {:remote_upgrade_headers, headers}, 1_000
    assert headers["authorization"] == "Bearer env-secret"

    assert :ok = AppServer.disconnect(conn)
  end

  test "connect_remote/2 rejects missing auth_token_env" do
    assert {:error, {:missing_auth_token_env, "CODEX_REMOTE_TOKEN"}} =
             AppServer.connect_remote("ws://127.0.0.1:4500",
               auth_token_env: "CODEX_REMOTE_TOKEN"
             )
  end

  test "connect_remote/2 rejects empty auth_token_env" do
    assert {:error, {:empty_auth_token_env, "CODEX_REMOTE_TOKEN"}} =
             AppServer.connect_remote("ws://127.0.0.1:4500",
               auth_token_env: "CODEX_REMOTE_TOKEN",
               process_env: %{"CODEX_REMOTE_TOKEN" => "   "}
             )
  end

  test "connect_remote/2 rejects non-loopback ws auth tokens" do
    assert {:error, {:invalid_remote_auth_transport, "ws://192.168.1.10:4500"}} =
             AppServer.connect_remote("ws://192.168.1.10:4500",
               auth_token: "secret-token"
             )
  end

  test "disconnect/1 cleanly shuts down a remote connection", %{url: url} do
    assert {:ok, conn} = AppServer.connect_remote(url, init_timeout_ms: 500)
    ref = Process.monitor(conn)

    assert :ok = AppServer.disconnect(conn)
    assert_receive {:DOWN, ^ref, :process, ^conn, _reason}, 1_000
    refute Process.alive?(conn)
  end
end
