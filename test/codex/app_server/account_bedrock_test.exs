defmodule Codex.AppServer.AccountBedrockTest do
  use ExUnit.Case, async: true

  alias Codex.AppServer.Account
  alias Codex.AppServer.Connection
  alias Codex.AppServer.NotificationAdapter
  alias Codex.AppServer.Protocol
  alias Codex.Auth.Store
  alias Codex.Events
  alias Codex.Options
  alias Codex.TestSupport.AppServerSubprocess

  setup do
    harness =
      AppServerSubprocess.new!(owner: self())
      |> AppServerSubprocess.put_current!()

    on_exit(fn -> AppServerSubprocess.cleanup(harness) end)

    {:ok, base_opts} = Options.new(%{api_key: "test"})
    codex_opts = AppServerSubprocess.codex_opts(base_opts, harness)

    {:ok, conn} =
      Connection.start_link(codex_opts,
        process_env: AppServerSubprocess.process_env(harness),
        init_timeout_ms: 200
      )

    :ok = AppServerSubprocess.attach(harness, conn)
    assert_receive {:app_server_subprocess_started, ^conn, _os_pid}
    assert_receive {:app_server_subprocess_send, ^conn, init_line}
    assert {:ok, %{"id" => 0}} = Jason.decode(init_line)

    :ok =
      AppServerSubprocess.send_stdout(
        Protocol.encode_response(0, %{"userAgent" => "codex/0.0.0"})
      )

    assert :ok == Connection.await_ready(conn, 200)
    assert_receive {:app_server_subprocess_send, ^conn, _initialized_line}

    {:ok, conn: conn}
  end

  test "typed Amazon Bedrock login encodes apiKey and region", %{conn: conn} do
    api_key = "bedrock-test-key"

    task =
      Task.async(fn ->
        Account.login_start(conn, {:amazon_bedrock, api_key, "us-east-1"})
      end)

    assert_receive {:app_server_subprocess_send, ^conn, request_line}

    assert {:ok,
            %{
              "id" => request_id,
              "method" => "account/login/start",
              "params" => params
            }} = Jason.decode(request_line)

    assert params == %{
             "type" => "amazonBedrock",
             "apiKey" => api_key,
             "region" => "us-east-1"
           }

    AppServerSubprocess.send_stdout(
      Protocol.encode_response(request_id, %{"type" => "amazonBedrock"})
    )

    assert {:ok, %{"type" => "amazonBedrock"}} = Task.await(task, 200)
  end

  test "raw Amazon Bedrock params remain a forward-compatible passthrough", %{conn: conn} do
    params = %{
      "type" => "amazonBedrock",
      "apiKey" => "raw-test-key",
      "region" => "us-west-2",
      "futureOption" => true
    }

    task = Task.async(fn -> Account.login_start(conn, params) end)
    assert_receive {:app_server_subprocess_send, ^conn, request_line}

    assert {:ok, %{"id" => request_id, "params" => ^params}} = Jason.decode(request_line)
    AppServerSubprocess.send_stdout(Protocol.encode_response(request_id, %{}))
    assert {:ok, %{}} = Task.await(task, 200)
  end

  test "typed Amazon Bedrock login rejects missing credentials without sending", %{conn: conn} do
    assert {:error, {:invalid_amazon_bedrock_login, :api_key_required}} =
             Account.login_start(conn, {:amazon_bedrock, "", "us-east-1"})

    assert {:error, {:invalid_amazon_bedrock_login, :region_required}} =
             Account.login_start(conn, {:amazon_bedrock, "bedrock-test-key", " "})

    refute_receive {:app_server_subprocess_send, ^conn, _request_line}, 50
  end

  test "Bedrock auth mode is recognized while unknown modes remain strings" do
    assert {:ok, %Events.AccountUpdated{auth_mode: :bedrock_api_key}} =
             NotificationAdapter.to_event("account/updated", %{
               "authMode" => "bedrockApiKey",
               "planType" => nil
             })

    assert {:ok, %Events.AccountUpdated{auth_mode: "futureAuthMode"}} =
             NotificationAdapter.to_event("account/updated", %{
               "authMode" => "futureAuthMode"
             })
  end

  test "auth.json Bedrock credentials round-trip with redacted inspection" do
    codex_home =
      Path.join(System.tmp_dir!(), "codex_bedrock_auth_#{System.unique_integer([:positive])}")

    File.mkdir_p!(codex_home)
    on_exit(fn -> File.rm_rf(codex_home) end)

    auth_path = Store.primary_path(codex_home)
    api_key = "persisted-bedrock-test-key"

    File.write!(
      auth_path,
      Jason.encode!(%{
        "auth_mode" => "bedrockApiKey",
        "bedrock_api_key" => %{"api_key" => api_key, "region" => "us-east-2"}
      })
    )

    assert {:ok,
            %Store.Record{
              auth_mode: :bedrock_api_key,
              bedrock_api_key: %Store.BedrockCredentials{
                api_key: ^api_key,
                region: "us-east-2"
              }
            } = record} = Store.load_path(auth_path)

    assert Store.infer_auth_mode(record) == :api
    refute inspect(record) =~ api_key

    assert :ok = Store.write(record, codex_home: codex_home)
    assert {:ok, encoded} = auth_path |> File.read!() |> Jason.decode()
    assert encoded["auth_mode"] == "bedrockApiKey"
    assert encoded["bedrock_api_key"] == %{"api_key" => api_key, "region" => "us-east-2"}
  end
end
