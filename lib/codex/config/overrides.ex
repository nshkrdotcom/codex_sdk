defmodule Codex.Config.Overrides do
  @moduledoc false

  alias Codex.Options
  alias Codex.Thread.Options, as: ThreadOptions

  @spec derived_overrides(Options.t(), ThreadOptions.t() | nil) :: [{String.t(), term()}]
  def derived_overrides(%Options{} = codex_opts, thread_opts) do
    []
    |> maybe_put_override("model_provider", thread_value(thread_opts, :model_provider))
    |> maybe_put_override("base_instructions", thread_value(thread_opts, :base_instructions))
    |> maybe_put_override(
      "developer_instructions",
      thread_value(thread_opts, :developer_instructions)
    )
    |> maybe_put_override(
      "model_reasoning_summary",
      pick(
        thread_value(thread_opts, :model_reasoning_summary),
        codex_opts.model_reasoning_summary
      )
    )
    |> maybe_put_override(
      "model_personality",
      pick(thread_value(thread_opts, :personality), codex_opts.model_personality)
      |> encode_personality()
    )
    |> maybe_put_override(
      "model_verbosity",
      pick(thread_value(thread_opts, :model_verbosity), codex_opts.model_verbosity)
    )
    |> maybe_put_override(
      "model_context_window",
      pick(thread_value(thread_opts, :model_context_window), codex_opts.model_context_window)
    )
    |> maybe_put_override(
      "model_auto_compact_token_limit",
      codex_opts.model_auto_compact_token_limit
    )
    |> maybe_put_override("review_model", codex_opts.review_model)
    |> maybe_put_override(
      "model_supports_reasoning_summaries",
      pick(
        thread_value(thread_opts, :model_supports_reasoning_summaries),
        codex_opts.model_supports_reasoning_summaries
      )
    )
    |> maybe_put_override("compact_prompt", thread_value(thread_opts, :compact_prompt))
    |> maybe_put_override("hide_agent_reasoning", codex_opts.hide_agent_reasoning)
    |> maybe_put_override(
      "show_raw_agent_reasoning",
      thread_value(thread_opts, :show_raw_agent_reasoning)
    )
    |> maybe_put_override("tool_output_token_limit", codex_opts.tool_output_token_limit)
    |> maybe_put_override("agents.max_threads", codex_opts.agent_max_threads)
    |> maybe_put_override(
      "history.persistence",
      pick(thread_value(thread_opts, :history_persistence), codex_opts.history_persistence)
    )
    |> maybe_put_override(
      "history.max_bytes",
      pick(thread_value(thread_opts, :history_max_bytes), codex_opts.history_max_bytes)
    )
    |> maybe_put_override(
      "features.apply_patch_freeform",
      thread_value(thread_opts, :apply_patch_freeform_enabled)
    )
    |> maybe_put_override(
      "features.view_image_tool",
      thread_value(thread_opts, :view_image_tool_enabled)
    )
    |> maybe_put_override(
      "features.unified_exec",
      thread_value(thread_opts, :unified_exec_enabled)
    )
    |> maybe_put_override("features.skills", thread_value(thread_opts, :skills_enabled))
    |> maybe_put_override("web_search", web_search_mode_override(thread_opts))
    |> maybe_put_override_true(
      "features.web_search_request",
      web_search_request_override(thread_opts)
    )
    |> add_shell_environment_policy_overrides(
      thread_value(thread_opts, :shell_environment_policy)
    )
    |> add_sandbox_policy_overrides(thread_value(thread_opts, :sandbox_policy))
    |> add_provider_tuning_overrides(thread_opts)
  end

  @spec merge_config(map() | nil, Options.t(), ThreadOptions.t()) :: map() | nil
  def merge_config(config, %Options{} = codex_opts, %ThreadOptions{} = thread_opts) do
    base = normalize_config_map(config)
    overrides = derived_overrides(codex_opts, thread_opts)

    merged =
      Enum.reduce(overrides, base, fn {key, value}, acc ->
        if has_config_key?(acc, key) do
          acc
        else
          Map.put(acc, key, value)
        end
      end)

    case merged do
      %{} = map when map_size(map) == 0 -> nil
      %{} = map -> map
      _ -> nil
    end
  end

  @spec cli_args([ThreadOptions.config_override()]) :: [String.t()]
  def cli_args(overrides) do
    overrides
    |> List.wrap()
    |> Enum.flat_map(&config_override_arg/1)
  end

  defp config_override_arg({key, value}) do
    ["--config", "#{key}=#{encode_override_value(value)}"]
  end

  defp config_override_arg(value) when is_binary(value) and value != "" do
    ["--config", value]
  end

  defp config_override_arg(_), do: []

  defp encode_override_value(value) when is_binary(value), do: inspect(value)
  defp encode_override_value(value) when is_boolean(value), do: to_string(value)

  defp encode_override_value(value) when is_integer(value) or is_float(value),
    do: to_string(value)

  defp encode_override_value(value) when is_list(value) do
    "[" <> Enum.map_join(value, ",", &encode_override_value/1) <> "]"
  end

  defp encode_override_value(%{} = value) do
    "{" <>
      Enum.map_join(value, ",", fn {key, entry} ->
        "#{encode_override_key(key)}=#{encode_override_value(entry)}"
      end) <> "}"
  end

  defp encode_override_value(value), do: inspect(value)

  defp encode_override_key(key), do: inspect(to_string(key))

  defp maybe_put_override(overrides, _key, nil), do: overrides
  defp maybe_put_override(overrides, _key, ""), do: overrides
  defp maybe_put_override(overrides, key, value), do: overrides ++ [{key, value}]

  defp maybe_put_override_true(overrides, key, true), do: overrides ++ [{key, true}]
  defp maybe_put_override_true(overrides, _key, _value), do: overrides

  defp pick(nil, fallback), do: fallback
  defp pick(value, _fallback), do: value

  defp encode_personality(nil), do: nil
  defp encode_personality(value) when is_atom(value), do: Atom.to_string(value)
  defp encode_personality(value) when is_binary(value), do: value
  defp encode_personality(_), do: nil

  defp web_search_mode_override(%ThreadOptions{} = opts) do
    case thread_value(opts, :web_search_mode) do
      :cached -> "cached"
      :live -> "live"
      "cached" -> "cached"
      "live" -> "live"
      _ -> nil
    end
  end

  defp web_search_mode_override(_), do: nil

  defp web_search_request_override(%ThreadOptions{} = opts) do
    case thread_value(opts, :web_search_mode) do
      :live -> true
      "live" -> true
      :cached -> nil
      "cached" -> nil
      :disabled -> nil
      "disabled" -> nil
      nil -> thread_value(opts, :web_search_enabled)
      _ -> thread_value(opts, :web_search_enabled)
    end
  end

  defp web_search_request_override(_), do: nil

  defp normalize_config_map(nil), do: %{}
  defp normalize_config_map(%{} = config), do: config
  defp normalize_config_map(_), do: %{}

  defp has_config_key?(%{} = config, key) when is_binary(key) do
    Map.has_key?(config, key) ||
      has_existing_atom_key?(config, key) ||
      has_nested_key?(config, String.split(key, "."))
  end

  defp has_config_key?(_config, _key), do: false

  defp has_nested_key?(_config, []), do: false

  defp has_nested_key?(config, [segment]) do
    case fetch_key(config, segment) do
      nil -> false
      _ -> true
    end
  end

  defp has_nested_key?(config, [segment | rest]) do
    case fetch_key(config, segment) do
      %{} = nested -> has_nested_key?(nested, rest)
      _ -> false
    end
  end

  defp fetch_key(map, segment) when is_map(map) and is_binary(segment) do
    if Map.has_key?(map, segment) do
      Map.get(map, segment)
    else
      case existing_atom(segment) do
        {:ok, atom} -> Map.get(map, atom)
        :error -> nil
      end
    end
  end

  defp has_existing_atom_key?(map, key) do
    case existing_atom(key) do
      {:ok, atom} -> Map.has_key?(map, atom)
      :error -> false
    end
  end

  defp existing_atom(value) when is_binary(value) do
    {:ok, String.to_existing_atom(value)}
  rescue
    ArgumentError -> :error
  end

  defp add_shell_environment_policy_overrides(overrides, nil), do: overrides

  defp add_shell_environment_policy_overrides(overrides, policy) do
    overrides
    |> maybe_put_override(
      "shell_environment_policy.inherit",
      fetch_any(policy, ["inherit", :inherit])
    )
    |> maybe_put_override(
      "shell_environment_policy.ignore_default_excludes",
      fetch_any(policy, ["ignore_default_excludes", :ignore_default_excludes])
    )
    |> maybe_put_override(
      "shell_environment_policy.exclude",
      fetch_any(policy, ["exclude", :exclude])
    )
    |> maybe_put_override(
      "shell_environment_policy.include_only",
      fetch_any(policy, ["include_only", :include_only])
    )
    |> maybe_put_override("shell_environment_policy.set", fetch_any(policy, ["set", :set]))
  end

  defp add_sandbox_policy_overrides(overrides, nil), do: overrides

  defp add_sandbox_policy_overrides(overrides, policy) do
    policy = normalize_sandbox_policy(policy)
    type = normalize_sandbox_policy_type(fetch_any(policy, ["type", :type]))

    network_access =
      normalize_network_access(
        fetch_any(policy, ["network_access", :network_access, "networkAccess", :networkAccess])
      )

    overrides =
      overrides
      |> maybe_put_override(
        "sandbox_workspace_write.writable_roots",
        fetch_any(policy, ["writable_roots", :writable_roots, "writableRoots", :writableRoots])
      )
      |> maybe_put_override(
        "sandbox_workspace_write.exclude_tmpdir_env_var",
        fetch_any(policy, [
          "exclude_tmpdir_env_var",
          :exclude_tmpdir_env_var,
          "excludeTmpdirEnvVar",
          :excludeTmpdirEnvVar
        ])
      )
      |> maybe_put_override(
        "sandbox_workspace_write.exclude_slash_tmp",
        fetch_any(policy, [
          "exclude_slash_tmp",
          :exclude_slash_tmp,
          "excludeSlashTmp",
          :excludeSlashTmp
        ])
      )

    case {type, network_access} do
      {"external-sandbox", value} when is_boolean(value) ->
        maybe_put_override(overrides, "sandbox_external.network_access", value)

      {_type, value} when is_boolean(value) ->
        maybe_put_override(overrides, "sandbox_workspace_write.network_access", value)

      _ ->
        overrides
    end
  end

  defp normalize_sandbox_policy(%{} = policy), do: policy
  defp normalize_sandbox_policy(list) when is_list(list), do: Map.new(list)
  defp normalize_sandbox_policy(policy) when is_atom(policy), do: %{type: policy}
  defp normalize_sandbox_policy(policy) when is_binary(policy), do: %{type: policy}
  defp normalize_sandbox_policy(_), do: %{}

  defp normalize_sandbox_policy_type(nil), do: nil
  defp normalize_sandbox_policy_type(:external_sandbox), do: "external-sandbox"
  defp normalize_sandbox_policy_type("external_sandbox"), do: "external-sandbox"
  defp normalize_sandbox_policy_type("externalSandbox"), do: "external-sandbox"
  defp normalize_sandbox_policy_type("external-sandbox"), do: "external-sandbox"
  defp normalize_sandbox_policy_type(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_sandbox_policy_type(value) when is_binary(value), do: value
  defp normalize_sandbox_policy_type(_), do: nil

  defp normalize_network_access(nil), do: nil
  defp normalize_network_access(value) when is_boolean(value), do: value
  defp normalize_network_access(:enabled), do: true
  defp normalize_network_access(:restricted), do: false
  defp normalize_network_access("enabled"), do: true
  defp normalize_network_access("restricted"), do: false
  defp normalize_network_access(_), do: nil

  defp add_provider_tuning_overrides(overrides, %ThreadOptions{} = thread_opts) do
    provider_id = provider_id_for_tuning(thread_opts)

    overrides
    |> maybe_put_override(
      "model_providers.#{provider_id}.request_max_retries",
      thread_opts.request_max_retries
    )
    |> maybe_put_override(
      "model_providers.#{provider_id}.stream_max_retries",
      thread_opts.stream_max_retries
    )
    |> maybe_put_override(
      "model_providers.#{provider_id}.stream_idle_timeout_ms",
      thread_opts.stream_idle_timeout_ms
    )
  end

  defp add_provider_tuning_overrides(overrides, _), do: overrides

  defp provider_id_for_tuning(%ThreadOptions{model_provider: provider})
       when is_binary(provider) and provider != "" do
    provider
  end

  defp provider_id_for_tuning(%ThreadOptions{oss: true, local_provider: provider})
       when is_binary(provider) and provider != "" do
    provider
  end

  defp provider_id_for_tuning(_), do: "openai"

  defp thread_value(nil, _field), do: nil
  defp thread_value(%ThreadOptions{} = thread_opts, field), do: Map.get(thread_opts, field)

  defp fetch_any(map, keys) when is_map(map) and is_list(keys) do
    Enum.reduce_while(keys, nil, fn key, _acc ->
      case Map.fetch(map, key) do
        {:ok, value} -> {:halt, value}
        :error -> {:cont, nil}
      end
    end)
  end
end
