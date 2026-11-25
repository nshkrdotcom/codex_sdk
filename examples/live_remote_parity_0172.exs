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

    thread =
      checked!(
        Codex.start_thread(opts, %{remote: address, remote_auth_token_env: token_env}),
        "thread setup"
      )

    turn_opts = %{timeout_ms: 120_000, env: env}
    run_id = System.unique_integer([:positive])
    marker_a = "remote-parity-alpha-#{run_id}"
    marker_b = "remote-parity-beta-#{run_id}"

    first =
      checked!(
        Thread.run(thread, "Reply exactly OK. Marker: #{marker_a}", turn_opts),
        "fresh turn"
      )

    second =
      checked!(
        Thread.run(first.thread, "Reply exactly OK. Marker: #{marker_b}", turn_opts),
        "resumed turn"
      )

    %Codex.Items.AgentMessage{text: first_text} = first.final_response
    %Codex.Items.AgentMessage{text: second_text} = second.final_response
    true = String.trim(first_text) == "OK" and String.trim(second_text) == "OK"
    thread_id = first.thread.thread_id
    true = is_binary(thread_id) and thread_id != "" and thread_id == second.thread.thread_id
    IO.puts("Remote exec fresh/resume: OK (same thread)")

    if URI.parse(address).scheme in ["ws", "wss"] do
      search(address, Map.get(env, token_env), thread_id, marker_a, marker_b)
    else
      IO.puts("SKIPPED: incremental search needs a WebSocket app-server")
    end
  end

  defp search(address, token, thread_id, marker_a, marker_b) do
    conn =
      checked!(
        AppServer.connect_remote(address,
          auth_token: token,
          experimental_api: true,
          init_timeout_ms: 30_000
        ),
        "WebSocket handshake"
      )

    try do
      id_a = "parity-a-#{System.unique_integer([:positive])}"
      id_b = "parity-b-#{System.unique_integer([:positive])}"
      :ok = AppServer.subscribe(conn, methods: ["thread/search/partial"], request_id: id_a)
      a = Task.async(fn -> AppServer.thread_search_stream(conn, id_a, marker_a) end)
      b = Task.async(fn -> AppServer.thread_search_stream(conn, id_b, marker_b) end)
      result_a = checked!(Task.await(a, 40_000), "first search")
      result_b = checked!(Task.await(b, 40_000), "second search")
      verify_search!(result_a, thread_id, marker_a)
      verify_search!(result_b, thread_id, marker_b)
      count = partials(id_a, 0)
      IO.puts("Concurrent streaming search: OK (#{count} matching partials; zero is valid)")
    after
      :ok = AppServer.unsubscribe(conn)
      :ok = AppServer.disconnect(conn)
    end
  end

  defp verify_search!(%{"data" => rows, "nextCursor" => cursor}, thread_id, marker)
       when is_list(rows) and (is_nil(cursor) or is_binary(cursor)) do
    unless Enum.any?(rows, fn
             %{"thread" => %{"id" => ^thread_id}, "snippet" => snippet} when is_binary(snippet) ->
               String.contains?(snippet, marker)

             _ ->
               false
           end) do
      Mix.raise("Streaming search did not return the expected thread and marker")
    end
  end

  defp verify_search!(_result, _thread_id, _marker), do: Mix.raise("Invalid search response")

  defp checked!({:ok, result}, _step), do: result

  defp checked!({:error, _reason}, step),
    do: Mix.raise("Remote parity check failed during #{step}")

  defp partials(id, count) do
    receive do
      {:codex_notification, "thread/search/partial", %{"requestId" => ^id}} ->
        partials(id, count + 1)

      {:codex_notification, "thread/search/partial", _} ->
        Mix.raise("Cross-search notification")
    after
      0 -> count
    end
  end
end

CodexExamples.LiveRemoteParity0172.main()
