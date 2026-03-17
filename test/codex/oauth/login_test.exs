defmodule Codex.OAuth.LoginTest do
  use ExUnit.Case, async: false
  use Codex.TestSupport.AuthEnv

  import Plug.Conn

  alias Codex.Auth.Store
  alias Codex.OAuth

  setup do
    original_port = Application.get_env(:codex_sdk, :oauth_browser_callback_port)

    on_exit(fn ->
      if is_nil(original_port) do
        Application.delete_env(:codex_sdk, :oauth_browser_callback_port)
      else
        Application.put_env(:codex_sdk, :oauth_browser_callback_port, original_port)
      end
    end)

    :ok
  end

  defmodule MockOAuthIssuerPlug do
    import Plug.Conn

    def init(opts), do: opts

    def call(conn, opts) do
      conn = fetch_query_params(conn)

      case {conn.method, conn.request_path} do
        {"GET", "/oauth/authorize"} ->
          redirect_uri = conn.query_params["redirect_uri"]
          state = conn.query_params["state"]

          location =
            redirect_uri <> "?" <> URI.encode_query(%{"code" => "auth-code", "state" => state})

          conn
          |> put_resp_header("location", location)
          |> send_resp(302, "")

        {"POST", "/oauth/token"} ->
          {:ok, body, conn} = read_body(conn)
          params = URI.decode_query(body)

          payload =
            case params["grant_type"] do
              "authorization_code" ->
                Keyword.fetch!(opts, :authorization_payload)

              "refresh_token" ->
                Keyword.fetch!(opts, :refresh_payload)

              _ ->
                %{"error" => "invalid_request"}
            end

          status = if Map.has_key?(payload, "error"), do: 400, else: 200

          conn
          |> put_resp_content_type("application/json")
          |> send_resp(status, Jason.encode!(payload))

        _ ->
          send_resp(conn, 404, "not found")
      end
    end
  end

  test "begin_login/1 and await_login/2 drive the public browser flow", %{codex_home: codex_home} do
    access_token = fake_chatgpt_access_token("acct_123", "pro")
    id_token = fake_chatgpt_id_token("acct_123", "pro")

    {:ok, issuer} =
      start_mock_issuer(
        authorization_payload: %{
          "access_token" => access_token,
          "refresh_token" => "refresh-token",
          "id_token" => id_token
        },
        refresh_payload: %{
          "access_token" => access_token,
          "refresh_token" => "refresh-token"
        }
      )

    opts = [
      auth_issuer: issuer,
      codex_home: codex_home,
      process_env: %{"CODEX_HOME" => codex_home},
      interactive?: true,
      os: :macos,
      storage: :memory
    ]

    configured_port = reserve_port()
    Application.put_env(:codex_sdk, :oauth_browser_callback_port, configured_port)

    assert {:ok, pending} = OAuth.begin_login(opts)
    assert String.starts_with?(pending.authorize_url, issuer <> "/oauth/authorize?")
    assert pending.redirect_uri == "http://localhost:#{configured_port}/auth/callback"

    assert {:ok, %Req.Response{status: 200}} = Req.get(pending.authorize_url)
    assert {:ok, result} = OAuth.await_login(pending, timeout: 2_000)

    assert result.provider == :openai_chatgpt
    assert result.flow_used == :browser_code
    assert result.storage_used == :memory
    assert result.auth_mode == :chatgpt
    assert result.account_id == "acct_123"
    assert result.plan_type == "pro"
    refute result.persisted?
  end

  test "login/status/refresh/logout manage persisted oauth auth", %{codex_home: codex_home} do
    initial_access_token = fake_chatgpt_access_token("acct_321", "team")
    refreshed_access_token = fake_chatgpt_access_token("acct_321", "team")

    record =
      Store.build_record(
        auth_mode: :chatgpt,
        openai_api_key: initial_access_token,
        access_token: initial_access_token,
        refresh_token: "refresh-token",
        id_token: fake_chatgpt_id_token("acct_321", "team"),
        last_refresh: DateTime.utc_now()
      )

    :ok = Store.write(record, codex_home: codex_home)

    {:ok, issuer} =
      start_mock_issuer(
        authorization_payload: %{
          "access_token" => initial_access_token,
          "refresh_token" => "refresh-token",
          "id_token" => fake_chatgpt_id_token("acct_321", "team")
        },
        refresh_payload: %{
          "access_token" => refreshed_access_token,
          "refresh_token" => "refresh-token"
        }
      )

    opts = [
      auth_issuer: issuer,
      codex_home: codex_home,
      process_env: %{"CODEX_HOME" => codex_home},
      interactive?: false
    ]

    assert {:ok, login_result} = OAuth.login(opts)
    assert login_result.account_id == "acct_321"
    assert login_result.storage_used == :file
    assert login_result.persisted?

    assert {:ok, status} = OAuth.status(opts)
    assert status.authenticated?
    assert status.account_id == "acct_321"
    assert status.plan_type == "team"

    assert {:ok, refreshed_status} = OAuth.refresh(opts)
    assert refreshed_status.authenticated?
    assert refreshed_status.account_id == "acct_321"

    assert {:ok, %Store.Record{} = stored} =
             Store.load(codex_home: codex_home, codex_home_explicit?: true)

    assert stored.tokens.access_token == refreshed_access_token

    assert :ok = OAuth.logout(opts)

    assert {:ok, logged_out_status} = OAuth.status(opts)
    refute logged_out_status.authenticated?
  end

  defp start_mock_issuer(opts) do
    {:ok, issuer_pid} =
      Bandit.start_link(plug: {MockOAuthIssuerPlug, opts}, ip: {127, 0, 0, 1}, port: 0)

    on_exit(fn ->
      try do
        _ = Supervisor.stop(issuer_pid)
      catch
        :exit, _ -> :ok
      end
    end)

    {:ok, {{127, 0, 0, 1}, port}} = ThousandIsland.listener_info(issuer_pid)
    {:ok, "http://127.0.0.1:#{port}"}
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

  defp fake_chatgpt_id_token(account_id, plan_type) do
    fake_jwt(%{
      "email" => "dev@example.com",
      "https://api.openai.com/auth" => %{
        "chatgpt_account_id" => account_id,
        "chatgpt_user_id" => "user_123",
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

  defp reserve_port do
    {:ok, socket} =
      :gen_tcp.listen(0, [:binary, {:active, false}, {:reuseaddr, true}, {:ip, {127, 0, 0, 1}}])

    {:ok, {{127, 0, 0, 1}, port}} = :inet.sockname(socket)
    :ok = :gen_tcp.close(socket)
    port
  end
end
