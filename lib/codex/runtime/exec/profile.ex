defmodule Codex.Runtime.Exec.Profile do
  @moduledoc false

  @behaviour CliSubprocessCore.ProviderProfile

  alias CliSubprocessCore.ProviderProfiles.Codex, as: CoreCodex
  alias CliSubprocessCore.ProviderProfiles.Shared
  alias Codex.Options

  @impl true
  def id, do: CoreCodex.id()

  @impl true
  def capabilities, do: CoreCodex.capabilities()

  @impl true
  def build_invocation(opts) when is_list(opts) do
    with {:ok, command_spec} <- Shared.resolve_command_spec(opts, :codex, "codex", [:binary_path]) do
      {:ok,
       Shared.command(command_spec, render_args(opts),
         cwd: Keyword.get(opts, :cwd),
         env: normalize_env(Keyword.get(opts, :env, %{}))
       )}
    end
  end

  @doc false
  @spec render_args(keyword()) :: [String.t()]
  def render_args(opts) when is_list(opts) do
    ["exec", "--json"]
    |> Shared.maybe_add_pair("--profile", Keyword.get(opts, :cli_profile))
    |> Shared.maybe_add_flag("--full-auto", Keyword.get(opts, :full_auto))
    |> Shared.maybe_add_flag(
      "--dangerously-bypass-approvals-and-sandbox",
      Keyword.get(opts, :dangerously_bypass_approvals_and_sandbox)
    )
    |> Shared.maybe_add_pair("--model", model_value(opts))
    |> Shared.maybe_add_pair("--color", Keyword.get(opts, :color))
    |> Shared.maybe_add_pair("--output-last-message", Keyword.get(opts, :output_last_message))
    |> Shared.maybe_add_pair("--sandbox", Keyword.get(opts, :sandbox))
    |> Shared.maybe_add_pair("--cd", Keyword.get(opts, :working_directory))
    |> Shared.maybe_add_repeat("--add-dir", Keyword.get(opts, :additional_directories, []))
    |> Shared.maybe_add_flag("--skip-git-repo-check", Keyword.get(opts, :skip_git_repo_check))
    |> Shared.maybe_add_repeat("--config", config_values(opts))
    |> Kernel.++(normalize_string_list(Keyword.get(opts, :subcommand_args, [])))
    |> Shared.maybe_add_pair("--continuation-token", Keyword.get(opts, :continuation_token))
    |> Shared.maybe_add_pair("--cancellation-token", Keyword.get(opts, :cancellation_token))
    |> Shared.maybe_add_repeat("--image", Keyword.get(opts, :images, []))
    |> maybe_add_output_schema(Keyword.get(opts, :output_schema))
  end

  @impl true
  def init_parser_state(opts), do: CoreCodex.init_parser_state(opts)

  @impl true
  def decode_stdout(line, state), do: CoreCodex.decode_stdout(line, state)

  @impl true
  def decode_stderr(chunk, state), do: CoreCodex.decode_stderr(chunk, state)

  @impl true
  def handle_exit(reason, state), do: CoreCodex.handle_exit(reason, state)

  @impl true
  def transport_options(opts), do: CoreCodex.transport_options(opts)

  defp maybe_add_output_schema(args, nil), do: args

  defp maybe_add_output_schema(args, schema) when is_binary(schema),
    do: args ++ ["--output-schema", schema]

  defp maybe_add_output_schema(args, schema) when is_map(schema) or is_list(schema) do
    Shared.maybe_add_json_pair(args, "--output-schema", schema)
  end

  defp maybe_add_output_schema(args, _other), do: args

  defp normalize_string_list(values) when is_list(values) do
    Enum.flat_map(values, fn
      value when is_binary(value) and value != "" -> [value]
      _value -> []
    end)
  end

  defp normalize_string_list(_values), do: []

  defp model_value(opts) do
    if local_provider_value(opts) do
      nil
    else
      opts
      |> keyword_to_options()
      |> case do
        %Options{} = options -> Options.execution_model(options)
        nil -> Keyword.get(opts, :model) || model_payload_value(opts, :resolved_model)
      end
    end
  end

  defp local_provider_value(opts) do
    Keyword.get(opts, :local_provider) ||
      Map.get(model_payload_backend_metadata(opts), "oss_provider")
  end

  defp config_values(opts) do
    payload_values =
      model_payload_backend_metadata(opts)
      |> Map.get("config_values", [])
      |> List.wrap()
      |> Enum.filter(&(is_binary(&1) and &1 != ""))

    (local_model_provider_config_values(opts) ++
       Keyword.get(opts, :config_values, []) ++
       payload_values)
    |> Enum.uniq()
  end

  defp local_model_provider_config_values(opts) do
    model = Keyword.get(opts, :model) || model_payload_value(opts, :resolved_model)

    case {local_provider_value(opts), model} do
      {provider, model}
      when is_binary(provider) and provider != "" and is_binary(model) and model != "" ->
        [~s(model_provider="#{provider}"), ~s(model="#{model}")]

      _other ->
        []
    end
  end

  defp model_payload_backend_metadata(opts) do
    opts
    |> Keyword.get(:model_payload, %{})
    |> case do
      payload when is_map(payload) ->
        Map.get(payload, :backend_metadata, Map.get(payload, "backend_metadata", %{}))

      _ ->
        %{}
    end
    |> case do
      metadata when is_map(metadata) -> metadata
      _ -> %{}
    end
  end

  defp model_payload_value(opts, key) when is_atom(key) do
    opts
    |> Keyword.get(:model_payload, %{})
    |> case do
      payload when is_map(payload) -> Map.get(payload, key, Map.get(payload, Atom.to_string(key)))
      _ -> nil
    end
  end

  defp normalize_env(nil), do: %{}

  defp normalize_env(env) when is_map(env) do
    Map.new(env, fn {key, value} -> {to_string(key), to_string(value)} end)
  end

  defp normalize_env(env) when is_list(env) do
    env
    |> Enum.filter(&match?({_, _}, &1))
    |> Map.new(fn {key, value} -> {to_string(key), to_string(value)} end)
  end

  defp normalize_env(_env), do: %{}

  defp keyword_to_options(opts) when is_list(opts) do
    case Keyword.get(opts, :codex_opts) do
      %Options{} = options ->
        options

      _ ->
        model = Keyword.get(opts, :model)
        model_payload = Keyword.get(opts, :model_payload)

        if (is_binary(model) and model != "") or is_map(model_payload) do
          %Options{model: model, model_payload: model_payload}
        end
    end
  end
end
