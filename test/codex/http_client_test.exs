defmodule Codex.HTTPClientTest do
  use ExUnit.Case, async: false

  alias Codex.HTTPClient

  setup do
    env_keys = ~w(CODEX_CA_CERTIFICATE SSL_CERT_FILE)

    original_env =
      env_keys
      |> Enum.map(&{&1, System.get_env(&1)})
      |> Map.new()

    Enum.each(env_keys, &System.delete_env/1)

    on_exit(fn ->
      Enum.each(env_keys, fn key ->
        case Map.fetch!(original_env, key) do
          nil -> System.delete_env(key)
          value -> System.put_env(key, value)
        end
      end)
    end)

    :ok
  end

  test "Req request options include connect_options when a custom CA is configured" do
    System.put_env("CODEX_CA_CERTIFICATE", "/tmp/codex.pem")

    opts = HTTPClient.Req.request_options(headers: [{"authorization", "Bearer test"}])

    assert Keyword.get(opts, :headers) == [{"authorization", "Bearer test"}]

    assert Keyword.get(opts, :connect_options) ==
             [transport_opts: [cacertfile: "/tmp/codex.pem"]]
  end

  test "Req request options omit connect_options when no custom CA is configured" do
    opts = HTTPClient.Req.request_options(headers: [{"authorization", "Bearer test"}])

    assert Keyword.get(opts, :headers) == [{"authorization", "Bearer test"}]
    refute Keyword.has_key?(opts, :connect_options)
  end
end
