defmodule Codex.Thread.Options do
  @moduledoc """
  Per-thread configuration options.
  """

  # credo:disable-for-this-file Credo.Check.Warning.StructFieldAmount

  alias Codex.Config.OptionNormalizers
  alias Codex.Config.Overrides
  alias Codex.FileSearch
  alias Codex.Protocol.CollaborationMode

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
            web_search_mode: :disabled,
            web_search_mode_explicit: false,
            personality: nil,
            collaboration_mode: nil,
            compact_prompt: nil,
            show_raw_agent_reasoning: false,
            output_schema: nil,
            apply_patch_freeform_enabled: nil,
            view_image_tool_enabled: nil,
            unified_exec_enabled: nil,
            skills_enabled: nil,
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
            history_persistence: nil,
            history_max_bytes: nil,
            model: nil,
            model_provider: nil,
            model_reasoning_summary: nil,
            model_verbosity: nil,
            model_context_window: nil,
            model_supports_reasoning_summaries: nil,
            request_max_retries: nil,
            stream_max_retries: nil,
            stream_idle_timeout_ms: nil,
            config: nil,
            base_instructions: nil,
            developer_instructions: nil,
            shell_environment_policy: nil,
            retry: nil,
            retry_opts: nil,
            rate_limit: nil,
            rate_limit_opts: nil,
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

  @type reasoning_summary :: :auto | :concise | :detailed | :none | String.t()
  @type model_verbosity :: :low | :medium | :high | String.t()
  @type web_search_mode :: Codex.Protocol.ConfigTypes.web_search_mode()
  @type personality :: Codex.Protocol.ConfigTypes.personality()
  @type collaboration_mode :: Codex.Protocol.CollaborationMode.t()

  @type retry_opts :: keyword()
  @type rate_limit_opts :: keyword()
  @type history_persistence :: String.t()

  @typep config_override_value_scalar :: String.t() | boolean() | integer() | float()
  @type config_override_value ::
          config_override_value_scalar()
          | [config_override_value()]
          | %{optional(String.t() | atom()) => config_override_value()}
  @type config_override :: String.t() | {String.t() | atom(), config_override_value()}

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
          web_search_mode: web_search_mode(),
          web_search_mode_explicit: boolean(),
          personality: personality() | nil,
          collaboration_mode: collaboration_mode() | nil,
          compact_prompt: String.t() | nil,
          show_raw_agent_reasoning: boolean(),
          output_schema: map() | nil,
          apply_patch_freeform_enabled: boolean() | nil,
          view_image_tool_enabled: boolean() | nil,
          unified_exec_enabled: boolean() | nil,
          skills_enabled: boolean() | nil,
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
          history_persistence: history_persistence() | nil,
          history_max_bytes: non_neg_integer() | nil,
          model: String.t() | nil,
          model_provider: String.t() | nil,
          model_reasoning_summary: reasoning_summary() | nil,
          model_verbosity: model_verbosity() | nil,
          model_context_window: pos_integer() | nil,
          model_supports_reasoning_summaries: boolean() | nil,
          request_max_retries: pos_integer() | nil,
          stream_max_retries: pos_integer() | nil,
          stream_idle_timeout_ms: pos_integer() | nil,
          config: map() | nil,
          base_instructions: String.t() | nil,
          developer_instructions: String.t() | nil,
          shell_environment_policy: map() | nil,
          retry: boolean() | nil,
          retry_opts: retry_opts() | nil,
          rate_limit: boolean() | nil,
          rate_limit_opts: rate_limit_opts() | nil,
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

    web_search_enabled_provided? =
      has_any_key?(attrs, [
        :web_search_enabled,
        "web_search_enabled",
        :webSearchEnabled,
        "webSearchEnabled"
      ])

    web_search_mode =
      Map.get(
        attrs,
        :web_search_mode,
        Map.get(
          attrs,
          "web_search_mode",
          Map.get(attrs, :webSearchMode, Map.get(attrs, "webSearchMode"))
        )
      )

    web_search_mode_provided? =
      has_any_key?(attrs, [:web_search_mode, "web_search_mode", :webSearchMode, "webSearchMode"])

    personality = Map.get(attrs, :personality, Map.get(attrs, "personality"))

    collaboration_mode =
      Map.get(attrs, :collaboration_mode, Map.get(attrs, "collaboration_mode"))

    compact_prompt = Map.get(attrs, :compact_prompt, Map.get(attrs, "compact_prompt"))

    show_raw_agent_reasoning =
      Map.get(
        attrs,
        :show_raw_agent_reasoning,
        Map.get(attrs, "show_raw_agent_reasoning", false)
      )

    output_schema = Map.get(attrs, :output_schema, Map.get(attrs, "output_schema"))

    apply_patch_freeform_enabled =
      Map.get(
        attrs,
        :apply_patch_freeform_enabled,
        Map.get(attrs, "apply_patch_freeform_enabled")
      )

    view_image_tool_enabled =
      Map.get(attrs, :view_image_tool_enabled, Map.get(attrs, "view_image_tool_enabled"))

    unified_exec_enabled =
      Map.get(attrs, :unified_exec_enabled, Map.get(attrs, "unified_exec_enabled"))

    skills_enabled = Map.get(attrs, :skills_enabled, Map.get(attrs, "skills_enabled"))

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

    history = Map.get(attrs, :history, Map.get(attrs, "history"))

    history_persistence =
      Map.get(attrs, :history_persistence, Map.get(attrs, "history_persistence"))

    history_max_bytes =
      Map.get(attrs, :history_max_bytes, Map.get(attrs, "history_max_bytes"))

    {history_persistence, history_max_bytes} =
      case history do
        %{} ->
          {
            history_persistence ||
              Map.get(history, :persistence, Map.get(history, "persistence")),
            history_max_bytes ||
              Map.get(
                history,
                :max_bytes,
                Map.get(history, "max_bytes", Map.get(history, "maxBytes"))
              )
          }

        _ ->
          {history_persistence, history_max_bytes}
      end

    model = Map.get(attrs, :model, Map.get(attrs, "model"))

    model_provider =
      Map.get(attrs, :model_provider, Map.get(attrs, "model_provider", Map.get(attrs, :provider)))

    model_reasoning_summary =
      Map.get(attrs, :model_reasoning_summary, Map.get(attrs, "model_reasoning_summary"))

    model_verbosity = Map.get(attrs, :model_verbosity, Map.get(attrs, "model_verbosity"))

    model_context_window =
      Map.get(attrs, :model_context_window, Map.get(attrs, "model_context_window"))

    model_supports_reasoning_summaries =
      Map.get(
        attrs,
        :model_supports_reasoning_summaries,
        Map.get(attrs, "model_supports_reasoning_summaries")
      )

    request_max_retries =
      Map.get(attrs, :request_max_retries, Map.get(attrs, "request_max_retries"))

    stream_max_retries =
      Map.get(attrs, :stream_max_retries, Map.get(attrs, "stream_max_retries"))

    stream_idle_timeout_ms =
      Map.get(attrs, :stream_idle_timeout_ms, Map.get(attrs, "stream_idle_timeout_ms"))

    config = Map.get(attrs, :config, Map.get(attrs, "config"))

    base_instructions =
      Map.get(attrs, :base_instructions, Map.get(attrs, "base_instructions"))

    developer_instructions =
      Map.get(attrs, :developer_instructions, Map.get(attrs, "developer_instructions"))

    shell_environment_policy =
      Map.get(attrs, :shell_environment_policy, Map.get(attrs, "shell_environment_policy"))

    retry = Map.get(attrs, :retry, Map.get(attrs, "retry"))
    retry_opts = Map.get(attrs, :retry_opts, Map.get(attrs, "retry_opts"))
    rate_limit = Map.get(attrs, :rate_limit, Map.get(attrs, "rate_limit"))
    rate_limit_opts = Map.get(attrs, :rate_limit_opts, Map.get(attrs, "rate_limit_opts"))

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
         {:ok, web_search_mode} <- normalize_web_search_mode(web_search_mode),
         {:ok, personality} <- normalize_personality(personality),
         {:ok, collaboration_mode} <- normalize_collaboration_mode(collaboration_mode),
         :ok <- validate_optional_string(compact_prompt, :compact_prompt),
         {:ok, show_raw_agent_reasoning} <-
           validate_optional_boolean(show_raw_agent_reasoning, :show_raw_agent_reasoning),
         {:ok, output_schema} <- ensure_optional_map(output_schema, :output_schema),
         {:ok, apply_patch_freeform_enabled} <-
           validate_optional_boolean(apply_patch_freeform_enabled, :apply_patch_freeform_enabled),
         {:ok, view_image_tool_enabled} <-
           validate_optional_boolean(view_image_tool_enabled, :view_image_tool_enabled),
         {:ok, unified_exec_enabled} <-
           validate_optional_boolean(unified_exec_enabled, :unified_exec_enabled),
         {:ok, skills_enabled} <- validate_optional_boolean(skills_enabled, :skills_enabled),
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
         {:ok, history_persistence} <- normalize_history_persistence(history_persistence),
         :ok <- validate_optional_non_negative_integer(history_max_bytes, :history_max_bytes),
         :ok <- validate_auto_flags(full_auto, dangerously_bypass_approvals_and_sandbox),
         :ok <- validate_optional_string(model, :model),
         :ok <- validate_optional_string(model_provider, :model_provider),
         {:ok, model_reasoning_summary} <- normalize_reasoning_summary(model_reasoning_summary),
         {:ok, model_verbosity} <- normalize_model_verbosity(model_verbosity),
         :ok <- validate_optional_positive_integer(model_context_window, :model_context_window),
         {:ok, model_supports_reasoning_summaries} <-
           validate_optional_boolean(
             model_supports_reasoning_summaries,
             :model_supports_reasoning_summaries
           ),
         :ok <- validate_optional_positive_integer(request_max_retries, :request_max_retries),
         :ok <- validate_optional_positive_integer(stream_max_retries, :stream_max_retries),
         :ok <-
           validate_optional_positive_integer(stream_idle_timeout_ms, :stream_idle_timeout_ms),
         {:ok, config} <- ensure_optional_map(config, :config),
         :ok <- validate_optional_string(base_instructions, :base_instructions),
         :ok <- validate_optional_string(developer_instructions, :developer_instructions),
         {:ok, shell_environment_policy} <-
           normalize_shell_environment_policy(shell_environment_policy),
         {:ok, retry} <- validate_optional_boolean(retry, :retry),
         {:ok, retry_opts} <- normalize_optional_keyword_list(retry_opts, :retry_opts),
         {:ok, rate_limit} <- validate_optional_boolean(rate_limit, :rate_limit),
         {:ok, rate_limit_opts} <-
           normalize_optional_keyword_list(rate_limit_opts, :rate_limit_opts),
         :ok <- validate_boolean(experimental_raw_events, :experimental_raw_events),
         :ok <- validate_timeout(approval_timeout_ms) do
      web_search_mode =
        resolve_web_search_mode(
          web_search_mode,
          web_search_enabled,
          web_search_mode_provided?,
          web_search_enabled_provided?,
          config
        )

      web_search_mode_explicit =
        explicit_web_search_mode?(
          web_search_mode,
          web_search_mode_provided?,
          web_search_enabled_provided?
        )

      web_search_enabled = web_search_mode != :disabled
      show_raw_agent_reasoning = show_raw_agent_reasoning || false

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
         web_search_mode: web_search_mode,
         web_search_mode_explicit: web_search_mode_explicit,
         personality: personality,
         collaboration_mode: collaboration_mode,
         compact_prompt: compact_prompt,
         show_raw_agent_reasoning: show_raw_agent_reasoning,
         output_schema: output_schema,
         apply_patch_freeform_enabled: apply_patch_freeform_enabled,
         view_image_tool_enabled: view_image_tool_enabled,
         unified_exec_enabled: unified_exec_enabled,
         skills_enabled: skills_enabled,
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
         history_persistence: history_persistence,
         history_max_bytes: history_max_bytes,
         model: model,
         model_provider: model_provider,
         model_reasoning_summary: model_reasoning_summary,
         model_verbosity: model_verbosity,
         model_context_window: model_context_window,
         model_supports_reasoning_summaries: model_supports_reasoning_summaries,
         request_max_retries: request_max_retries,
         stream_max_retries: stream_max_retries,
         stream_idle_timeout_ms: stream_idle_timeout_ms,
         config: config,
         base_instructions: base_instructions,
         developer_instructions: developer_instructions,
         shell_environment_policy: shell_environment_policy,
         retry: retry,
         retry_opts: retry_opts,
         rate_limit: rate_limit,
         rate_limit_opts: rate_limit_opts,
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

  defp validate_optional_positive_integer(nil, _field), do: :ok

  defp validate_optional_positive_integer(value, _field) when is_integer(value) and value > 0,
    do: :ok

  defp validate_optional_positive_integer(value, field),
    do: {:error, {:"invalid_#{field}", value}}

  defp validate_optional_non_negative_integer(nil, _field), do: :ok

  defp validate_optional_non_negative_integer(value, _field)
       when is_integer(value) and value >= 0,
       do: :ok

  defp validate_optional_non_negative_integer(value, field),
    do: {:error, {:"invalid_#{field}", value}}

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

  defp normalize_history_persistence(value),
    do: OptionNormalizers.normalize_history_persistence(value, :invalid_history_persistence)

  defp normalize_reasoning_summary(value),
    do: OptionNormalizers.normalize_reasoning_summary(value, :invalid_model_reasoning_summary)

  defp normalize_model_verbosity(value),
    do: OptionNormalizers.normalize_model_verbosity(value, :invalid_model_verbosity)

  defp normalize_web_search_mode(nil), do: {:ok, nil}

  defp normalize_web_search_mode(value) when is_atom(value) do
    value
    |> Atom.to_string()
    |> normalize_web_search_mode()
  end

  defp normalize_web_search_mode(value) when is_binary(value) do
    case String.downcase(String.trim(value)) do
      "" -> {:ok, nil}
      "disabled" -> {:ok, :disabled}
      "cached" -> {:ok, :cached}
      "live" -> {:ok, :live}
      other -> {:error, {:invalid_web_search_mode, other}}
    end
  end

  defp normalize_web_search_mode(other), do: {:error, {:invalid_web_search_mode, other}}

  defp resolve_web_search_mode(mode, enabled, mode_provided?, enabled_provided?, config) do
    cond do
      mode_provided? and not is_nil(mode) ->
        mode

      enabled_provided? ->
        if enabled, do: :live, else: :disabled

      true ->
        case web_search_mode_from_config(config) do
          nil -> :disabled
          config_mode -> config_mode
        end
    end
  end

  defp explicit_web_search_mode?(mode, mode_provided?, enabled_provided?) do
    (mode_provided? and not is_nil(mode)) or enabled_provided?
  end

  defp web_search_mode_from_config(%{} = config) do
    case fetch_any(config, [:web_search, "web_search", :webSearch, "webSearch"]) do
      mode when mode in [:disabled, "disabled"] -> :disabled
      mode when mode in [:cached, "cached"] -> :cached
      mode when mode in [:live, "live"] -> :live
      _ -> web_search_mode_from_features(fetch_any(config, [:features, "features"]))
    end
  end

  defp web_search_mode_from_config(_), do: nil

  defp web_search_mode_from_features(%{} = features) do
    cached =
      fetch_any(features, [
        :web_search_cached,
        "web_search_cached",
        :webSearchCached,
        "webSearchCached"
      ])

    live =
      fetch_any(features, [
        :web_search_request,
        "web_search_request",
        :webSearchRequest,
        "webSearchRequest"
      ])

    cond do
      cached in [true, "true"] -> :cached
      live in [true, "true"] -> :live
      true -> nil
    end
  end

  defp web_search_mode_from_features(_), do: nil

  defp normalize_personality(nil), do: {:ok, nil}

  defp normalize_personality(value) when is_atom(value) do
    value
    |> Atom.to_string()
    |> normalize_personality()
  end

  defp normalize_personality(value) when is_binary(value) do
    case String.downcase(String.trim(value)) do
      "" -> {:ok, nil}
      "friendly" -> {:ok, :friendly}
      "pragmatic" -> {:ok, :pragmatic}
      "none" -> {:ok, :none}
      other -> {:error, {:invalid_personality, other}}
    end
  end

  defp normalize_personality(other), do: {:error, {:invalid_personality, other}}

  defp normalize_collaboration_mode(nil), do: {:ok, nil}

  defp normalize_collaboration_mode(%CollaborationMode{} = mode),
    do: {:ok, mode}

  defp normalize_collaboration_mode(%{} = mode) do
    normalized =
      mode
      |> Enum.map(fn {key, value} ->
        key = normalize_collaboration_key(key)
        {key, normalize_collaboration_value(key, value)}
      end)
      |> Map.new()

    {:ok, CollaborationMode.from_map(normalized)}
  rescue
    _ -> {:error, {:invalid_collaboration_mode, mode}}
  end

  defp normalize_collaboration_mode(other), do: {:error, {:invalid_collaboration_mode, other}}

  defp normalize_collaboration_key(key) when is_atom(key),
    do: key |> Atom.to_string() |> normalize_collaboration_key()

  defp normalize_collaboration_key("reasoningEffort"), do: "reasoning_effort"
  defp normalize_collaboration_key("reasoning_effort"), do: "reasoning_effort"
  defp normalize_collaboration_key("developerInstructions"), do: "developer_instructions"
  defp normalize_collaboration_key("developer_instructions"), do: "developer_instructions"
  defp normalize_collaboration_key(key) when is_binary(key), do: key

  defp normalize_collaboration_value("mode", value) when is_atom(value),
    do: Atom.to_string(value)

  defp normalize_collaboration_value("reasoning_effort", value) when is_atom(value),
    do: Atom.to_string(value)

  defp normalize_collaboration_value(_key, value), do: value

  defp normalize_config_overrides(overrides),
    do: Overrides.normalize_config_overrides(overrides)

  defp normalize_shell_environment_policy(nil), do: {:ok, nil}

  defp normalize_shell_environment_policy(%{} = policy) do
    with :ok <- validate_shell_env_inherit(policy),
         :ok <- validate_shell_env_ignore_default_excludes(policy),
         :ok <- validate_shell_env_list(policy, ["exclude", :exclude]),
         :ok <- validate_shell_env_list(policy, ["include_only", :include_only]),
         :ok <- validate_shell_env_set(policy) do
      {:ok, policy}
    end
  end

  defp normalize_shell_environment_policy(list) when is_list(list) do
    normalize_shell_environment_policy(Map.new(list))
  end

  defp normalize_shell_environment_policy(value),
    do: {:error, {:invalid_shell_environment_policy, value}}

  defp validate_shell_env_inherit(policy) do
    case fetch_any(policy, ["inherit", :inherit]) do
      nil -> :ok
      value when is_binary(value) -> :ok
      other -> {:error, {:invalid_shell_environment_inherit, other}}
    end
  end

  defp validate_shell_env_ignore_default_excludes(policy) do
    case fetch_any(policy, ["ignore_default_excludes", :ignore_default_excludes]) do
      nil -> :ok
      value when is_boolean(value) -> :ok
      other -> {:error, {:invalid_shell_environment_ignore_default_excludes, other}}
    end
  end

  defp validate_shell_env_list(policy, keys) do
    case fetch_any(policy, keys) do
      nil ->
        :ok

      value when is_list(value) ->
        if Enum.all?(value, &is_binary/1) do
          :ok
        else
          {:error, {:invalid_shell_environment_list, value}}
        end

      other ->
        {:error, {:invalid_shell_environment_list, other}}
    end
  end

  defp validate_shell_env_set(policy) do
    case fetch_any(policy, ["set", :set]) do
      nil ->
        :ok

      %{} = set ->
        validate_string_map(set, :invalid_shell_environment_set)

      other ->
        {:error, {:invalid_shell_environment_set, other}}
    end
  end

  defp validate_string_map(map, error_tag) do
    if Enum.all?(map, fn {key, value} -> is_binary(key) and is_binary(value) end) do
      :ok
    else
      {:error, {error_tag, map}}
    end
  end

  defp normalize_optional_keyword_list(nil, _field), do: {:ok, nil}

  defp normalize_optional_keyword_list(%{} = value, _field),
    do: {:ok, Map.to_list(value)}

  defp normalize_optional_keyword_list(value, field) when is_list(value) do
    if Keyword.keyword?(value) do
      {:ok, value}
    else
      {:error, {:"invalid_#{field}", value}}
    end
  end

  defp normalize_optional_keyword_list(value, field),
    do: {:error, {:"invalid_#{field}", value}}

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

  defp fetch_any(map, keys) when is_map(map) and is_list(keys) do
    Enum.reduce_while(keys, nil, fn key, _acc ->
      case Map.fetch(map, key) do
        {:ok, value} -> {:halt, value}
        :error -> {:cont, nil}
      end
    end)
  end

  defp has_any_key?(map, keys) when is_map(map) and is_list(keys) do
    Enum.any?(keys, &Map.has_key?(map, &1))
  end

  defp has_any_key?(_map, _keys), do: false
end
