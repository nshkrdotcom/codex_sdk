defmodule Codex.ExamplesSupport do
  @moduledoc false

  alias CliSubprocessCore.ExecutionSurface
  alias Codex.Items
  alias Codex.Models
  alias Codex.Options
  alias Codex.Thread.Options, as: ThreadOptions
  alias Codex.Turn.Result

  defmodule SSHContext do
    @moduledoc false

    @enforce_keys [:argv]
    defstruct argv: [],
              execution_surface: nil,
              example_cwd: nil,
              example_danger_full_access: false,
              ssh_host: nil,
              ssh_user: nil,
              ssh_port: nil,
              ssh_identity_file: nil

    @type t :: %__MODULE__{
            argv: [String.t()],
            execution_surface: ExecutionSurface.t() | nil,
            example_cwd: String.t() | nil,
            example_danger_full_access: boolean(),
            ssh_host: String.t() | nil,
            ssh_user: String.t() | nil,
            ssh_port: pos_integer() | nil,
            ssh_identity_file: String.t() | nil
          }
  end

  @context_key {__MODULE__, :ssh_context}
  @example_ssh_options %{
    "BatchMode" => "yes",
    "ConnectTimeout" => 10
  }
  @ssh_switches [
    cwd: :string,
    danger_full_access: :boolean,
    ssh_host: :string,
    ssh_identity_file: :string,
    ssh_port: :integer,
    ssh_user: :string
  ]

  @spec ollama_mode?() :: boolean()
  def ollama_mode? do
    System.get_env("CODEX_PROVIDER_BACKEND") == "oss" and
      System.get_env("CODEX_OSS_PROVIDER") == "ollama"
  end

  @spec ollama_model() :: String.t()
  def ollama_model do
    System.get_env("CODEX_MODEL") || "gpt-oss:20b"
  end

  @spec example_model(String.t() | nil) :: String.t() | nil
  def example_model(default \\ System.get_env("CODEX_MODEL")) do
    if ollama_mode?(), do: ollama_model(), else: default
  end

  @spec example_reasoning(Models.reasoning_effort() | nil) :: Models.reasoning_effort() | nil
  def example_reasoning(default \\ Models.default_reasoning_effort()) do
    if ollama_mode?(), do: nil, else: default
  end

  @spec conversation_default_mode() :: :multi_turn | :save_resume
  def conversation_default_mode do
    if ollama_mode?(), do: :save_resume, else: :multi_turn
  end

  @spec init_example!([String.t()]) :: SSHContext.t()
  def init_example!(argv \\ System.argv()) when is_list(argv) do
    case Process.get(@context_key) do
      %SSHContext{} = context ->
        context

      nil ->
        case parse_argv(argv) do
          {:ok, %SSHContext{} = context} ->
            System.argv(context.argv)
            Process.put(@context_key, context)
            context

          {:error, message} ->
            raise ArgumentError, message
        end
    end
  end

  @spec context() :: SSHContext.t()
  def context do
    case Process.get(@context_key) do
      %SSHContext{} = context -> context
      _ -> init_example!()
    end
  end

  @spec parse_argv([String.t()]) :: {:ok, SSHContext.t()} | {:error, String.t()}
  def parse_argv(argv) when is_list(argv) do
    {parsed, remaining, invalid} =
      argv
      |> Enum.reject(&(&1 == "--"))
      |> OptionParser.parse(strict: @ssh_switches)

    if invalid != [] do
      {:error, invalid_options_message(invalid)}
    else
      build_context(parsed, remaining)
    end
  end

  @spec ssh_enabled?() :: boolean()
  def ssh_enabled?, do: match?(%SSHContext{execution_surface: %ExecutionSurface{}}, context())

  @spec nonlocal_path_execution_surface?() :: boolean()
  def nonlocal_path_execution_surface? do
    ExecutionSurface.nonlocal_path_surface?(execution_surface())
  end

  @spec danger_full_access?() :: boolean()
  def danger_full_access?, do: context().example_danger_full_access == true

  @spec execution_surface() :: ExecutionSurface.t() | nil
  def execution_surface, do: context().execution_surface

  @spec command_opts(keyword()) :: keyword()
  def command_opts(opts \\ []) when is_list(opts) do
    opts
    |> maybe_put_command_execution_surface()
    |> maybe_put_command_working_directory()
    |> maybe_put_command_danger_full_access()
  end

  @spec example_working_directory() :: String.t() | nil
  def example_working_directory do
    case context().example_cwd do
      cwd when is_binary(cwd) and cwd != "" ->
        cwd

      _ ->
        if nonlocal_path_execution_surface?(), do: nil, else: File.cwd!()
    end
  end

  @spec remote_working_directory_configured?() :: boolean()
  def remote_working_directory_configured? do
    case context().example_cwd do
      cwd when is_binary(cwd) -> String.trim(cwd) != ""
      _ -> false
    end
  end

  @spec ensure_remote_working_directory(String.t()) :: :ok | {:skip, String.t()}
  def ensure_remote_working_directory(
        message \\ "this SSH app-server example requires --cwd <remote trusted directory> because app-server thread start does not expose --skip-git-repo-check"
      ) do
    if ssh_enabled?() and not remote_working_directory_configured?(),
      do: {:skip, message},
      else: :ok
  end

  @spec ensure_local_execution_surface(String.t()) :: :ok | {:skip, String.t()}
  def ensure_local_execution_surface(
        message \\ "this example uses local host resources and does not support --ssh-host"
      ) do
    if ssh_enabled?(), do: {:skip, message}, else: :ok
  end

  @spec thread_opts!(map() | keyword() | ThreadOptions.t()) :: ThreadOptions.t()
  def thread_opts!(attrs \\ %{}) do
    case thread_opts(attrs) do
      {:ok, %ThreadOptions{} = options} ->
        options

      {:error, reason} ->
        raise ArgumentError, "invalid Codex example thread options: #{inspect(reason)}"
    end
  end

  @spec thread_opts(map() | keyword() | ThreadOptions.t()) ::
          {:ok, ThreadOptions.t()} | {:error, term()}
  def thread_opts(%ThreadOptions{} = attrs) do
    attrs
    |> Map.from_struct()
    |> thread_opts()
  end

  def thread_opts(attrs) when is_list(attrs), do: attrs |> Map.new() |> thread_opts()

  def thread_opts(attrs) when is_map(attrs) do
    attrs
    |> maybe_put_example_working_directory()
    |> maybe_put_skip_git_repo_check()
    |> maybe_put_thread_danger_full_access()
    |> ThreadOptions.new()
  end

  @spec codex_options!(map() | keyword(), keyword()) :: Options.t()
  def codex_options!(attrs \\ %{}, opts \\ []) do
    case codex_options(attrs, opts) do
      {:ok, %Options{} = options} ->
        options

      {:skip, reason} ->
        raise ArgumentError, reason

      {:error, reason} ->
        raise ArgumentError, "invalid Codex example options: #{inspect(reason)}"
    end
  end

  @spec codex_options(map() | keyword(), keyword()) ::
          {:ok, Options.t()} | {:skip, String.t()} | {:error, term()}
  def codex_options(attrs \\ %{}, opts \\ [])
      when (is_map(attrs) or is_list(attrs)) and is_list(opts) do
    attrs = Map.new(attrs)

    with {:ok, attrs} <-
           maybe_put_local_codex_path(attrs, Keyword.get(opts, :missing_cli, :raise)),
         {:ok, %Options{} = options} <- Options.new(maybe_put_execution_surface(attrs)) do
      {:ok, options}
    end
  end

  @spec auth_available?() :: boolean()
  def auth_available? do
    ollama_mode?() or ssh_enabled?() or not is_nil(Codex.Auth.api_key()) or
      not is_nil(Codex.Auth.chatgpt_access_token())
  end

  @spec ensure_auth_available(String.t()) :: :ok | {:skip, String.t()}
  def ensure_auth_available(message \\ default_auth_message()) do
    if auth_available?(), do: :ok, else: {:skip, message}
  end

  @spec default_auth_message() :: String.t()
  def default_auth_message do
    if ollama_mode?() do
      "configure local Codex OSS + Ollama and ensure the selected local model is installed before running this example"
    else
      "authenticate with `codex login` or set CODEX_API_KEY before running this example"
    end
  end

  @spec ensure_app_server_supported(Options.t()) :: :ok | {:skip, String.t()}
  def ensure_app_server_supported(%Options{} = codex_opts) do
    case Codex.CLI.run(["app-server", "--help"], codex_opts: codex_opts, timeout_ms: 30_000) do
      {:ok, _result} ->
        :ok

      {:error, _reason} ->
        {:skip, "your `codex` CLI does not support `codex app-server`; upgrade it and retry"}
    end
  end

  @spec decode_json_result(Result.t()) :: {:ok, term()} | {:error, term()}
  def decode_json_result(%Result{} = result) do
    case Result.json(result) do
      {:ok, decoded} ->
        {:ok, decoded}

      {:error, _reason} ->
        decode_json_message(result.final_response)
    end
  end

  defp decode_json_message(%Items.AgentMessage{text: text}) when is_binary(text) do
    text
    |> json_candidates()
    |> Enum.find_value({:error, :invalid_json}, fn candidate ->
      case Jason.decode(candidate) do
        {:ok, decoded} -> {:ok, decoded}
        {:error, _reason} -> nil
      end
    end)
  end

  defp decode_json_message(_other), do: {:error, :invalid_json}

  defp json_candidates(text) when is_binary(text) do
    trimmed = String.trim(text)

    [
      trimmed,
      fenced_json(trimmed),
      bracket_slice(trimmed, "{", "}"),
      bracket_slice(trimmed, "[", "]")
    ]
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.uniq()
  end

  defp fenced_json(text) when is_binary(text) do
    with {start, marker_size} <- find_marker(text, "```"),
         after_open <-
           binary_part(text, start + marker_size, byte_size(text) - start - marker_size),
         {:ok, body_start} <- skip_fence_label(after_open),
         body_source <- binary_part(after_open, body_start, byte_size(after_open) - body_start),
         {finish, _} <- find_marker(body_source, "```") do
      body_source
      |> binary_part(0, finish)
      |> String.trim()
    else
      _ -> nil
    end
  end

  defp find_marker(text, marker) do
    case :binary.match(text, marker) do
      :nomatch -> nil
      match -> match
    end
  end

  defp skip_fence_label(text) do
    cond do
      starts_with_ascii_whitespace?(text) ->
        {:ok, leading_ascii_whitespace_size(text)}

      String.starts_with?(text, "json") ->
        rest = binary_part(text, 4, byte_size(text) - 4)

        if rest == "" or starts_with_ascii_whitespace?(rest) do
          {:ok, 4 + leading_ascii_whitespace_size(rest)}
        else
          :error
        end

      true ->
        {:ok, 0}
    end
  end

  defp starts_with_ascii_whitespace?(<<byte, _rest::binary>>),
    do: byte in [?\s, ?\t, ?\n, ?\r, ?\v, ?\f]

  defp starts_with_ascii_whitespace?(<<>>), do: false

  defp leading_ascii_whitespace_size(value), do: do_leading_ascii_whitespace_size(value, 0)

  defp do_leading_ascii_whitespace_size(<<byte, rest::binary>>, count)
       when byte in [?\s, ?\t, ?\n, ?\r, ?\v, ?\f],
       do: do_leading_ascii_whitespace_size(rest, count + 1)

  defp do_leading_ascii_whitespace_size(_value, count), do: count

  defp bracket_slice(text, left, right)
       when is_binary(text) and is_binary(left) and is_binary(right) do
    case {:binary.match(text, left), :binary.matches(text, right)} do
      {:nomatch, _} ->
        nil

      {_, []} ->
        nil

      {{start_idx, _left_len}, matches} ->
        {end_idx, _right_len} = List.last(matches)

        if start_idx <= end_idx do
          text
          |> binary_part(start_idx, end_idx - start_idx + byte_size(right))
          |> String.trim()
        else
          nil
        end
    end
  end

  defp build_context(parsed, argv) do
    example_cwd = Keyword.get(parsed, :cwd)
    example_danger_full_access = Keyword.get(parsed, :danger_full_access, false)
    ssh_host = Keyword.get(parsed, :ssh_host)
    ssh_user = Keyword.get(parsed, :ssh_user)
    ssh_port = Keyword.get(parsed, :ssh_port)
    ssh_identity_file = Keyword.get(parsed, :ssh_identity_file)

    case normalize_example_cwd(example_cwd) do
      {:ok, example_cwd} ->
        do_build_context(
          argv,
          example_cwd,
          example_danger_full_access,
          ssh_host,
          ssh_user,
          ssh_port,
          ssh_identity_file
        )

      {:error, _reason} = error ->
        error
    end
  end

  defp do_build_context(
         argv,
         example_cwd,
         example_danger_full_access,
         nil,
         ssh_user,
         ssh_port,
         ssh_identity_file
       ) do
    with :ok <- validate_ssh_flag_dependencies(nil, ssh_user, ssh_port, ssh_identity_file) do
      {:ok,
       %SSHContext{
         argv: argv,
         example_cwd: example_cwd,
         example_danger_full_access: example_danger_full_access
       }}
    end
  end

  defp do_build_context(
         argv,
         example_cwd,
         example_danger_full_access,
         ssh_host,
         ssh_user,
         ssh_port,
         ssh_identity_file
       ) do
    with :ok <- validate_ssh_flag_dependencies(ssh_host, ssh_user, ssh_port, ssh_identity_file) do
      build_ssh_context(
        argv,
        example_cwd,
        example_danger_full_access,
        ssh_host,
        ssh_user,
        ssh_port,
        ssh_identity_file
      )
    end
  end

  defp validate_ssh_flag_dependencies(ssh_host, ssh_user, ssh_port, ssh_identity_file) do
    if is_nil(ssh_host) and Enum.any?([ssh_user, ssh_port, ssh_identity_file], &present?/1) do
      {:error, "SSH example flags require --ssh-host when any other --ssh-* flag is set."}
    else
      :ok
    end
  end

  defp build_ssh_context(
         argv,
         example_cwd,
         example_danger_full_access,
         ssh_host,
         ssh_user,
         ssh_port,
         ssh_identity_file
       ) do
    with {:ok, {destination, parsed_user}} <- split_host(ssh_host),
         {:ok, effective_user} <- coalesce_user(parsed_user, ssh_user),
         {:ok, identity_file} <- normalize_identity_file(ssh_identity_file),
         {:ok, %ExecutionSurface{} = execution_surface} <-
           ExecutionSurface.new(
             surface_kind: :ssh_exec,
             transport_options:
               []
               |> Keyword.put(:destination, destination)
               |> maybe_put_kw(:ssh_user, effective_user)
               |> maybe_put_kw(:port, ssh_port)
               |> maybe_put_kw(:identity_file, identity_file)
               |> Keyword.put(:ssh_options, @example_ssh_options)
           ) do
      {:ok,
       %SSHContext{
         argv: argv,
         execution_surface: execution_surface,
         example_cwd: example_cwd,
         example_danger_full_access: example_danger_full_access,
         ssh_host: destination,
         ssh_user: effective_user,
         ssh_port: ssh_port,
         ssh_identity_file: identity_file
       }}
    else
      {:error, reason} when is_binary(reason) -> {:error, reason}
      {:error, reason} -> {:error, "invalid SSH example flags: #{inspect(reason)}"}
    end
  end

  defp maybe_put_local_codex_path(attrs, mode) do
    cond do
      nonlocal_path_execution_surface?() ->
        {:ok, maybe_put_execution_surface(attrs)}

      local_codex_override?(attrs) ->
        {:ok, attrs}

      true ->
        resolve_local_codex_path(attrs, mode)
    end
  end

  defp local_codex_override?(attrs) do
    present?(Map.get(attrs, :codex_path_override)) or
      present?(Map.get(attrs, "codex_path_override"))
  end

  defp resolve_local_codex_path(attrs, mode) do
    case System.get_env("CODEX_PATH") || System.find_executable("codex") do
      path when is_binary(path) and path != "" ->
        {:ok, Map.put(attrs, :codex_path_override, path)}

      _ ->
        reason = "install the `codex` CLI or set CODEX_PATH before running this example"

        case mode do
          :skip -> {:skip, reason}
          _ -> {:error, reason}
        end
    end
  end

  defp maybe_put_execution_surface(attrs) when is_map(attrs) do
    case execution_surface() do
      %ExecutionSurface{} = surface -> Map.put(attrs, :execution_surface, surface)
      nil -> attrs
    end
  end

  defp maybe_put_example_working_directory(attrs) when is_map(attrs) do
    if present?(present_value?(attrs, :working_directory)) || present?(present_value?(attrs, :cd)) do
      attrs
    else
      case context().example_cwd do
        cwd when is_binary(cwd) and cwd != "" -> Map.put(attrs, :working_directory, cwd)
        _ -> attrs
      end
    end
  end

  defp maybe_put_skip_git_repo_check(attrs) when is_map(attrs) do
    if ssh_enabled?() and present_value?(attrs, :skip_git_repo_check) != true do
      Map.put(attrs, :skip_git_repo_check, true)
    else
      attrs
    end
  end

  defp maybe_put_thread_danger_full_access(attrs) when is_map(attrs) do
    if danger_full_access?() and not present?(present_value?(attrs, :sandbox)) and
         present_value?(attrs, :dangerously_bypass_approvals_and_sandbox) != true do
      Map.put(attrs, :sandbox, :danger_full_access)
    else
      attrs
    end
  end

  defp present_value?(attrs, key) when is_map(attrs) and is_atom(key) do
    case {Map.get(attrs, key), Map.get(attrs, Atom.to_string(key))} do
      {nil, nil} -> nil
      {value, nil} -> value
      {nil, value} -> value
      {value, _other} -> value
    end
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(nil), do: false
  defp present?(_value), do: true

  defp normalize_example_cwd(nil), do: {:ok, nil}

  defp normalize_example_cwd(path) when is_binary(path) do
    case String.trim(path) do
      "" -> {:error, "--cwd must be a non-empty path"}
      trimmed -> {:ok, trimmed}
    end
  end

  defp split_host(ssh_host) when is_binary(ssh_host) do
    case String.trim(ssh_host) do
      "" ->
        {:error, "--ssh-host must be a non-empty host name"}

      trimmed ->
        case String.split(trimmed, "@", parts: 2) do
          [destination] ->
            {:ok, {destination, nil}}

          [inline_user, destination] when inline_user != "" and destination != "" ->
            {:ok, {destination, inline_user}}

          _other ->
            {:error, "--ssh-host must be either <host> or <user>@<host>"}
        end
    end
  end

  defp coalesce_user(nil, nil), do: {:ok, nil}
  defp coalesce_user(inline_user, nil), do: {:ok, inline_user}

  defp coalesce_user(nil, ssh_user) when is_binary(ssh_user) do
    case String.trim(ssh_user) do
      "" -> {:error, "--ssh-user must be a non-empty string"}
      trimmed -> {:ok, trimmed}
    end
  end

  defp coalesce_user(inline_user, ssh_user) when is_binary(ssh_user) do
    normalized = String.trim(ssh_user)

    cond do
      normalized == "" ->
        {:error, "--ssh-user must be a non-empty string"}

      normalized == inline_user ->
        {:ok, inline_user}

      true ->
        {:error,
         "--ssh-host already contains #{inspect(inline_user)}; omit --ssh-user or make it match"}
    end
  end

  defp normalize_identity_file(nil), do: {:ok, nil}

  defp normalize_identity_file(path) when is_binary(path) do
    case String.trim(path) do
      "" -> {:error, "--ssh-identity-file must be a non-empty path"}
      trimmed -> {:ok, Path.expand(trimmed)}
    end
  end

  defp invalid_options_message(invalid) when is_list(invalid) do
    rendered =
      Enum.map_join(invalid, ", ", fn
        {name, nil} -> "--#{name}"
        {name, value} -> "--#{name}=#{value}"
      end)

    "invalid example flags: #{rendered}. Supported flags: --cwd, --danger-full-access, --ssh-host, --ssh-user, --ssh-port, --ssh-identity-file"
  end

  defp maybe_put_kw(opts, _key, nil), do: opts
  defp maybe_put_kw(opts, key, value), do: Keyword.put(opts, key, value)

  defp maybe_put_command_execution_surface(opts) when is_list(opts) do
    case execution_surface() do
      %ExecutionSurface{} = surface -> Keyword.put(opts, :execution_surface, surface)
      nil -> opts
    end
  end

  defp maybe_put_command_working_directory(opts) when is_list(opts) do
    case example_working_directory() do
      cwd when is_binary(cwd) and cwd != "" -> Keyword.put_new(opts, :cwd, cwd)
      _ -> opts
    end
  end

  defp maybe_put_command_danger_full_access(opts) when is_list(opts) do
    if danger_full_access?() and not Keyword.has_key?(opts, :sandbox) and
         not Keyword.has_key?(opts, :dangerously_bypass_approvals_and_sandbox) do
      Keyword.put(opts, :sandbox, :danger_full_access)
    else
      opts
    end
  end
end
