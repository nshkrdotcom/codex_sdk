# Stable 0.172.0 app-server parity; mutations are opt-in and disposable.
Mix.Task.run("app.start")
Code.require_file(Path.expand("support/example_helper.exs", __DIR__))

alias CodexExamples.Support
alias Codex.{AppServer, Thread}

Support.init!()

defmodule CodexExamples.LiveParity0172 do
  @moduledoc false

  def main do
    case Support.codex_options(%{}, missing_cli: :skip) do
      {:skip, reason} -> IO.puts("SKIPPED: #{reason}")
      {:ok, opts} -> run(opts)
      {:error, _reason} -> Mix.raise("Unable to construct Codex options")
    end
  end

  defp run(opts) do
    :ok = Support.ensure_app_server_supported(opts)
    {:ok, conn} = AppServer.connect(opts, experimental_api: true, init_timeout_ms: 30_000)

    try do
      {:ok, providers} = AppServer.model_provider_list(conn)
      true = is_map(providers)
      {:ok, %{"data" => []}} = AppServer.thread_list(conn, included_thread_ids: [])
      IO.puts("Provider inventory and empty inclusion filter: OK")

      if System.get_env("CODEX_PARITY_HISTORY") == "1" do
        history(conn, opts)
      else
        IO.puts("SKIPPED: disposable history/goal scenario (CODEX_PARITY_HISTORY=1)")
      end

      if System.get_env("CODEX_PARITY_BEDROCK_DISCOVERY") == "1" do
        {:ok, discovery} = AppServer.Account.bedrock_discover(conn)
        true = is_map(discovery)
        IO.puts("Bedrock credential discovery: OK (values not printed)")
      else
        IO.puts("SKIPPED: Bedrock discovery (CODEX_PARITY_BEDROCK_DISCOVERY=1)")
      end
    after
      :ok = AppServer.disconnect(conn)
    end
  end

  defp history(conn, opts) do
    marker = "parity-marker-#{System.unique_integer([:positive])}"

    {:ok, thread} =
      Codex.start_thread(
        opts,
        Support.thread_opts!(%{
          transport: {:app_server, conn},
          working_directory: Support.example_working_directory(),
          history_mode: :paginated,
          ephemeral: false
        })
      )

    result =
      case Thread.run(thread, "Reply exactly OK. Marker: #{marker}", %{timeout_ms: 120_000}) do
        {:ok, result} -> result
        {:error, _reason} -> Mix.raise("Unable to complete the disposable history turn")
      end

    id = result.thread.thread_id

    try do
      {:ok, %{"data" => [found | _]}} = AppServer.thread_search(conn, marker)
      true = found["thread"]["id"] == id
      {:ok, %{"data" => [_ | _]}} =
        AppServer.thread_search_occurrences(conn, id, marker, limit: 10)
      IO.puts("Persisted thread search and occurrence lookup: OK")

      if System.get_env("CODEX_PARITY_GOALS") == "1" do
        goals(conn, id)
      else
        IO.puts("SKIPPED: goals (CODEX_PARITY_GOALS=1 and server goals feature)")
      end
    after
      :ok = AppServer.thread_archive(conn, id)
    end
  end

  defp goals(conn, id) do
    {:ok, %{"goal" => goal}} =
      AppServer.thread_goal_set(conn, id,
        objective: "Disposable parity check",
        status: :paused,
        origin: :user,
        token_budget: 1000
      )

    true = is_map(goal)

    try do
      {:ok, %{"goal" => _}} = AppServer.thread_goal_set(conn, id, token_budget: nil, origin: :user)
      {:ok, %{"goal" => %{"tokenBudget" => nil}}} = AppServer.thread_goal_get(conn, id)
      IO.puts("Goal set, read and budget clear: OK")
    after
      {:ok, %{"cleared" => true}} = AppServer.thread_goal_clear(conn, id, origin: :user)
      {:ok, %{"goal" => nil}} = AppServer.thread_goal_get(conn, id)
    end
  end
end

CodexExamples.LiveParity0172.main()
