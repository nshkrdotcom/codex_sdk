defmodule Codex.CLI do
  @moduledoc """
  Thin wrapper around the upstream `codex` terminal client.

  Use this module when you want command-surface parity with the Codex CLI,
  including commands that do not fit the SDK's structured `Codex.Exec` or
  `Codex.AppServer` APIs.

  For long-running or interactive commands, use `start/2` or the helpers that
  return `%Codex.CLI.Session{}`.
  """

  alias Codex.CLI.Session
  alias Codex.Config.Defaults
  alias Codex.Config.Overrides
  alias Codex.Options
  alias Codex.Runtime.Env, as: RuntimeEnv

  @type result :: Session.result()

  @doc """
  Runs a `codex` command synchronously and collects stdout/stderr until exit.
  """
  @spec run([String.t()], keyword()) :: {:ok, result()} | {:error, term()}
  def run(args, opts \\ []) when is_list(args) and is_list(opts) do
    input = Keyword.get(opts, :stdin)
    timeout_ms = Keyword.get(opts, :timeout_ms, Defaults.exec_timeout_ms())

    session_opts =
      opts
      |> Keyword.delete(:stdin)
      |> Keyword.put(:stdin, true)

    with {:ok, session} <- start(args, session_opts),
         :ok <- maybe_send_input(session, input),
         :ok <- close_for_sync(session),
         {:ok, result} <- Session.collect(session, timeout_ms) do
      {:ok, result}
    else
      {:error, {:timeout, session}} = error ->
        _ = Session.stop(session)
        error

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Starts a raw `codex` subprocess session.
  """
  @spec start([String.t()], keyword()) :: {:ok, Session.t()} | {:error, term()}
  def start(args, opts \\ []) when is_list(args) and is_list(opts) do
    cwd = resolve_cwd(opts)

    with {:ok, codex_opts} <- normalize_codex_opts(opts),
         {:ok, binary_path} <- Options.codex_path(codex_opts),
         {:ok, env} <- build_env(codex_opts, opts) do
      session_opts = [
        receiver: Keyword.get(opts, :receiver, self()),
        stdin: Keyword.get(opts, :stdin, false),
        pty: Keyword.get(opts, :pty, false),
        cwd: cwd,
        env: env
      ]

      Session.start(binary_path, normalize_args(args), session_opts)
    end
  end

  @doc """
  Launches `codex` in interactive mode (or one-shot prompt mode when `prompt`
  is provided) and returns a raw subprocess session.
  """
  @spec interactive(String.t() | nil | keyword(), keyword()) ::
          {:ok, Session.t()} | {:error, term()}
  def interactive(prompt_or_opts \\ nil, opts \\ [])

  def interactive(opts, []) when is_list(opts) do
    interactive(nil, opts)
  end

  def interactive(prompt, opts) when is_binary(prompt) or is_nil(prompt) do
    with {:ok, global_args} <- global_args(opts) do
      args = global_args ++ maybe_prompt(prompt)
      start(args, Keyword.merge(opts, pty: true, stdin: true))
    end
  end

  @doc """
  Runs `codex app`.
  """
  @spec app(String.t() | nil | keyword(), keyword()) :: {:ok, result()} | {:error, term()}
  def app(path_or_opts \\ nil, opts \\ [])

  def app(opts, []) when is_list(opts), do: app(nil, opts)

  def app(path, opts) when is_binary(path) or is_nil(path) do
    with {:ok, global_args} <- global_args(opts) do
      args =
        ["app"] ++
          global_args ++
          optional_flag("--download-url", Keyword.get(opts, :download_url)) ++
          optional_positional(path)

      run(args, opts)
    end
  end

  @doc """
  Launches `codex app-server`.
  """
  @spec app_server(keyword()) :: {:ok, Session.t()} | {:error, term()}
  def app_server(opts \\ []) when is_list(opts) do
    with {:ok, global_args} <- global_args(opts) do
      args =
        ["app-server"] ++ global_args ++ optional_flag("--listen", Keyword.get(opts, :listen))

      start(args, Keyword.merge(opts, stdin: true))
    end
  end

  @doc """
  Runs `codex apply TASK_ID`.
  """
  @spec apply(String.t(), keyword()) :: {:ok, result()} | {:error, term()}
  def apply(task_id, opts \\ []) when is_binary(task_id) and is_list(opts) do
    with {:ok, global_args} <- global_args(opts) do
      run(["apply"] ++ global_args ++ [task_id], opts)
    end
  end

  @doc """
  Launches the interactive `codex cloud` picker.
  """
  @spec cloud(keyword()) :: {:ok, Session.t()} | {:error, term()}
  def cloud(opts \\ []) when is_list(opts) do
    with {:ok, global_args} <- global_args(opts) do
      start(["cloud"] ++ global_args, Keyword.merge(opts, pty: true, stdin: true))
    end
  end

  @doc """
  Runs `codex cloud list`.
  """
  @spec cloud_list(keyword()) :: {:ok, result()} | {:error, term()}
  def cloud_list(opts \\ []) when is_list(opts) do
    with {:ok, global_args} <- global_args(opts) do
      args =
        ["cloud", "list"] ++
          global_args ++
          optional_flag("--cursor", Keyword.get(opts, :cursor)) ++
          optional_flag("--env", Keyword.get(opts, :env_id)) ++
          optional_boolean("--json", Keyword.get(opts, :json)) ++
          optional_flag("--limit", Keyword.get(opts, :limit))

      run(args, opts)
    end
  end

  @doc """
  Runs `codex cloud exec`.
  """
  @spec cloud_exec(String.t(), keyword()) :: {:ok, result()} | {:error, term()}
  def cloud_exec(query, opts \\ []) when is_binary(query) and is_list(opts) do
    with {:ok, global_args} <- global_args(opts) do
      args =
        ["cloud", "exec"] ++
          global_args ++
          required_flag("--env", Keyword.get(opts, :env_id)) ++
          optional_flag("--attempts", Keyword.get(opts, :attempts)) ++
          [query]

      run(args, opts)
    end
  end

  @doc """
  Runs `codex completion`.
  """
  @spec completion(String.t(), keyword()) :: {:ok, result()} | {:error, term()}
  def completion(shell, opts \\ []) when is_binary(shell) and is_list(opts) do
    with {:ok, global_args} <- global_args(opts) do
      run(["completion"] ++ global_args ++ [shell], opts)
    end
  end

  @doc """
  Runs `codex debug app-server send-message-v2`.
  """
  @spec debug_app_server_send_message_v2(String.t(), keyword()) ::
          {:ok, result()} | {:error, term()}
  def debug_app_server_send_message_v2(message, opts \\ [])
      when is_binary(message) and is_list(opts) do
    with {:ok, global_args} <- global_args(opts) do
      run(["debug", "app-server", "send-message-v2"] ++ global_args ++ [message], opts)
    end
  end

  @doc """
  Runs `codex execpolicy check`.
  """
  @spec execpolicy_check([String.t()] | String.t(), keyword()) ::
          {:ok, result()} | {:error, term()}
  def execpolicy_check(command, opts \\ []) when is_list(opts) do
    command = normalize_command(command)

    with {:ok, global_args} <- global_args(opts) do
      args =
        ["execpolicy", "check"] ++
          global_args ++
          optional_boolean("--pretty", Keyword.get(opts, :pretty)) ++
          repeat_flag("--rules", Keyword.get(opts, :rules, [])) ++
          ["--"] ++ command

      run(args, opts)
    end
  end

  @doc """
  Runs `codex features list`.
  """
  @spec features_list(keyword()) :: {:ok, result()} | {:error, term()}
  def features_list(opts \\ []) when is_list(opts) do
    with {:ok, global_args} <- global_args(opts) do
      run(["features", "list"] ++ global_args, opts)
    end
  end

  @doc """
  Runs `codex features enable FEATURE`.
  """
  @spec features_enable(String.t(), keyword()) :: {:ok, result()} | {:error, term()}
  def features_enable(feature, opts \\ []) when is_binary(feature) and is_list(opts) do
    with {:ok, global_args} <- global_args(opts) do
      run(["features", "enable"] ++ global_args ++ [feature], opts)
    end
  end

  @doc """
  Runs `codex features disable FEATURE`.
  """
  @spec features_disable(String.t(), keyword()) :: {:ok, result()} | {:error, term()}
  def features_disable(feature, opts \\ []) when is_binary(feature) and is_list(opts) do
    with {:ok, global_args} <- global_args(opts) do
      run(["features", "disable"] ++ global_args ++ [feature], opts)
    end
  end

  @doc """
  Runs `codex login`.
  """
  @spec login(:chatgpt | :device_auth | {:api_key, String.t()} | keyword(), keyword()) ::
          {:ok, result()} | {:error, term()}
  def login(mode_or_opts \\ :chatgpt, opts \\ [])

  def login(opts, []) when is_list(opts), do: login(:chatgpt, opts)

  def login({:api_key, api_key}, opts) when is_binary(api_key) and is_list(opts) do
    with {:ok, global_args} <- global_args(opts) do
      run(
        ["login"] ++ global_args ++ ["--with-api-key"],
        Keyword.put(opts, :stdin, ensure_newline(api_key))
      )
    end
  end

  def login(:device_auth, opts) when is_list(opts) do
    with {:ok, global_args} <- global_args(opts) do
      run(["login"] ++ global_args ++ ["--device-auth"], opts)
    end
  end

  def login(:chatgpt, opts) when is_list(opts) do
    with {:ok, global_args} <- global_args(opts) do
      run(["login"] ++ global_args, opts)
    end
  end

  @doc """
  Runs `codex login status`.
  """
  @spec login_status(keyword()) :: {:ok, result()} | {:error, term()}
  def login_status(opts \\ []) when is_list(opts) do
    with {:ok, global_args} <- global_args(opts) do
      run(["login", "status"] ++ global_args, opts)
    end
  end

  @doc """
  Runs `codex logout`.
  """
  @spec logout(keyword()) :: {:ok, result()} | {:error, term()}
  def logout(opts \\ []) when is_list(opts) do
    with {:ok, global_args} <- global_args(opts) do
      run(["logout"] ++ global_args, opts)
    end
  end

  @doc """
  Runs `codex mcp add`.
  """
  @spec mcp_add(String.t(), {:command, [String.t()]} | {:url, String.t()}, keyword()) ::
          {:ok, result()} | {:error, term()}
  def mcp_add(name, {:command, command}, opts)
      when is_binary(name) and is_list(command) and is_list(opts) do
    mcp_env = Keyword.get(opts, :env, [])

    with {:ok, global_args} <- global_args(opts) do
      args =
        ["mcp", "add", name] ++
          global_args ++
          repeat_flag("--env", mcp_env) ++
          ["--"] ++ normalize_args(command)

      run(args, Keyword.delete(opts, :env))
    end
  end

  def mcp_add(name, {:url, url}, opts)
      when is_binary(name) and is_binary(url) and is_list(opts) do
    with {:ok, global_args} <- global_args(opts) do
      args =
        ["mcp", "add", name] ++
          global_args ++
          ["--url", url] ++
          optional_flag("--bearer-token-env-var", Keyword.get(opts, :bearer_token_env_var))

      run(args, opts)
    end
  end

  @doc """
  Runs `codex mcp get`.
  """
  @spec mcp_get(String.t(), keyword()) :: {:ok, result()} | {:error, term()}
  def mcp_get(name, opts \\ []) when is_binary(name) and is_list(opts) do
    with {:ok, global_args} <- global_args(opts) do
      args =
        ["mcp", "get", name] ++
          global_args ++ optional_boolean("--json", Keyword.get(opts, :json))

      run(args, opts)
    end
  end

  @doc """
  Runs `codex mcp list`.
  """
  @spec mcp_list(keyword()) :: {:ok, result()} | {:error, term()}
  def mcp_list(opts \\ []) when is_list(opts) do
    with {:ok, global_args} <- global_args(opts) do
      args =
        ["mcp", "list"] ++ global_args ++ optional_boolean("--json", Keyword.get(opts, :json))

      run(args, opts)
    end
  end

  @doc """
  Runs `codex mcp login`.
  """
  @spec mcp_login(String.t(), keyword()) :: {:ok, result()} | {:error, term()}
  def mcp_login(name, opts \\ []) when is_binary(name) and is_list(opts) do
    scopes =
      case Keyword.get(opts, :scopes, []) do
        values when is_list(values) -> Enum.join(values, ",")
        value -> value
      end

    with {:ok, global_args} <- global_args(opts) do
      args =
        ["mcp", "login", name] ++ global_args ++ optional_flag("--scopes", scopes)

      run(args, opts)
    end
  end

  @doc """
  Runs `codex mcp logout`.
  """
  @spec mcp_logout(String.t(), keyword()) :: {:ok, result()} | {:error, term()}
  def mcp_logout(name, opts \\ []) when is_binary(name) and is_list(opts) do
    with {:ok, global_args} <- global_args(opts) do
      run(["mcp", "logout", name] ++ global_args, opts)
    end
  end

  @doc """
  Runs `codex mcp remove`.
  """
  @spec mcp_remove(String.t(), keyword()) :: {:ok, result()} | {:error, term()}
  def mcp_remove(name, opts \\ []) when is_binary(name) and is_list(opts) do
    with {:ok, global_args} <- global_args(opts) do
      run(["mcp", "remove", name] ++ global_args, opts)
    end
  end

  @doc """
  Launches `codex mcp-server`.
  """
  @spec mcp_server(keyword()) :: {:ok, Session.t()} | {:error, term()}
  def mcp_server(opts \\ []) when is_list(opts) do
    with {:ok, global_args} <- global_args(opts) do
      start(["mcp-server"] ++ global_args, Keyword.merge(opts, stdin: true))
    end
  end

  @doc """
  Launches `codex resume`.
  """
  @spec resume(String.t() | :last | keyword() | nil, keyword()) ::
          {:ok, Session.t()} | {:error, term()}
  def resume(target_or_opts \\ nil, opts \\ [])

  def resume(opts, []) when is_list(opts), do: resume(nil, opts)

  def resume(target, opts) when is_binary(target) or target in [:last, nil] do
    with {:ok, global_args} <- global_args(opts) do
      args =
        ["resume"] ++
          global_args ++
          optional_boolean("--all", Keyword.get(opts, :all)) ++ resume_target(target)

      start(args, Keyword.merge(opts, pty: true, stdin: true))
    end
  end

  @doc """
  Launches `codex fork`.
  """
  @spec fork(String.t() | :last | keyword() | nil, keyword()) ::
          {:ok, Session.t()} | {:error, term()}
  def fork(target_or_opts \\ nil, opts \\ [])

  def fork(opts, []) when is_list(opts), do: fork(nil, opts)

  def fork(target, opts) when is_binary(target) or target in [:last, nil] do
    with {:ok, global_args} <- global_args(opts) do
      args =
        ["fork"] ++
          global_args ++ optional_boolean("--all", Keyword.get(opts, :all)) ++ fork_target(target)

      start(args, Keyword.merge(opts, pty: true, stdin: true))
    end
  end

  @doc """
  Runs `codex sandbox`.
  """
  @spec sandbox([String.t()] | String.t(), keyword()) :: {:ok, result()} | {:error, term()}
  def sandbox(command, opts \\ []) when is_list(opts) do
    command = normalize_command(command)

    with {:ok, global_args} <- global_args(opts) do
      run(["sandbox"] ++ global_args ++ ["--"] ++ command, opts)
    end
  end

  defp normalize_codex_opts(opts) do
    case Keyword.get(opts, :codex_opts) || Keyword.get(opts, :options) do
      %Options{} = codex_opts ->
        {:ok, codex_opts}

      nil ->
        Options.new(%{
          api_key: Keyword.get(opts, :api_key),
          base_url: Keyword.get(opts, :base_url),
          codex_path_override:
            Keyword.get(opts, :codex_path_override, Keyword.get(opts, :codex_path))
        })

      attrs when is_list(attrs) or is_map(attrs) ->
        Options.new(attrs)

      other ->
        {:error, {:invalid_codex_opts, other}}
    end
  end

  defp build_env(%Options{} = codex_opts, opts) do
    process_env = Keyword.get(opts, :process_env, Keyword.get(opts, :env, %{}))

    with {:ok, custom_env} <- normalize_process_env(process_env) do
      base_env =
        RuntimeEnv.base_overrides(codex_opts.api_key, codex_opts.base_url)

      merged =
        base_env
        |> Map.merge(custom_env, fn _key, _base, custom -> custom end)

      env =
        if Keyword.get(opts, :clear_env?, false) do
          [:clear | preserved_env() ++ Map.to_list(merged)]
        else
          preserved_env() ++ Map.to_list(merged)
        end

      {:ok, env}
    end
  end

  defp normalize_process_env(nil), do: {:ok, %{}}
  defp normalize_process_env(%{} = env), do: {:ok, stringify_map(env)}

  defp normalize_process_env(env) when is_list(env) do
    if Keyword.keyword?(env) do
      {:ok, env |> Map.new() |> stringify_map()}
    else
      {:error, {:invalid_env, env}}
    end
  end

  defp normalize_process_env(env), do: {:error, {:invalid_env, env}}

  defp stringify_map(map) do
    map
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Enum.into(%{}, fn {key, value} -> {to_string(key), to_string(value)} end)
  end

  defp preserved_env do
    Defaults.preserved_env_keys()
    |> Enum.reduce([], fn key, acc ->
      case System.get_env(key) do
        nil -> acc
        value -> acc ++ [{key, value}]
      end
    end)
  end

  defp global_args(opts) do
    with {:ok, config_args} <- config_args(opts) do
      {:ok,
       optional_flag("--cd", Keyword.get(opts, :cd, Keyword.get(opts, :working_directory))) ++
         repeat_flag(
           "--add-dir",
           Keyword.get(opts, :add_dir, Keyword.get(opts, :additional_directories, []))
         ) ++
         optional_flag(
           "--ask-for-approval",
           normalize_approval(Keyword.get(opts, :ask_for_approval))
         ) ++
         optional_boolean(
           "--dangerously-bypass-approvals-and-sandbox",
           Keyword.get(opts, :dangerously_bypass_approvals_and_sandbox) ||
             Keyword.get(opts, :yolo)
         ) ++
         repeat_flag("--disable", Keyword.get(opts, :disable, [])) ++
         repeat_flag("--enable", Keyword.get(opts, :enable, [])) ++
         optional_boolean("--full-auto", Keyword.get(opts, :full_auto)) ++
         repeat_flag("--image", Keyword.get(opts, :image, Keyword.get(opts, :images, []))) ++
         optional_flag("--model", Keyword.get(opts, :model)) ++
         optional_boolean("--no-alt-screen", Keyword.get(opts, :no_alt_screen)) ++
         optional_boolean("--oss", Keyword.get(opts, :oss)) ++
         optional_flag("--profile", Keyword.get(opts, :profile)) ++
         optional_flag("--sandbox", normalize_sandbox(Keyword.get(opts, :sandbox))) ++
         optional_boolean("--search", Keyword.get(opts, :search)) ++
         config_args}
    end
  end

  defp config_args(opts) do
    [Keyword.get(opts, :config), Keyword.get(opts, :config_overrides)]
    |> Enum.reduce_while({:ok, []}, fn source, {:ok, acc} ->
      case Overrides.normalize_config_overrides(source) do
        {:ok, normalized} -> {:cont, {:ok, acc ++ normalized}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, normalized} -> {:ok, Overrides.cli_args(normalized)}
      {:error, _} = error -> error
    end
  end

  defp maybe_send_input(_session, nil), do: :ok

  defp maybe_send_input(session, data) do
    Session.send_input(session, data)
  end

  defp close_for_sync(session) do
    case Session.close_input(session) do
      :ok -> :ok
      {:error, :stdin_unavailable} -> :ok
      {:error, _} = error -> error
    end
  end

  defp resolve_cwd(opts), do: Keyword.get(opts, :cwd)

  defp normalize_args(args), do: Enum.map(args, &to_string/1)

  defp normalize_command(command) when is_binary(command), do: [command]
  defp normalize_command(command) when is_list(command), do: normalize_args(command)

  defp normalize_sandbox(nil), do: nil
  defp normalize_sandbox(:read_only), do: "read-only"
  defp normalize_sandbox(:workspace_write), do: "workspace-write"
  defp normalize_sandbox(:danger_full_access), do: "danger-full-access"
  defp normalize_sandbox(:strict), do: "read-only"
  defp normalize_sandbox(:permissive), do: "danger-full-access"
  defp normalize_sandbox(value) when is_binary(value), do: value
  defp normalize_sandbox(value), do: to_string(value)

  defp normalize_approval(nil), do: nil

  defp normalize_approval(value) when is_atom(value),
    do: value |> Atom.to_string() |> String.replace("_", "-")

  defp normalize_approval(value) when is_binary(value), do: value
  defp normalize_approval(value), do: to_string(value)

  defp maybe_prompt(prompt) when is_binary(prompt) and prompt != "", do: [prompt]
  defp maybe_prompt(_prompt), do: []

  defp optional_flag(_name, nil), do: []
  defp optional_flag(name, value), do: [name, to_string(value)]

  defp required_flag(name, nil), do: raise(ArgumentError, "missing required option for #{name}")
  defp required_flag(name, value), do: [name, to_string(value)]

  defp optional_positional(nil), do: []
  defp optional_positional(value), do: [to_string(value)]

  defp optional_boolean(_name, value) when value in [false, nil], do: []
  defp optional_boolean(name, true), do: [name]

  defp repeat_flag(_name, nil), do: []

  defp repeat_flag(name, values) when is_list(values) do
    Enum.flat_map(values, fn value -> [name, to_string(value)] end)
  end

  defp repeat_flag(name, value), do: [name, to_string(value)]

  defp resume_target(:last), do: ["--last"]
  defp resume_target(target) when is_binary(target), do: [target]
  defp resume_target(_), do: []

  defp fork_target(:last), do: ["--last"]
  defp fork_target(target) when is_binary(target), do: [target]
  defp fork_target(_), do: []

  defp ensure_newline(value) do
    if String.ends_with?(value, "\n"), do: value, else: value <> "\n"
  end
end
