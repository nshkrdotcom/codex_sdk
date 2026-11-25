# Connect only to an independently operated, disposable remote app-server.
Mix.Task.run("app.start")
Code.require_file(Path.expand("support/example_helper.exs", __DIR__))

alias CodexExamples.Support
alias Codex.{AppServer, Thread}

Support.init!()

defmodule CodexExamples.LiveRemoteParity0172 do
  @moduledoc false

  def main do
    case System.get_env("CODEX_PARITY_REMOTE_ADDR") do
      address when is_binary(address) and address != "" -> run(address)
      _ -> IO.puts("SKIPPED: set CODEX_PARITY_REMOTE_ADDR for remote exec")
    end
  end

  defp run(address) do
    token_env = System.get_env("CODEX_PARITY_REMOTE_TOKEN_ENV")
    env = if token_env, do: %{token_env => System.fetch_env!(token_env)}, else: %{}
    opts = Support.codex_options!()

    {:ok, thread} = Codex.start_thread(opts, %{remote: address, remote_auth_token_env: token_env})
    turn_opts = %{timeout_ms: 120_000, env: env}
    {:ok, first} = Thread.run(thread, "Reply exactly OK. Marker: remote-parity-alpha", turn_opts)
    {:ok, second} = Thread.run(first.thread, "Reply exactly OK. Marker: remote-parity-beta", turn_opts)
    true = first.thread.thread_id == second.thread.thread_id
    IO.puts("Remote exec fresh/resume: OK (same thread)")

    if URI.parse(address).scheme in ["ws", "wss"] do
      search(address, Map.get(env, token_env))
    else
      IO.puts("SKIPPED: incremental search needs a WebSocket app-server")
    end
  end

  defp search(address, token) do
    {:ok, conn} =
      AppServer.connect_remote(address,
        auth_token: token,
        experimental_api: true,
        init_timeout_ms: 30_000
      )

    try do
      id_a = "parity-a-#{System.unique_integer([:positive])}"
      id_b = "parity-b-#{System.unique_integer([:positive])}"
      :ok = AppServer.subscribe(conn, methods: ["thread/search/partial"], request_id: id_a)
      a = Task.async(fn -> AppServer.thread_search_stream(conn, id_a, "remote-parity-alpha") end)
      b = Task.async(fn -> AppServer.thread_search_stream(conn, id_b, "remote-parity-beta") end)
      {:ok, result_a} = Task.await(a, 40_000)
      {:ok, result_b} = Task.await(b, 40_000)
      true = is_list(result_a["data"]) and is_list(result_b["data"])
      count = partials(id_a, 0)
      IO.puts("Concurrent streaming search: OK (#{count} matching partials; zero is valid)")
    after
      :ok = AppServer.unsubscribe(conn)
      :ok = AppServer.disconnect(conn)
    end
  end

  defp partials(id, count) do
    receive do
      {:codex_notification, "thread/search/partial", %{"requestId" => ^id}} -> partials(id, count + 1)
      {:codex_notification, "thread/search/partial", _} -> Mix.raise("Cross-search notification")
    after
      0 -> count
    end
  end
end

CodexExamples.LiveRemoteParity0172.main()
