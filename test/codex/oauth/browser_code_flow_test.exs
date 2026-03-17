defmodule Codex.OAuth.BrowserCodeFlowTest do
  use ExUnit.Case, async: false
  use Codex.TestSupport.AuthEnv

  import Plug.Conn

  alias Codex.Auth.Store
  alias Codex.OAuth.Context
  alias Codex.OAuth.Flows.BrowserCode

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

  defmodule MockIssuerPlug do
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

          response = %{
            "id_token" => Keyword.fetch!(opts, :id_token),
            "access_token" => Keyword.fetch!(opts, :access_token),
            "refresh_token" => "refresh-token"
          }

          if params["grant_type"] == "authorization_code" and params["code_verifier"] do
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(200, Jason.encode!(response))
          else
            send_resp(conn, 400, Jason.encode!(%{"error" => "invalid_request"}))
          end

        _ ->
          send_resp(conn, 404, "not found")
      end
    end
  end

  test "browser flow builds the authorize url and persists upstream-compatible auth", %{
    codex_home: codex_home
  } do
    id_token =
      fake_jwt(%{
        "email" => "dev@example.com",
        "https://api.openai.com/auth" => %{
          "chatgpt_account_id" => "acct_123",
          "chatgpt_user_id" => "user_123",
          "chatgpt_plan_type" => "pro"
        }
      })

    access_token =
      fake_jwt(%{
        "exp" => DateTime.utc_now() |> DateTime.add(3_600, :second) |> DateTime.to_unix(),
        "https://api.openai.com/auth" => %{
          "chatgpt_plan_type" => "pro",
          "chatgpt_account_id" => "acct_123"
        }
      })

    {:ok, issuer_pid} =
      Bandit.start_link(
        plug: {MockIssuerPlug, id_token: id_token, access_token: access_token},
        ip: {127, 0, 0, 1},
        port: 0
      )

    on_exit(fn ->
      try do
        _ = Supervisor.stop(issuer_pid)
      catch
        :exit, _ -> :ok
      end
    end)

    {:ok, {{127, 0, 0, 1}, port}} = ThousandIsland.listener_info(issuer_pid)
    issuer = "http://127.0.0.1:#{port}"

    context =
      Context.resolve!(
        auth_issuer: issuer,
        codex_home: codex_home,
        process_env: %{"CODEX_HOME" => codex_home},
        interactive?: true,
        os: :macos
      )

    configured_port = reserve_port()
    Application.put_env(:codex_sdk, :oauth_browser_callback_port, configured_port)

    assert {:ok, pending} = BrowserCode.begin(context, storage: :file)

    params = pending.authorize_url |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()

    assert params["code_challenge_method"] == "S256"
    assert params["state"] == pending.state
    assert params["redirect_uri"] == "http://localhost:#{configured_port}/auth/callback"

    assert {:ok, %Req.Response{status: 200}} = Req.get(pending.authorize_url)
    assert {:ok, session} = BrowserCode.await(pending, timeout: 2_000)

    assert session.auth_record.auth_mode == :chatgpt
    assert session.auth_record.tokens.account_id == "acct_123"
    assert session.auth_record.tokens.plan_type == "pro"

    assert {:ok, %Store.Record{} = stored} =
             Store.load(codex_home: codex_home, codex_home_explicit?: true)

    assert stored.auth_mode == :chatgpt
    assert stored.openai_api_key == access_token
    assert stored.tokens.access_token == access_token
    assert stored.tokens.refresh_token == "refresh-token"
    assert stored.tokens.account_id == "acct_123"
  end

  defp reserve_port do
    {:ok, socket} =
      :gen_tcp.listen(0, [:binary, {:active, false}, {:reuseaddr, true}, {:ip, {127, 0, 0, 1}}])

    {:ok, {{127, 0, 0, 1}, port}} = :inet.sockname(socket)
    :ok = :gen_tcp.close(socket)
    port
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
end
