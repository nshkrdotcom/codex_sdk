defmodule Codex.OAuth.DeviceCodeFlowTest do
  use ExUnit.Case, async: false
  use Codex.TestSupport.AuthEnv

  @moduletag :requires_loopback

  import Plug.Conn

  alias Codex.Auth.Store
  alias Codex.OAuth.Context
  alias Codex.OAuth.Flows.DeviceCode

  defmodule MockDeviceIssuerPlug do
    import Plug.Conn

    def init(opts), do: opts

    def call(conn, opts) do
      conn = fetch_query_params(conn)

      case {conn.method, conn.request_path} do
        {"POST", "/api/accounts/deviceauth/usercode"} ->
          send_user_code(conn)

        {"POST", "/api/accounts/deviceauth/token"} ->
          send_device_token(conn, opts)

        {"POST", "/oauth/token"} ->
          send_oauth_token(conn, opts)

        _ ->
          send_resp(conn, 404, "not found")
      end
    end

    defp send_user_code(conn) do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(
        200,
        Jason.encode!(%{
          "device_auth_id" => "device-123",
          "user_code" => "ABCD-EFGH",
          "interval" => "1"
        })
      )
    end

    defp send_device_token(conn, opts) do
      {:ok, body, conn} = read_body(conn)
      _params = Jason.decode!(body)
      {status, payload} = device_token_response(opts)

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(status, Jason.encode!(payload))
    end

    defp device_token_response(opts) do
      case next_poll_count(opts) do
        0 ->
          {400, %{"error" => "authorization_pending"}}

        1 ->
          {400, %{"error" => "slow_down"}}

        _ ->
          {200, %{"authorization_code" => "device-code", "code_verifier" => "device-verifier"}}
      end
    end

    defp next_poll_count(opts) do
      Agent.get_and_update(Keyword.fetch!(opts, :counter), fn count ->
        {count, count + 1}
      end)
    end

    defp send_oauth_token(conn, opts) do
      {:ok, body, conn} = read_body(conn)
      params = URI.decode_query(body)
      payload = oauth_token_payload(params, opts)
      status = if Map.has_key?(payload, "error"), do: 400, else: 200

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(status, Jason.encode!(payload))
    end

    defp oauth_token_payload(params, opts) do
      if params["grant_type"] == "authorization_code" and
           params["code_verifier"] == "device-verifier" do
        %{
          "id_token" => Keyword.fetch!(opts, :id_token),
          "access_token" => Keyword.fetch!(opts, :access_token),
          "refresh_token" => "refresh-token"
        }
      else
        %{"error" => "invalid_request"}
      end
    end
  end

  defmodule DeniedDeviceIssuerPlug do
    import Plug.Conn

    def init(opts), do: opts

    def call(conn, _opts) do
      conn = fetch_query_params(conn)

      case {conn.method, conn.request_path} do
        {"POST", "/api/accounts/deviceauth/usercode"} ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(
            200,
            Jason.encode!(%{"device_auth_id" => "device-123", "user_code" => "ABCD-EFGH"})
          )

        {"POST", "/api/accounts/deviceauth/token"} ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(400, Jason.encode!(%{"error" => "access_denied"}))

        _ ->
          send_resp(conn, 404, "not found")
      end
    end
  end

  test "device flow requests codes, respects polling backoff, and persists auth", %{
    codex_home: codex_home
  } do
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    on_exit(fn ->
      try do
        Agent.stop(counter)
      catch
        :exit, _ -> :ok
      end
    end)

    id_token =
      fake_jwt(%{
        "https://api.openai.com/auth" => %{
          "chatgpt_account_id" => "acct_321",
          "chatgpt_plan_type" => "team"
        }
      })

    access_token =
      fake_jwt(%{
        "exp" => DateTime.utc_now() |> DateTime.add(3_600, :second) |> DateTime.to_unix(),
        "https://api.openai.com/auth" => %{
          "chatgpt_account_id" => "acct_321",
          "chatgpt_plan_type" => "team"
        }
      })

    {:ok, issuer_pid} =
      Bandit.start_link(
        plug:
          {MockDeviceIssuerPlug, counter: counter, id_token: id_token, access_token: access_token},
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
        os: :linux
      )

    assert {:ok, pending} = DeviceCode.begin(context, storage: :file)
    assert pending.user_code == "ABCD-EFGH"
    assert pending.verification_url == issuer <> "/codex/device"

    sleep_fun = fn ms ->
      send(self(), {:slept, ms})
      :ok
    end

    assert {:ok, session} = DeviceCode.await(pending, timeout: 2_000, sleep_fun: sleep_fun)
    assert_receive {:slept, 1_000}
    assert_receive {:slept, 2_000}

    assert session.auth_record.tokens.account_id == "acct_321"
    assert session.auth_record.tokens.plan_type == "team"

    assert {:ok, %Store.Record{} = stored} =
             Store.load(codex_home: codex_home, codex_home_explicit?: true)

    assert stored.auth_mode == :chatgpt
    assert stored.tokens.account_id == "acct_321"
    assert stored.tokens.refresh_token == "refresh-token"
  end

  test "device flow fails clearly on denied authorization", %{codex_home: codex_home} do
    {:ok, issuer_pid} =
      Bandit.start_link(plug: DeniedDeviceIssuerPlug, ip: {127, 0, 0, 1}, port: 0)

    on_exit(fn ->
      try do
        _ = Supervisor.stop(issuer_pid)
      catch
        :exit, _ -> :ok
      end
    end)

    {:ok, {{127, 0, 0, 1}, port}} = ThousandIsland.listener_info(issuer_pid)

    context =
      Context.resolve!(
        auth_issuer: "http://127.0.0.1:#{port}",
        codex_home: codex_home,
        process_env: %{"CODEX_HOME" => codex_home},
        interactive?: true,
        os: :linux
      )

    assert {:ok, pending} = DeviceCode.begin(context, storage: :file)

    assert {:error, :device_code_denied} =
             DeviceCode.await(pending, timeout: 100, sleep_fun: fn _ -> :ok end)
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
