defmodule Codex.Thread.Options do
  @moduledoc """
  Per-thread configuration options.
  """

  alias Codex.FileSearch

  @enforce_keys []
  defstruct metadata: %{},
            labels: %{},
            auto_run: false,
            transport: :exec,
            approval_policy: nil,
            approval_hook: nil,
            approval_timeout_ms: 30_000,
            sandbox: :default,
            sandbox_policy: nil,
            working_directory: nil,
            additional_directories: [],
            skip_git_repo_check: false,
            network_access_enabled: nil,
            web_search_enabled: false,
            ask_for_approval: nil,
            attachments: [],
            file_search: nil,
            profile: nil,
            oss: false,
            local_provider: nil,
            full_auto: false,
            dangerously_bypass_approvals_and_sandbox: false,
            output_last_message: nil,
            color: nil,
            config_overrides: [],
            model: nil,
            model_provider: nil,
            config: nil,
            base_instructions: nil,
            developer_instructions: nil,
            experimental_raw_events: false

  @type transport :: :exec | {:app_server, pid()}

  @type network_access :: :enabled | :restricted

  @type sandbox ::
          :default
          | :strict
          | :permissive
          | :read_only
          | :workspace_write
          | :danger_full_access
          | :external_sandbox
          | {:external_sandbox, network_access()}
          | String.t()

  @type sandbox_policy_type ::
          :danger_full_access
          | :read_only
          | :workspace_write
          | :external_sandbox
          | String.t()

  @type sandbox_policy :: %{
          optional(:type) => sandbox_policy_type(),
          optional(:writable_roots) => [String.t()],
          optional(:network_access) => boolean() | :enabled | :restricted | String.t(),
          optional(:exclude_tmpdir_env_var) => boolean(),
          optional(:exclude_slash_tmp) => boolean()
        }

  @type color :: :always | :never | :auto | String.t()

  @type config_override ::
          String.t()
          | {String.t() | atom(), term()}

  @type t :: %__MODULE__{
          metadata: map(),
          labels: map(),
          auto_run: boolean(),
          transport: transport(),
          approval_policy: module() | nil,
          approval_hook: module() | nil,
          approval_timeout_ms: pos_integer(),
          sandbox: sandbox(),
          sandbox_policy: sandbox_policy() | sandbox_policy_type() | nil,
          working_directory: String.t() | nil,
          additional_directories: [String.t()],
          skip_git_repo_check: boolean(),
          network_access_enabled: boolean() | nil,
          web_search_enabled: boolean(),
          ask_for_approval: :untrusted | :on_failure | :on_request | :never | String.t() | nil,
          attachments: [map()] | [],
          file_search: FileSearch.t() | nil,
          profile: String.t() | nil,
          oss: boolean(),
          local_provider: String.t() | nil,
          full_auto: boolean(),
          dangerously_bypass_approvals_and_sandbox: boolean(),
          output_last_message: String.t() | nil,
          color: color() | nil,
          config_overrides: [config_override()],
          model: String.t() | nil,
          model_provider: String.t() | nil,
          config: map() | nil,
          base_instructions: String.t() | nil,
          developer_instructions: String.t() | nil,
          experimental_raw_events: boolean()
        }

  @doc """
  Builds a thread options struct from various inputs.
  """
  @spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, term()}
  def new(%__MODULE__{} = opts), do: {:ok, opts}
  def new(attrs) when is_list(attrs), do: attrs |> Map.new() |> new()

  def new(attrs) when is_map(attrs) do
    metadata = Map.get(attrs, :metadata, Map.get(attrs, "metadata", %{}))
    labels = Map.get(attrs, :labels, Map.get(attrs, "labels", %{}))
    auto_run = Map.get(attrs, :auto_run, Map.get(attrs, "auto_run", false))
    transport = Map.get(attrs, :transport, Map.get(attrs, "transport"))
    approval_policy = Map.get(attrs, :approval_policy, Map.get(attrs, "approval_policy"))
    approval_hook = Map.get(attrs, :approval_hook, Map.get(attrs, "approval_hook"))

    approval_timeout_ms =
      Map.get(attrs, :approval_timeout_ms, Map.get(attrs, "approval_timeout_ms", 30_000))

    sandbox = Map.get(attrs, :sandbox, Map.get(attrs, "sandbox", :default))
    sandbox_policy = Map.get(attrs, :sandbox_policy, Map.get(attrs, "sandbox_policy"))

    working_directory =
      Map.get(attrs, :working_directory, Map.get(attrs, "working_directory", Map.get(attrs, :cd)))

    additional_directories =
      Map.get(attrs, :additional_directories, Map.get(attrs, "additional_directories", []))

    skip_git_repo_check =
      Map.get(attrs, :skip_git_repo_check, Map.get(attrs, "skip_git_repo_check", false))

    network_access_enabled =
      Map.get(attrs, :network_access_enabled, Map.get(attrs, "network_access_enabled"))

    web_search_enabled =
      Map.get(attrs, :web_search_enabled, Map.get(attrs, "web_search_enabled", false))

    ask_for_approval = Map.get(attrs, :ask_for_approval, Map.get(attrs, "ask_for_approval"))
    attachments = Map.get(attrs, :attachments, Map.get(attrs, "attachments", []))
    file_search = Map.get(attrs, :file_search, Map.get(attrs, "file_search"))

    profile =
      Map.get(attrs, :profile, Map.get(attrs, "profile", Map.get(attrs, :config_profile)))
      |> case do
        nil -> Map.get(attrs, "config_profile")
        value -> value
      end

    oss = Map.get(attrs, :oss, Map.get(attrs, "oss", false))

    local_provider =
      Map.get(
        attrs,
        :local_provider,
        Map.get(
          attrs,
          "local_provider",
          Map.get(attrs, :oss_provider, Map.get(attrs, "oss_provider"))
        )
      )

    full_auto = Map.get(attrs, :full_auto, Map.get(attrs, "full_auto", false))

    dangerously_bypass_approvals_and_sandbox =
      Map.get(
        attrs,
        :dangerously_bypass_approvals_and_sandbox,
        Map.get(attrs, "dangerously_bypass_approvals_and_sandbox", false)
      )

    output_last_message =
      Map.get(attrs, :output_last_message, Map.get(attrs, "output_last_message"))

    color = Map.get(attrs, :color, Map.get(attrs, "color"))

    config_overrides =
      Map.get(
        attrs,
        :config_overrides,
        Map.get(attrs, "config_overrides", Map.get(attrs, :config_override, []))
      )

    model = Map.get(attrs, :model, Map.get(attrs, "model"))

    model_provider =
      Map.get(attrs, :model_provider, Map.get(attrs, "model_provider", Map.get(attrs, :provider)))

    config = Map.get(attrs, :config, Map.get(attrs, "config"))

    base_instructions =
      Map.get(attrs, :base_instructions, Map.get(attrs, "base_instructions"))

    developer_instructions =
      Map.get(attrs, :developer_instructions, Map.get(attrs, "developer_instructions"))

    experimental_raw_events =
      Map.get(attrs, :experimental_raw_events, Map.get(attrs, "experimental_raw_events", false))

    with {:ok, metadata} <- ensure_map(metadata, :metadata),
         {:ok, labels} <- ensure_map(labels, :labels),
         {:ok, attachments} <- ensure_list(attachments, :attachments),
         {:ok, file_search} <- FileSearch.new(file_search),
         {:ok, transport} <- normalize_transport(transport),
         {:ok, sandbox} <- normalize_sandbox(sandbox),
         {:ok, sandbox_policy} <- normalize_sandbox_policy(sandbox_policy),
         :ok <- validate_boolean(auto_run, :auto_run),
         :ok <- validate_optional_string(working_directory, :working_directory),
         {:ok, additional_directories} <-
           normalize_string_list(additional_directories, :additional_directories),
         :ok <- validate_boolean(skip_git_repo_check, :skip_git_repo_check),
         {:ok, network_access_enabled} <-
           validate_optional_boolean(network_access_enabled, :network_access_enabled),
         :ok <- validate_boolean(web_search_enabled, :web_search_enabled),
         {:ok, ask_for_approval} <- normalize_ask_for_approval(ask_for_approval),
         :ok <- validate_optional_string(profile, :profile),
         :ok <- validate_boolean(oss, :oss),
         :ok <- validate_optional_string(local_provider, :local_provider),
         :ok <- validate_boolean(full_auto, :full_auto),
         :ok <-
           validate_boolean(
             dangerously_bypass_approvals_and_sandbox,
             :dangerously_bypass_approvals_and_sandbox
           ),
         :ok <- validate_optional_string(output_last_message, :output_last_message),
         {:ok, color} <- normalize_color(color),
         {:ok, config_overrides} <- normalize_config_overrides(config_overrides),
         :ok <- validate_auto_flags(full_auto, dangerously_bypass_approvals_and_sandbox),
         :ok <- validate_optional_string(model, :model),
         :ok <- validate_optional_string(model_provider, :model_provider),
         {:ok, config} <- ensure_optional_map(config, :config),
         :ok <- validate_optional_string(base_instructions, :base_instructions),
         :ok <- validate_optional_string(developer_instructions, :developer_instructions),
         :ok <- validate_boolean(experimental_raw_events, :experimental_raw_events),
         :ok <- validate_timeout(approval_timeout_ms) do
      {:ok,
       %__MODULE__{
         metadata: metadata,
         labels: labels,
         auto_run: auto_run,
         transport: transport,
         approval_policy: approval_policy,
         approval_hook: approval_hook,
         approval_timeout_ms: approval_timeout_ms,
         sandbox: sandbox,
         sandbox_policy: sandbox_policy,
         working_directory: working_directory,
         additional_directories: additional_directories,
         skip_git_repo_check: skip_git_repo_check,
         network_access_enabled: network_access_enabled,
         web_search_enabled: web_search_enabled,
         ask_for_approval: ask_for_approval,
         attachments: attachments,
         file_search: file_search,
         profile: profile,
         oss: oss,
         local_provider: local_provider,
         full_auto: full_auto,
         dangerously_bypass_approvals_and_sandbox: dangerously_bypass_approvals_and_sandbox,
         output_last_message: output_last_message,
         color: color,
         config_overrides: config_overrides,
         model: model,
         model_provider: model_provider,
         config: config,
         base_instructions: base_instructions,
         developer_instructions: developer_instructions,
         experimental_raw_events: experimental_raw_events
       }}
    else
      {:error, _} = error -> error
    end
  end

  defp ensure_map(value, _field) when is_map(value), do: {:ok, value}
  defp ensure_map(nil, _field), do: {:ok, %{}}
  defp ensure_map(value, field), do: {:error, {:invalid_map, field, value}}

  defp ensure_list(value, _field) when is_list(value), do: {:ok, value}
  defp ensure_list(nil, _field), do: {:ok, []}
  defp ensure_list(value, field), do: {:error, {:invalid_list, field, value}}

  defp ensure_optional_map(nil, _field), do: {:ok, nil}
  defp ensure_optional_map(value, _field) when is_map(value), do: {:ok, value}
  defp ensure_optional_map(value, field), do: {:error, {:invalid_map, field, value}}

  defp validate_optional_string(nil, _field), do: :ok
  defp validate_optional_string(value, _field) when is_binary(value), do: :ok
  defp validate_optional_string(value, field), do: {:error, {:"invalid_#{field}", value}}

  defp validate_optional_boolean(nil, _field), do: {:ok, nil}
  defp validate_optional_boolean(value, _field) when is_boolean(value), do: {:ok, value}
  defp validate_optional_boolean(value, field), do: {:error, {:"invalid_#{field}", value}}

  defp validate_boolean(value, _field) when is_boolean(value), do: :ok
  defp validate_boolean(value, field), do: {:error, {:"invalid_#{field}", value}}

  defp validate_auto_flags(full_auto, dangerously_bypass)
       when full_auto and dangerously_bypass,
       do: {:error, :conflicting_auto_flags}

  defp validate_auto_flags(_full_auto, _dangerously_bypass), do: :ok

  defp validate_timeout(value) when is_integer(value) and value > 0, do: :ok
  defp validate_timeout(value), do: {:error, {:invalid_timeout, value}}

  defp normalize_string_list(list, _field) when list in [nil, []], do: {:ok, []}

  defp normalize_string_list(list, field) when is_list(list) do
    if Enum.all?(list, &is_binary/1) do
      {:ok, list}
    else
      {:error, {:invalid_list, field, list}}
    end
  end

  defp normalize_string_list(value, field), do: {:error, {:invalid_list, field, value}}

  defp normalize_transport(nil) do
    {:ok, Application.get_env(:codex_sdk, :default_transport, :exec)}
  end

  defp normalize_transport(:exec), do: {:ok, :exec}
  defp normalize_transport("exec"), do: {:ok, :exec}

  defp normalize_transport({:app_server, pid}) when is_pid(pid), do: {:ok, {:app_server, pid}}

  defp normalize_transport(value), do: {:error, {:invalid_transport, value}}

  defp normalize_sandbox(nil), do: {:ok, :default}
  defp normalize_sandbox(:default), do: {:ok, :default}
  defp normalize_sandbox(:strict), do: {:ok, :strict}
  defp normalize_sandbox(:permissive), do: {:ok, :permissive}
  defp normalize_sandbox(:read_only), do: {:ok, :read_only}
  defp normalize_sandbox(:workspace_write), do: {:ok, :workspace_write}
  defp normalize_sandbox(:danger_full_access), do: {:ok, :danger_full_access}
  defp normalize_sandbox(:external_sandbox), do: {:ok, :external_sandbox}
  defp normalize_sandbox({:external_sandbox, :enabled}), do: {:ok, {:external_sandbox, :enabled}}

  defp normalize_sandbox({:external_sandbox, :restricted}),
    do: {:ok, {:external_sandbox, :restricted}}

  defp normalize_sandbox("read-only"), do: {:ok, :read_only}
  defp normalize_sandbox("workspace-write"), do: {:ok, :workspace_write}
  defp normalize_sandbox("danger-full-access"), do: {:ok, :danger_full_access}
  defp normalize_sandbox("external-sandbox"), do: {:ok, :external_sandbox}

  defp normalize_sandbox(value) when is_binary(value) do
    # Accept arbitrary strings for forward compatibility with the upstream CLI, but
    # keep validating common values.
    {:ok, value}
  end

  defp normalize_sandbox(value), do: {:error, {:invalid_sandbox, value}}

  defp normalize_sandbox_policy(nil), do: {:ok, nil}
  defp normalize_sandbox_policy(%{} = policy), do: {:ok, policy}
  defp normalize_sandbox_policy(policy) when is_list(policy), do: {:ok, Map.new(policy)}
  defp normalize_sandbox_policy(policy) when is_atom(policy), do: {:ok, %{type: policy}}
  defp normalize_sandbox_policy(policy) when is_binary(policy), do: {:ok, %{type: policy}}
  defp normalize_sandbox_policy(value), do: {:error, {:invalid_sandbox_policy, value}}

  defp normalize_color(nil), do: {:ok, nil}
  defp normalize_color(:auto), do: {:ok, :auto}
  defp normalize_color(:always), do: {:ok, :always}
  defp normalize_color(:never), do: {:ok, :never}
  defp normalize_color("auto"), do: {:ok, :auto}
  defp normalize_color("always"), do: {:ok, :always}
  defp normalize_color("never"), do: {:ok, :never}
  defp normalize_color(value) when is_binary(value), do: {:ok, value}
  defp normalize_color(value), do: {:error, {:invalid_color, value}}

  defp normalize_config_overrides(nil), do: {:ok, []}

  defp normalize_config_overrides(%{} = overrides) do
    {:ok, Enum.map(overrides, fn {key, value} -> {to_string(key), value} end)}
  end

  defp normalize_config_overrides(overrides) when is_list(overrides) do
    cond do
      Keyword.keyword?(overrides) ->
        {:ok, Enum.map(overrides, fn {key, value} -> {to_string(key), value} end)}

      Enum.all?(overrides, &is_binary/1) ->
        {:ok, overrides}

      Enum.all?(overrides, &match?({_, _}, &1)) ->
        {:ok, Enum.map(overrides, fn {key, value} -> {to_string(key), value} end)}

      true ->
        {:error, {:invalid_config_overrides, overrides}}
    end
  end

  defp normalize_config_overrides(value), do: {:error, {:invalid_config_overrides, value}}

  defp normalize_ask_for_approval(nil), do: {:ok, nil}
  defp normalize_ask_for_approval(:untrusted), do: {:ok, :untrusted}
  defp normalize_ask_for_approval(:on_failure), do: {:ok, :on_failure}
  defp normalize_ask_for_approval(:on_request), do: {:ok, :on_request}
  defp normalize_ask_for_approval(:never), do: {:ok, :never}
  defp normalize_ask_for_approval("untrusted"), do: {:ok, :untrusted}
  defp normalize_ask_for_approval("on-failure"), do: {:ok, :on_failure}
  defp normalize_ask_for_approval("on-request"), do: {:ok, :on_request}
  defp normalize_ask_for_approval("never"), do: {:ok, :never}
  defp normalize_ask_for_approval(value) when is_binary(value), do: {:ok, value}
  defp normalize_ask_for_approval(value), do: {:error, {:invalid_ask_for_approval, value}}
end
