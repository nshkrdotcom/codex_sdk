defmodule Codex.OAuth.AppServerAuthTest do
  use ExUnit.Case, async: false
  use Codex.TestSupport.AuthEnv

  import Plug.Conn

  alias Codex.AppServer
  alias Codex.AppServer.Protocol
  alias Codex.Auth.Store
  alias Codex.Options
  alias Codex.TestSupport.AppServerSubprocess

  defmodule MockRefreshIssuerPlug do
    import Plug.Conn

    def init(opts), do: opts

    def call(conn, opts) do
      case {conn.method, conn.request_path} do
        {"POST", "/oauth/token"} ->
          {:ok, body, conn} = read_body(conn)
          params = URI.decode_query(body)
          send(Keyword.fetch!(opts, :owner), {:oauth_token_request, params})

          conn
          |> put_resp_content_type("application/json")
          |> send_resp(200, Jason.encode!(Agent.get(Keyword.fetch!(opts, :state), & &1)))

        _ ->
          send_resp(conn, 404, "not found")
      end
    end
  end

  setup do
    bash = System.find_executable("bash") || "/bin/bash"
    {:ok, codex_opts} = Options.new(%{codex_path_override: bash})
    {:ok, codex_opts: codex_opts}
  end

  test "AppServer.connect with oauth file mode resolves auth against the child CODEX_HOME", %{
    tmp_root: tmp_root,
    codex_opts: codex_opts
  } do
    child_home = Path.join(tmp_root, "child_home_file")
    File.mkdir_p!(child_home)

    :ok =
      Store.write(
        Store.build_record(auth_mode: :api_key, openai_api_key: "sk-child"),
        codex_home: child_home
      )

    owner = self()

    task =
      Task.async(fn ->
        AppServer.connect(codex_opts,
          transport: {AppServerSubprocess, owner: owner},
          init_timeout_ms: 200,
          process_env: child_env(child_home),
          oauth: [storage: :file, interactive?: false]
        )
      end)

    assert_receive {:app_server_subprocess_started, conn, os_pid}
    assert_receive {:app_server_subprocess_start_opts, ^conn, ^os_pid, _start_opts}
    assert_receive {:app_server_subprocess_send, ^conn, init_line}
    assert {:ok, %{"id" => 0, "method" => "initialize"}} = Jason.decode(init_line)

    send(conn, {:stdout, os_pid, Protocol.encode_response(0, %{"userAgent" => "codex/0.0.0"})})

    assert_receive {:app_server_subprocess_send, ^conn, initialized_line}
    assert {:ok, %{"method" => "initialized"}} = Jason.decode(initialized_line)
    refute_receive {:app_server_subprocess_send, ^conn, _login_line}, 50

    assert {:ok, ^conn} = Task.await(task, 200)
    assert AppServer.disconnect(conn) == :ok
  end

  test "memory-mode oauth requires experimental_api: true", %{codex_opts: codex_opts} do
    assert {:error, :experimental_api_required_for_memory_oauth} =
             AppServer.connect(codex_opts,
               transport: {AppServerSubprocess, owner: self()},
               oauth: [storage: :memory]
             )

    refute_receive {:app_server_subprocess_started, _, _}
  end

  test "AppServer.connect with oauth memory mode performs external login and auto-refresh without rewriting auth.json",
       %{
         tmp_root: tmp_root,
         codex_opts: codex_opts
       } do
    child_home = Path.join(tmp_root, "child_home_memory")
    File.mkdir_p!(child_home)

    initial_access_token = fake_chatgpt_access_token("acct_1", "pro")
    refreshed_access_token = fake_chatgpt_access_token("acct_1", "pro")

    write_chatgpt_auth(child_home, initial_access_token, "refresh-token", "acct_1", "pro")

    {:ok, issuer, state} = start_mock_issuer(%{"access_token" => refreshed_access_token})

    owner = self()

    task =
      Task.async(fn ->
        AppServer.connect(codex_opts,
          transport: {AppServerSubprocess, owner: owner},
          experimental_api: true,
          init_timeout_ms: 200,
          process_env: child_env(child_home),
          oauth: [
            mode: :auto,
            storage: :memory,
            auto_refresh: true,
            interactive?: false,
            auth_issuer: issuer
          ]
        )
      end)

    assert_receive {:app_server_subprocess_started, conn, os_pid}
    assert_receive {:app_server_subprocess_start_opts, ^conn, ^os_pid, _start_opts}
    assert_receive {:app_server_subprocess_send, ^conn, init_line}

    assert {:ok, %{"id" => 0, "method" => "initialize", "params" => init_params}} =
             Jason.decode(init_line)

    assert init_params["capabilities"] == %{"experimentalApi" => true}

    send(conn, {:stdout, os_pid, Protocol.encode_response(0, %{"userAgent" => "codex/0.0.0"})})

    assert_receive {:app_server_subprocess_send, ^conn, initialized_line}
    assert {:ok, %{"method" => "initialized"}} = Jason.decode(initialized_line)

    assert_receive {:app_server_subprocess_send, ^conn, login_line}

    assert {:ok, %{"id" => login_id, "method" => "account/login/start", "params" => login_params}} =
             Jason.decode(login_line)

    assert login_params == %{
             "type" => "chatgptAuthTokens",
             "accessToken" => initial_access_token,
             "chatgptAccountId" => "acct_1",
             "chatgptPlanType" => "pro"
           }

    send(
      conn,
      {:stdout, os_pid, Protocol.encode_response(login_id, %{"type" => "chatgptAuthTokens"})}
    )

    assert {:ok, ^conn} = Task.await(task, 200)
    assert 1 == map_size(:sys.get_state(conn).subscribers)
    assert :ok == AppServer.subscribe(conn, methods: ["account/chatgptAuthTokens/refresh"])

    send(
      conn,
      {:stdout, os_pid,
       Protocol.encode_request(91, "account/chatgptAuthTokens/refresh", %{
         "reason" => "unauthorized",
         "previousAccountId" => "acct_1"
       })}
    )

    assert_receive {:codex_request, 91, "account/chatgptAuthTokens/refresh",
                    %{"reason" => "unauthorized"}},
                   1_000

    assert_receive {:oauth_token_request,
                    %{
                      "grant_type" => "refresh_token",
                      "refresh_token" => "refresh-token",
                      "client_id" => _
                    }},
                   1_000

    assert_receive {:app_server_subprocess_send, ^conn, refresh_line}, 1_000

    assert {:ok, %{"id" => 91, "result" => refresh_result}} = Jason.decode(refresh_line)

    assert refresh_result == %{
             "accessToken" => refreshed_access_token,
             "chatgptAccountId" => "acct_1",
             "chatgptPlanType" => "pro"
           }

    assert {:ok, %Store.Record{} = stored} =
             Store.load(codex_home: child_home, codex_home_explicit?: true)

    assert stored.tokens.access_token == initial_access_token
    assert AppServer.disconnect(conn) == :ok

    Agent.stop(state)
  end

  test "auto refresh rejects previousAccountId mismatches", %{
    tmp_root: tmp_root,
    codex_opts: codex_opts
  } do
    child_home = Path.join(tmp_root, "child_home_mismatch")
    File.mkdir_p!(child_home)

    initial_access_token = fake_chatgpt_access_token("acct_1", "pro")
    mismatched_access_token = fake_chatgpt_access_token("acct_2", "pro")

    write_chatgpt_auth(child_home, initial_access_token, "refresh-token", "acct_1", "pro")

    {:ok, issuer, state} = start_mock_issuer(%{"access_token" => mismatched_access_token})

    owner = self()

    task =
      Task.async(fn ->
        AppServer.connect(codex_opts,
          transport: {AppServerSubprocess, owner: owner},
          experimental_api: true,
          init_timeout_ms: 200,
          process_env: child_env(child_home),
          oauth: [storage: :memory, auto_refresh: true, interactive?: false, auth_issuer: issuer]
        )
      end)

    assert_receive {:app_server_subprocess_started, conn, os_pid}
    assert_receive {:app_server_subprocess_start_opts, ^conn, ^os_pid, _start_opts}
    assert_receive {:app_server_subprocess_send, ^conn, init_line}
    assert {:ok, %{"id" => 0}} = Jason.decode(init_line)
    send(conn, {:stdout, os_pid, Protocol.encode_response(0, %{"userAgent" => "codex/0.0.0"})})
    assert_receive {:app_server_subprocess_send, ^conn, _initialized_line}

    assert_receive {:app_server_subprocess_send, ^conn, login_line}

    assert {:ok, %{"id" => login_id, "method" => "account/login/start"}} =
             Jason.decode(login_line)

    send(
      conn,
      {:stdout, os_pid, Protocol.encode_response(login_id, %{"type" => "chatgptAuthTokens"})}
    )

    assert {:ok, ^conn} = Task.await(task, 200)
    assert 1 == map_size(:sys.get_state(conn).subscribers)
    assert :ok == AppServer.subscribe(conn, methods: ["account/chatgptAuthTokens/refresh"])

    send(
      conn,
      {:stdout, os_pid,
       Protocol.encode_request(92, "account/chatgptAuthTokens/refresh", %{
         "reason" => "unauthorized",
         "previousAccountId" => "acct_1"
       })}
    )

    assert_receive {:codex_request, 92, "account/chatgptAuthTokens/refresh",
                    %{"reason" => "unauthorized"}},
                   1_000

    assert_receive {:oauth_token_request, %{"refresh_token" => "refresh-token"}}, 1_000
    assert_receive {:app_server_subprocess_send, ^conn, refresh_line}, 1_000

    assert {:ok, %{"id" => 92, "error" => error}} = Jason.decode(refresh_line)
    assert error["message"] == "refreshed ChatGPT account did not match the previous account"

    assert AppServer.disconnect(conn) == :ok
    Agent.stop(state)
  end

  defp start_mock_issuer(payload) do
    {:ok, state} = Agent.start_link(fn -> payload end)

    {:ok, issuer_pid} =
      Bandit.start_link(
        plug: {MockRefreshIssuerPlug, owner: self(), state: state},
        ip: {127, 0, 0, 1},
        port: 0
      )

    {:ok, {{127, 0, 0, 1}, port}} = ThousandIsland.listener_info(issuer_pid)

    on_exit(fn ->
      try do
        _ = Supervisor.stop(issuer_pid)
      catch
        :exit, _ -> :ok
      end
    end)

    {:ok, "http://127.0.0.1:#{port}", state}
  end

  defp write_chatgpt_auth(codex_home, access_token, refresh_token, account_id, plan_type) do
    id_token =
      fake_jwt(%{
        "email" => "dev@example.com",
        "https://api.openai.com/auth" => %{
          "chatgpt_account_id" => account_id,
          "chatgpt_user_id" => "user_1",
          "chatgpt_plan_type" => plan_type
        }
      })

    record =
      Store.build_record(
        auth_mode: :chatgpt,
        openai_api_key: access_token,
        access_token: access_token,
        refresh_token: refresh_token,
        id_token: id_token,
        last_refresh: DateTime.utc_now()
      )

    :ok = Store.write(record, codex_home: codex_home)
  end

  defp fake_chatgpt_access_token(account_id, plan_type) do
    fake_jwt(%{
      "exp" => DateTime.utc_now() |> DateTime.add(3_600, :second) |> DateTime.to_unix(),
      "https://api.openai.com/auth" => %{
        "chatgpt_account_id" => account_id,
        "chatgpt_plan_type" => plan_type
      }
    })
  end

  defp fake_jwt(payload) do
    header =
      %{"alg" => "none", "typ" => "JWT"} |> Jason.encode!() |> Base.url_encode64(padding: false)

    payload =
      payload
      |> Jason.encode!()
      |> Base.url_encode64(padding: false)

    header <> "." <> payload <> ".sig"
  end

  defp child_env(codex_home) do
    [CODEX_HOME: codex_home, HOME: codex_home, USERPROFILE: codex_home]
  end
end
