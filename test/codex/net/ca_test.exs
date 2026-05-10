defmodule Codex.Net.CATest do
  use ExUnit.Case, async: false

  alias Codex.TestSupport.Env

  alias Codex.Net.CA

  setup do
    env_keys = ~w(CODEX_CA_CERTIFICATE SSL_CERT_FILE)

    original_env =
      env_keys
      |> Enum.map(&{&1, System.get_env(&1)})
      |> Map.new()

    Enum.each(env_keys, &Env.delete/1)

    on_exit(fn ->
      Enum.each(env_keys, fn key ->
        case Map.fetch!(original_env, key) do
          nil -> Env.delete(key)
          value -> Env.put(key, value)
        end
      end)
    end)

    :ok
  end

  test "CODEX_CA_CERTIFICATE takes precedence over SSL_CERT_FILE" do
    Env.put("CODEX_CA_CERTIFICATE", "/tmp/codex.pem")
    Env.put("SSL_CERT_FILE", "/tmp/ssl.pem")

    assert CA.certificate_file() == "/tmp/codex.pem"
  end

  test "blank CA environment values are ignored" do
    Env.put("CODEX_CA_CERTIFICATE", "   ")
    Env.put("SSL_CERT_FILE", "")

    assert CA.certificate_file() == nil
    assert CA.env_overrides() == %{}
    assert CA.req_connect_options() == []
    assert CA.httpc_ssl_options() == []
    assert CA.websocket_ssl_options() == []
  end

  test "SSL_CERT_FILE is used when CODEX_CA_CERTIFICATE is unset" do
    Env.put("SSL_CERT_FILE", "/tmp/ssl.pem")

    assert CA.certificate_file() == "/tmp/ssl.pem"

    assert CA.env_overrides() == %{
             "CODEX_CA_CERTIFICATE" => "/tmp/ssl.pem",
             "SSL_CERT_FILE" => "/tmp/ssl.pem"
           }
  end

  test "builds Req, :httpc, and websocket options from the resolved certificate file" do
    Env.put("CODEX_CA_CERTIFICATE", "/tmp/codex.pem")

    assert CA.req_connect_options() == [transport_opts: [cacertfile: "/tmp/codex.pem"]]
    assert CA.httpc_ssl_options() == [cacertfile: "/tmp/codex.pem"]
    assert CA.websocket_ssl_options() == [cacertfile: "/tmp/codex.pem"]
  end

  test "merges Req options without dropping existing transport options" do
    Env.put("CODEX_CA_CERTIFICATE", "/tmp/codex.pem")

    opts =
      CA.merge_req_options(
        headers: [{"x-test", "1"}],
        connect_options: [transport_opts: [proxy: {:http, ~c"localhost", 8080}]]
      )

    assert Keyword.get(opts, :headers) == [{"x-test", "1"}]

    assert Keyword.get(opts, :connect_options) == [
             transport_opts: [proxy: {:http, ~c"localhost", 8080}, cacertfile: "/tmp/codex.pem"]
           ]
  end
end
