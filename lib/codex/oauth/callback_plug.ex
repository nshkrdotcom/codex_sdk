defmodule Codex.OAuth.CallbackPlug do
  @moduledoc false

  import Plug.Conn

  alias Codex.OAuth.LoopbackServer

  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, opts) do
    conn = fetch_query_params(conn)

    response =
      LoopbackServer.handle_callback(
        Keyword.fetch!(opts, :server),
        conn.request_path,
        conn.query_params
      )

    conn
    |> put_resp_content_type("text/html", "utf-8")
    |> send_resp(response.status, response.body)
  end
end
