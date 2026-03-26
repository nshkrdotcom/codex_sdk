defmodule Codex.Auth.StoreTest do
  use ExUnit.Case, async: false
  use Codex.TestSupport.AuthEnv

  alias Codex.Auth.Store

  describe "load/1" do
    test "respects explicit chatgpt auth_mode over stale OPENAI_API_KEY", %{
      codex_home: codex_home
    } do
      File.write!(
        Path.join(codex_home, "auth.json"),
        Jason.encode!(%{
          "auth_mode" => "chatgpt",
          "OPENAI_API_KEY" => "sk-stale",
          "tokens" => %{
            "access_token" => "chatgpt-access-token",
            "refresh_token" => "refresh-token",
            "id_token" =>
              fake_jwt(%{"https://api.openai.com/auth" => %{"chatgpt_plan_type" => "pro"}})
          },
          "last_refresh" => "2026-03-16T00:00:00Z"
        })
      )

      assert {:ok, %Store.Record{} = auth} =
               Store.load(codex_home: codex_home, codex_home_explicit?: true)

      assert auth.auth_mode == :chatgpt
      assert auth.openai_api_key == "sk-stale"
      assert auth.tokens.access_token == "chatgpt-access-token"
      assert auth.tokens.plan_type == "pro"
    end

    test "falls back to OPENAI_API_KEY when auth_mode is absent", %{codex_home: codex_home} do
      File.write!(
        Path.join(codex_home, "auth.json"),
        Jason.encode!(%{
          "OPENAI_API_KEY" => "sk-auth-file"
        })
      )

      assert {:ok, %Store.Record{} = auth} =
               Store.load(codex_home: codex_home, codex_home_explicit?: true)

      assert auth.auth_mode == :api_key
      assert auth.openai_api_key == "sk-auth-file"
      assert auth.tokens == nil
    end

    test "keeps chatgptAuthTokens distinct from managed chatgpt auth", %{codex_home: codex_home} do
      File.write!(
        Path.join(codex_home, "auth.json"),
        Jason.encode!(%{
          "auth_mode" => "chatgptAuthTokens",
          "tokens" => %{
            "access_token" => fake_jwt(%{"exp" => 1_800_000_000}),
            "refresh_token" => "",
            "id_token" =>
              fake_jwt(%{
                "https://api.openai.com/auth" => %{
                  "chatgpt_account_id" => "acct_123",
                  "chatgpt_plan_type" => "team"
                }
              })
          }
        })
      )

      assert {:ok, %Store.Record{} = auth} =
               Store.load(codex_home: codex_home, codex_home_explicit?: true)

      assert auth.auth_mode == :chatgpt_auth_tokens
      assert auth.tokens.chatgpt_account_id == "acct_123"
      assert auth.tokens.plan_type == "team"
      assert %DateTime{} = auth.tokens.expires_at
    end

    test "normalizes hc plan claims to enterprise", %{codex_home: codex_home} do
      File.write!(
        Path.join(codex_home, "auth.json"),
        Jason.encode!(%{
          "auth_mode" => "chatgpt",
          "tokens" => %{
            "access_token" => "chatgpt-access-token",
            "refresh_token" => "refresh-token",
            "id_token" =>
              fake_jwt(%{"https://api.openai.com/auth" => %{"chatgpt_plan_type" => "hc"}})
          }
        })
      )

      assert {:ok, %Store.Record{} = auth} =
               Store.load(codex_home: codex_home, codex_home_explicit?: true)

      assert auth.tokens.plan_type == "enterprise"
    end
  end

  describe "write/2 and delete/1" do
    test "persists upstream-compatible auth.json atomically and deletes it", %{
      codex_home: codex_home
    } do
      record = %Store.Record{
        auth_mode: :chatgpt,
        openai_api_key: "access-token",
        last_refresh: ~U[2026-03-16 00:00:00Z],
        tokens: %Store.Tokens{
          access_token: "access-token",
          refresh_token: "refresh-token",
          id_token:
            fake_jwt(%{
              "email" => "dev@example.com",
              "https://api.openai.com/auth" => %{
                "chatgpt_account_id" => "acct_123",
                "chatgpt_user_id" => "user_123",
                "chatgpt_plan_type" => "business"
              }
            }),
          account_id: "acct_123"
        }
      }

      assert :ok = Store.write(record, codex_home: codex_home)

      path = Path.join(codex_home, "auth.json")
      assert File.exists?(path)
      refute File.exists?(path <> ".tmp")

      assert {:ok, decoded} = path |> File.read() |> then(&match_json(&1))
      assert decoded["auth_mode"] == "chatgpt"
      assert decoded["OPENAI_API_KEY"] == "access-token"
      assert decoded["tokens"]["access_token"] == "access-token"
      assert decoded["tokens"]["refresh_token"] == "refresh-token"
      assert decoded["tokens"]["account_id"] == "acct_123"
      assert decoded["last_refresh"] == "2026-03-16T00:00:00Z"

      assert :ok = Store.delete(codex_home: codex_home)
      refute File.exists?(path)
    end
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

  defp match_json({:ok, contents}), do: Jason.decode(contents)
  defp match_json(other), do: other
end
