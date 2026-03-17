Mix.Task.run("app.start")

defmodule CodexExamples.LiveOAuthLogin do
  @moduledoc false

  def main(argv) do
    config = parse_args(argv)
    {codex_home, cleanup?} = resolve_codex_home(config)
    process_env = child_env(codex_home)

    try do
      case run(config, codex_home, process_env) do
        :ok ->
          :ok

        {:skip, reason} ->
          IO.puts("SKIPPED: #{reason}")

        {:error, reason} ->
          Mix.raise("OAuth example failed: #{inspect(reason)}")
      end
    after
      if cleanup? do
        File.rm_rf(codex_home)
      end
    end
  end

  defp run(config, codex_home, process_env) do
    oauth_opts = [
      codex_home: codex_home,
      process_env: process_env,
      interactive?: config.interactive?
    ]

    IO.puts("OAuth example CODEX_HOME: #{codex_home}")

    with {:ok, status} <- Codex.OAuth.status(oauth_opts) do
      print_status("status", status)

      cond do
        status.authenticated? ->
          :ok = maybe_refresh(oauth_opts, status)
          maybe_run_memory_app_server(config, process_env)

        config.interactive? ->
          with {:ok, result} <- Codex.OAuth.login(oauth_opts) do
            print_login(result)
            :ok = maybe_refresh(oauth_opts, result)
            maybe_run_memory_app_server(config, process_env)
          end

        true ->
          {:skip,
           "no OAuth session found in the isolated CODEX_HOME; rerun with --interactive or point CODEX_OAUTH_EXAMPLE_HOME at an existing session"}
      end
    end
  end

  defp maybe_refresh(oauth_opts, %{auth_mode: auth_mode})
       when auth_mode in [:chatgpt, :chatgpt_auth_tokens] do
    case Codex.OAuth.refresh(oauth_opts) do
      {:ok, status} ->
        print_status("refresh", status)
        :ok

      {:error, reason} ->
        IO.puts("refresh: skipped (#{inspect(reason)})")
        :ok
    end
  end

  defp maybe_refresh(_oauth_opts, _result) do
    IO.puts("refresh: skipped (not a ChatGPT OAuth session)")
    :ok
  end

  defp maybe_run_memory_app_server(%{app_server_memory?: false}, _process_env), do: :ok

  defp maybe_run_memory_app_server(%{interactive?: interactive?}, process_env) do
    with {:ok, codex_path} <- fetch_codex_path(),
         :ok <- ensure_app_server_supported(codex_path),
         {:ok, codex_opts} <-
           Codex.Options.new(%{
             codex_path_override: codex_path,
             reasoning_effort: :low
           }),
         {:ok, conn} <-
           Codex.AppServer.connect(codex_opts,
             experimental_api: true,
             process_env: process_env,
             oauth: [
               mode: :auto,
               storage: :memory,
               auto_refresh: true,
               interactive?: interactive?
             ]
           ) do
      try do
        IO.puts("memory-mode app-server connect: ok")
        IO.inspect(Codex.AppServer.Account.read(conn), label: "account/read")
        :ok
      after
        :ok = Codex.AppServer.disconnect(conn)
      end
    else
      {:skip, reason} ->
        IO.puts("memory-mode app-server: skipped (#{reason})")
        :ok

      {:error, reason} ->
        IO.puts("memory-mode app-server: failed (#{inspect(reason)})")
        :ok
    end
  end

  defp print_login(result) do
    IO.puts("""
    login:
      provider: #{result.provider}
      flow_used: #{result.flow_used}
      storage_used: #{result.storage_used}
      auth_mode: #{result.auth_mode}
      account_id: #{inspect(result.account_id)}
      plan_type: #{inspect(result.plan_type)}
      persisted?: #{result.persisted?}
    """)
  end

  defp print_status(label, status) do
    IO.puts("""
    #{label}:
      authenticated?: #{status.authenticated?}
      auth_mode: #{inspect(status.auth_mode)}
      storage_used: #{inspect(status.storage_used)}
      account_id: #{inspect(status.account_id)}
      plan_type: #{inspect(status.plan_type)}
      persisted?: #{inspect(status.persisted?)}
    """)
  end

  defp resolve_codex_home(%{use_real_home?: true}) do
    {Codex.Auth.codex_home(), false}
  end

  defp resolve_codex_home(config) do
    case System.get_env("CODEX_OAUTH_EXAMPLE_HOME") do
      value when is_binary(value) and value != "" ->
        File.mkdir_p!(value)
        {value, false}

      _ ->
        codex_home =
          Path.join(
            System.tmp_dir!(),
            "codex_sdk_oauth_example_#{System.unique_integer([:positive])}"
          )

        File.mkdir_p!(codex_home)
        {codex_home, not config.keep_home?}
    end
  end

  defp fetch_codex_path do
    case System.get_env("CODEX_PATH") || System.find_executable("codex") do
      nil -> {:skip, "install the `codex` CLI or set CODEX_PATH"}
      path -> {:ok, path}
    end
  end

  defp ensure_app_server_supported(codex_path) do
    {_output, status} = System.cmd(codex_path, ["app-server", "--help"], stderr_to_stdout: true)

    if status == 0 do
      :ok
    else
      {:skip, "your `codex` CLI does not support `codex app-server`"}
    end
  end

  defp child_env(codex_home) do
    %{
      "CODEX_HOME" => codex_home,
      "HOME" => codex_home,
      "USERPROFILE" => codex_home
    }
  end

  defp parse_args(argv) do
    Enum.reduce(
      argv,
      %{interactive?: false, app_server_memory?: false, keep_home?: false, use_real_home?: false},
      fn
        "--interactive", acc -> %{acc | interactive?: true}
        "--app-server-memory", acc -> %{acc | app_server_memory?: true}
        "--keep-home", acc -> %{acc | keep_home?: true}
        "--use-real-home", acc -> %{acc | use_real_home?: true}
        _other, acc -> acc
      end
    )
  end
end

CodexExamples.LiveOAuthLogin.main(System.argv())
