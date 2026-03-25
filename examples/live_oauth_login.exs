Mix.Task.run("app.start")

defmodule CodexExamples.LiveOAuthLogin do
  @moduledoc false

  alias Codex.OAuth.Session.{PendingDeviceLogin, PendingLogin}

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
          Mix.raise("OAuth example failed: #{format_error(reason)}")
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
          with {:ok, result} <- interactive_login(config, oauth_opts) do
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

  defp interactive_login(config, oauth_opts) do
    login_opts = oauth_opts ++ login_flow_opts(config)

    case Codex.OAuth.begin_login(login_opts) do
      {:ok, %PendingLogin{} = pending} ->
        print_warnings(pending.warnings)
        print_browser_login(pending, config)
        :ok = maybe_open_browser(pending, config)
        handle_browser_await(Codex.OAuth.await_login(pending), pending, config)

      {:ok, %PendingDeviceLogin{} = pending} ->
        print_warnings(pending.warnings)
        print_device_login(pending)
        Codex.OAuth.await_login(pending)

      {:error, _} = error ->
        error
    end
  end

  defp handle_browser_await({:ok, result}, _pending, _config), do: {:ok, result}

  defp handle_browser_await({:error, :timeout}, %PendingLogin{} = pending, %{flow: :auto}) do
    {:error,
     {:browser_login_timeout,
      "browser login timed out; open the printed URL manually or rerun with --device",
      pending.authorize_url}}
  end

  defp handle_browser_await({:error, :timeout}, %PendingLogin{} = pending, _config) do
    {:error,
     {:browser_login_timeout, "browser login timed out; open the printed URL manually",
      pending.authorize_url}}
  end

  defp handle_browser_await({:error, _} = error, _pending, _config), do: error

  defp maybe_open_browser(_pending, %{open_browser?: false}) do
    IO.puts("browser auto-open: disabled (--no-browser)")
    :ok
  end

  defp maybe_open_browser(%PendingLogin{} = pending, _config) do
    case Codex.OAuth.open_in_browser(pending) do
      :ok ->
        IO.puts("browser auto-open: launched")
        :ok

      {:error, reason} ->
        IO.puts("browser auto-open failed: #{inspect(reason)}")
        IO.puts("Continue by opening the printed authorization URL manually.")
        :ok
    end
  end

  defp print_browser_login(%PendingLogin{} = pending, config) do
    IO.puts("""
    login flow:
      selected: browser_code
      authorize_url: #{pending.authorize_url}
      callback_url: #{pending.redirect_uri}
      opener: #{if(config.open_browser?, do: "auto", else: "manual")}
    """)
  end

  defp print_device_login(%PendingDeviceLogin{} = pending) do
    IO.puts("""
    login flow:
      selected: device_code
      verification_url: #{pending.verification_url}
      user_code: #{pending.user_code}
      expires_at: #{inspect(pending.expires_at)}
    """)
  end

  defp print_warnings(nil), do: :ok

  defp print_warnings(warnings) when is_list(warnings) do
    Enum.each(warnings, &IO.puts("warning: #{&1}"))
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
             codex_path_override: codex_path
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

  defp login_flow_opts(config) do
    []
    |> maybe_put_flow(config.flow)
    |> maybe_put(:callback_port, config.callback_port)
  end

  defp parse_args(argv) do
    Enum.reduce(
      argv,
      %{
        interactive?: false,
        app_server_memory?: false,
        keep_home?: false,
        use_real_home?: false,
        flow: :auto,
        open_browser?: true,
        callback_port: nil
      },
      fn
        "--interactive", acc ->
          %{acc | interactive?: true}

        "--app-server-memory", acc ->
          %{acc | app_server_memory?: true}

        "--keep-home", acc ->
          %{acc | keep_home?: true}

        "--use-real-home", acc ->
          %{acc | use_real_home?: true}

        "--browser", acc ->
          %{acc | flow: :browser}

        "--device", acc ->
          %{acc | flow: :device}

        "--no-browser", acc ->
          %{acc | open_browser?: false}

        arg, acc when is_binary(arg) ->
          parse_option_arg(arg, acc)

        _other, acc ->
          acc
      end
    )
  end

  defp format_error({:browser_login_timeout, message, authorize_url}) do
    "#{message}\nAuthorization URL: #{authorize_url}"
  end

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)

  defp parse_option_arg("--callback-port=" <> value, acc) do
    case Integer.parse(value) do
      {port, ""} when port >= 0 and port <= 65_535 -> %{acc | callback_port: port}
      _ -> Mix.raise("invalid --callback-port value: #{inspect(value)}")
    end
  end

  defp parse_option_arg(_arg, acc), do: acc

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp maybe_put_flow(opts, :auto), do: opts
  defp maybe_put_flow(opts, :browser), do: Keyword.put(opts, :flow, :browser)
  defp maybe_put_flow(opts, :device), do: Keyword.put(opts, :flow, :device)
end

CodexExamples.LiveOAuthLogin.main(System.argv())
