defmodule Codex.AppServer.Params do
  @moduledoc false

  alias Codex.Protocol.ByteRange
  alias Codex.Protocol.CollaborationMode
  alias Codex.Protocol.TextElement

  @spec normalize_map(map() | keyword() | nil) :: map()
  def normalize_map(nil), do: %{}
  def normalize_map(%{} = map), do: map
  def normalize_map(list) when is_list(list), do: Map.new(list)

  @spec ask_for_approval(map() | keyword() | atom() | String.t() | nil) ::
          map() | String.t() | nil
  def ask_for_approval(nil), do: nil
  def ask_for_approval(:untrusted), do: "untrusted"
  def ask_for_approval(:on_failure), do: "on-failure"
  def ask_for_approval(:on_request), do: "on-request"
  def ask_for_approval(:never), do: "never"
  def ask_for_approval("untrusted"), do: "untrusted"
  def ask_for_approval("on-failure"), do: "on-failure"
  def ask_for_approval("on-request"), do: "on-request"
  def ask_for_approval("never"), do: "never"
  def ask_for_approval(policy) when is_list(policy), do: policy |> Map.new() |> ask_for_approval()

  def ask_for_approval(%{} = policy) do
    policy = normalize_map(policy)

    case fetch_any(policy, [:type, "type"]) do
      value when value in [:granular, "granular"] ->
        %{
          "type" => "granular",
          "sandboxApproval" =>
            truthy?(
              fetch_any(policy, [
                :sandbox_approval,
                "sandbox_approval",
                :sandboxApproval,
                "sandboxApproval"
              ])
            ),
          "rules" => truthy?(fetch_any(policy, [:rules, "rules"])),
          "skillApproval" =>
            truthy?(
              fetch_any(policy, [
                :skill_approval,
                "skill_approval",
                :skillApproval,
                "skillApproval"
              ])
            ),
          "requestPermissions" =>
            truthy?(
              fetch_any(policy, [
                :request_permissions,
                "request_permissions",
                :requestPermissions,
                "requestPermissions"
              ])
            ),
          "mcpElicitations" =>
            truthy?(
              fetch_any(policy, [
                :mcp_elicitations,
                "mcp_elicitations",
                :mcpElicitations,
                "mcpElicitations"
              ])
            )
        }

      _ ->
        nil
    end
  end

  def ask_for_approval(value) when is_binary(value), do: value
  def ask_for_approval(_), do: nil

  @type sandbox_policy ::
          String.t()
          | %{String.t() => String.t()}
          | nil

  @spec sandbox_mode(atom() | String.t() | {atom(), atom()} | nil) :: sandbox_policy()
  def sandbox_mode(nil), do: nil
  def sandbox_mode(:strict), do: "read-only"
  def sandbox_mode(:default), do: nil
  def sandbox_mode(:permissive), do: "danger-full-access"
  def sandbox_mode(:read_only), do: "read-only"
  def sandbox_mode(:workspace_write), do: "workspace-write"
  def sandbox_mode(:danger_full_access), do: "danger-full-access"

  def sandbox_mode(:external_sandbox),
    do: %{"type" => "external-sandbox", "network_access" => "restricted"}

  def sandbox_mode({:external_sandbox, :enabled}),
    do: %{"type" => "external-sandbox", "network_access" => "enabled"}

  def sandbox_mode({:external_sandbox, :restricted}),
    do: %{"type" => "external-sandbox", "network_access" => "restricted"}

  def sandbox_mode("read-only"), do: "read-only"
  def sandbox_mode("workspace-write"), do: "workspace-write"
  def sandbox_mode("danger-full-access"), do: "danger-full-access"
  def sandbox_mode("default"), do: nil

  def sandbox_mode("external-sandbox"),
    do: %{"type" => "external-sandbox", "network_access" => "restricted"}

  def sandbox_mode(value) when is_binary(value), do: value
  def sandbox_mode(_), do: nil

  @type app_sandbox_policy :: map() | nil

  @spec sandbox_policy(term()) :: app_sandbox_policy()
  def sandbox_policy(nil), do: nil
  def sandbox_policy(%{} = policy), do: normalize_sandbox_policy(policy)

  def sandbox_policy(policy) when is_list(policy),
    do: policy |> Map.new() |> normalize_sandbox_policy()

  def sandbox_policy(policy) when is_atom(policy), do: %{"type" => normalize_policy_type(policy)}

  def sandbox_policy(policy) when is_binary(policy),
    do: %{"type" => normalize_policy_type(policy)}

  def sandbox_policy(_), do: nil

  @spec reasoning_effort(atom() | String.t() | nil) :: String.t() | nil
  def reasoning_effort(nil), do: nil
  def reasoning_effort(value) when is_atom(value), do: Atom.to_string(value)
  def reasoning_effort(value) when is_binary(value), do: value
  def reasoning_effort(_), do: nil

  @spec personality(atom() | String.t() | nil) :: String.t() | nil
  def personality(nil), do: nil
  def personality(:friendly), do: "friendly"
  def personality(:pragmatic), do: "pragmatic"
  def personality(:none), do: "none"
  def personality("friendly"), do: "friendly"
  def personality("pragmatic"), do: "pragmatic"
  def personality("none"), do: "none"
  def personality(value) when is_binary(value), do: value
  def personality(_), do: nil

  @type collaboration_mode_map :: %{optional(String.t()) => term()}

  @spec collaboration_mode(term()) :: collaboration_mode_map() | nil
  def collaboration_mode(nil), do: nil

  def collaboration_mode(%CollaborationMode{} = mode) do
    CollaborationMode.to_map(mode)
  end

  def collaboration_mode(%{} = mode) do
    normalized =
      mode
      |> Enum.map(fn {key, value} ->
        key = normalize_collaboration_key(key)
        {key, normalize_collaboration_value(key, value)}
      end)
      |> Map.new()

    normalized
    |> CollaborationMode.from_map()
    |> CollaborationMode.to_map()
  rescue
    _ -> nil
  end

  def collaboration_mode(_), do: nil

  @spec thread_sort_key(atom() | String.t() | nil) :: String.t() | nil
  def thread_sort_key(nil), do: nil
  def thread_sort_key(:created_at), do: "created_at"
  def thread_sort_key(:updated_at), do: "updated_at"
  def thread_sort_key("created_at"), do: "created_at"
  def thread_sort_key("updated_at"), do: "updated_at"
  def thread_sort_key("createdAt"), do: "created_at"
  def thread_sort_key("updatedAt"), do: "updated_at"
  def thread_sort_key(value) when is_binary(value), do: value
  def thread_sort_key(_), do: nil

  @spec thread_source_kind(atom() | String.t() | nil) :: String.t() | nil
  def thread_source_kind(nil), do: nil
  def thread_source_kind(:cli), do: "cli"
  def thread_source_kind(:vscode), do: "vscode"
  def thread_source_kind(:vs_code), do: "vscode"
  def thread_source_kind(:exec), do: "exec"
  def thread_source_kind(:app_server), do: "appServer"
  def thread_source_kind(:sub_agent), do: "subAgent"
  def thread_source_kind(:sub_agent_review), do: "subAgentReview"
  def thread_source_kind(:sub_agent_compact), do: "subAgentCompact"
  def thread_source_kind(:sub_agent_thread_spawn), do: "subAgentThreadSpawn"
  def thread_source_kind(:sub_agent_other), do: "subAgentOther"
  def thread_source_kind(:unknown), do: "unknown"
  def thread_source_kind("app_server"), do: "appServer"
  def thread_source_kind("appServer"), do: "appServer"
  def thread_source_kind("sub_agent"), do: "subAgent"
  def thread_source_kind("subAgent"), do: "subAgent"
  def thread_source_kind("sub_agent_review"), do: "subAgentReview"
  def thread_source_kind("subAgentReview"), do: "subAgentReview"
  def thread_source_kind("sub_agent_compact"), do: "subAgentCompact"
  def thread_source_kind("subAgentCompact"), do: "subAgentCompact"
  def thread_source_kind("sub_agent_thread_spawn"), do: "subAgentThreadSpawn"
  def thread_source_kind("subAgentThreadSpawn"), do: "subAgentThreadSpawn"
  def thread_source_kind("sub_agent_other"), do: "subAgentOther"
  def thread_source_kind("subAgentOther"), do: "subAgentOther"
  def thread_source_kind(value) when is_binary(value), do: value
  def thread_source_kind(_), do: nil

  @spec terminal_size(map() | keyword() | nil) :: map() | nil
  def terminal_size(nil), do: nil
  def terminal_size(size) when is_list(size), do: size |> Map.new() |> terminal_size()

  def terminal_size(%{} = size) do
    size = normalize_map(size)

    %{}
    |> put_optional("rows", fetch_any(size, [:rows, "rows"]))
    |> put_optional("cols", fetch_any(size, [:cols, "cols"]))
    |> case do
      %{} = result when map_size(result) == 0 -> nil
      %{} = result -> result
    end
  end

  def terminal_size(_), do: nil

  @spec per_cwd_extra_user_roots([map() | keyword()] | nil) :: [map()] | nil
  def per_cwd_extra_user_roots(nil), do: nil

  def per_cwd_extra_user_roots(entries) when is_list(entries) do
    entries
    |> Enum.map(&per_cwd_extra_user_root/1)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      list -> list
    end
  end

  def per_cwd_extra_user_roots(_), do: nil

  @spec windows_sandbox_setup_mode(atom() | String.t() | nil) :: String.t() | nil
  def windows_sandbox_setup_mode(nil), do: nil
  def windows_sandbox_setup_mode(:elevate), do: "elevate"
  def windows_sandbox_setup_mode(:unelevated), do: "unelevated"
  def windows_sandbox_setup_mode("elevate"), do: "elevate"
  def windows_sandbox_setup_mode("unelevated"), do: "unelevated"
  def windows_sandbox_setup_mode(value) when is_binary(value), do: value
  def windows_sandbox_setup_mode(_), do: nil

  @spec hazelnut_scope(atom() | String.t() | nil) :: String.t() | nil
  def hazelnut_scope(nil), do: nil
  def hazelnut_scope(:example), do: "example"
  def hazelnut_scope(:workspace_shared), do: "workspace-shared"
  def hazelnut_scope(:all_shared), do: "all-shared"
  def hazelnut_scope(:personal), do: "personal"
  def hazelnut_scope("workspace_shared"), do: "workspace-shared"
  def hazelnut_scope("all_shared"), do: "all-shared"
  def hazelnut_scope(value) when is_binary(value), do: value
  def hazelnut_scope(_), do: nil

  @spec product_surface(atom() | String.t() | nil) :: String.t() | nil
  def product_surface(nil), do: nil
  def product_surface(:chatgpt), do: "chatgpt"
  def product_surface(:codex), do: "codex"
  def product_surface(:api), do: "api"
  def product_surface(:atlas), do: "atlas"
  def product_surface(value) when is_binary(value), do: value
  def product_surface(_), do: nil

  @spec thread_realtime_audio_chunk(map() | keyword() | nil) :: map() | nil
  def thread_realtime_audio_chunk(nil), do: nil

  def thread_realtime_audio_chunk(audio) when is_list(audio),
    do: audio |> Map.new() |> thread_realtime_audio_chunk()

  def thread_realtime_audio_chunk(%{} = audio) do
    audio = normalize_map(audio)

    %{}
    |> put_optional("data", fetch_any(audio, [:data, "data"]))
    |> put_optional(
      "sampleRate",
      fetch_any(audio, [:sample_rate, "sample_rate", :sampleRate, "sampleRate"])
    )
    |> put_optional(
      "numChannels",
      fetch_any(audio, [:num_channels, "num_channels", :numChannels, "numChannels"])
    )
    |> put_optional(
      "samplesPerChannel",
      fetch_any(audio, [
        :samples_per_channel,
        "samples_per_channel",
        :samplesPerChannel,
        "samplesPerChannel"
      ])
    )
    |> case do
      %{} = result when map_size(result) == 0 -> nil
      %{} = result -> result
    end
  end

  def thread_realtime_audio_chunk(_), do: nil

  @spec git_info_update(map() | keyword() | nil) :: map() | nil
  def git_info_update(nil), do: nil

  def git_info_update(git_info) when is_list(git_info),
    do: git_info |> Map.new() |> git_info_update()

  def git_info_update(%{} = git_info) do
    git_info = normalize_map(git_info)

    %{}
    |> put_present("sha", git_info, [:sha, "sha"])
    |> put_present("branch", git_info, [:branch, "branch"])
    |> put_present("originUrl", git_info, [:origin_url, "origin_url", :originUrl, "originUrl"])
    |> case do
      %{} = result when map_size(result) == 0 -> nil
      %{} = result -> result
    end
  end

  def git_info_update(_), do: nil

  @spec merge_strategy(atom() | String.t() | nil) :: String.t() | nil
  def merge_strategy(nil), do: nil
  def merge_strategy(:replace), do: "replace"
  def merge_strategy(:upsert), do: "upsert"
  def merge_strategy("replace"), do: "replace"
  def merge_strategy("upsert"), do: "upsert"
  def merge_strategy(value) when is_binary(value), do: value
  def merge_strategy(_), do: nil

  @type user_input :: map()

  @spec user_input(String.t() | [map()]) :: [user_input()]
  def user_input(input) when is_binary(input) do
    [%{"type" => "text", "text" => input}]
  end

  def user_input(inputs) when is_list(inputs) do
    Enum.map(inputs, &user_input_block/1)
  end

  defp user_input_block(%{"type" => "text"} = block) do
    %{"type" => "text", "text" => Map.get(block, "text") || ""}
    |> put_optional("textElements", normalize_text_elements(block))
  end

  defp user_input_block(%{type: :text} = block) do
    %{"type" => "text", "text" => Map.get(block, :text) || ""}
    |> put_optional("textElements", normalize_text_elements(block))
  end

  defp user_input_block(%{"type" => "image"} = block) do
    %{
      "type" => "image",
      "url" =>
        fetch_any(block, [
          :url,
          "url",
          :image_url,
          "image_url",
          :imageUrl,
          "imageUrl"
        ]) || ""
    }
  end

  defp user_input_block(%{type: :image} = block) do
    %{
      "type" => "image",
      "url" =>
        fetch_any(block, [
          :url,
          "url",
          :image_url,
          "image_url",
          :imageUrl,
          "imageUrl"
        ]) || ""
    }
  end

  defp user_input_block(%{"type" => type} = block) when type in ["localImage", "local_image"] do
    %{"type" => "localImage", "path" => Map.get(block, "path") || ""}
  end

  defp user_input_block(%{type: type} = block) when type in [:local_image, :localImage] do
    %{"type" => "localImage", "path" => Map.get(block, :path) || ""}
  end

  defp user_input_block(%{"type" => "skill"} = block) do
    %{
      "type" => "skill",
      "name" => fetch_any(block, [:name, "name"]) || "",
      "path" => fetch_any(block, [:path, "path"]) || ""
    }
  end

  defp user_input_block(%{type: :skill} = block) do
    %{
      "type" => "skill",
      "name" => fetch_any(block, [:name, "name"]) || "",
      "path" => fetch_any(block, [:path, "path"]) || ""
    }
  end

  defp user_input_block(%{"type" => "mention"} = block) do
    %{
      "type" => "mention",
      "name" => fetch_any(block, [:name, "name"]) || "",
      "path" => fetch_any(block, [:path, "path"]) || ""
    }
  end

  defp user_input_block(%{type: :mention} = block) do
    %{
      "type" => "mention",
      "name" => fetch_any(block, [:name, "name"]) || "",
      "path" => fetch_any(block, [:path, "path"]) || ""
    }
  end

  defp user_input_block(text) when is_binary(text) do
    %{"type" => "text", "text" => text}
  end

  defp user_input_block(other) when is_map(other) do
    other
    |> normalize_map()
    |> Map.new()
    |> ensure_type()
  end

  defp ensure_type(%{"type" => _} = block), do: block
  defp ensure_type(block), do: Map.put(block, "type", "text")

  defp normalize_text_elements(%{} = block) do
    block
    |> fetch_any([:text_elements, "text_elements", :textElements, "textElements"])
    |> normalize_text_elements_list()
  end

  defp normalize_text_elements_list(nil), do: nil

  defp normalize_text_elements_list(elements) when is_list(elements) do
    elements
    |> Enum.map(&normalize_text_element/1)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      list -> list
    end
  end

  defp normalize_text_elements_list(_), do: nil

  defp normalize_text_element(%TextElement{} = element) do
    element
    |> TextElement.to_map()
    |> normalize_text_element()
  end

  defp normalize_text_element(%{} = element) do
    element = normalize_map(element)

    byte_range =
      element
      |> fetch_any([:byte_range, "byte_range", :byteRange, "byteRange"])
      |> normalize_byte_range()

    %{}
    |> put_optional("byteRange", byte_range)
    |> put_optional("placeholder", fetch_any(element, [:placeholder, "placeholder"]))
    |> case do
      %{} = result when map_size(result) == 0 -> nil
      %{} = result -> result
    end
  end

  defp normalize_text_element(_), do: nil

  defp normalize_byte_range(%ByteRange{} = range) do
    ByteRange.to_map(range)
  end

  defp normalize_byte_range(%{} = range) do
    range = normalize_map(range)

    %{}
    |> put_optional("start", fetch_any(range, [:start, "start"]))
    |> put_optional("end", fetch_any(range, [:end, "end"]))
    |> case do
      %{} = result when map_size(result) == 0 -> nil
      %{} = result -> result
    end
  end

  defp normalize_byte_range(_), do: nil

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

  defp normalize_sandbox_policy(%{} = policy) do
    type =
      policy
      |> fetch_any([:type, "type"])
      |> normalize_policy_type()

    %{}
    |> put_optional("type", type)
    |> put_optional(
      "access",
      fetch_any(policy, [:access, "access"])
      |> normalize_read_only_access()
      |> only_for_types(type, ["readOnly"])
    )
    |> put_optional(
      "writableRoots",
      fetch_any(policy, [:writable_roots, "writable_roots", :writableRoots, "writableRoots"])
    )
    |> put_optional(
      "readOnlyAccess",
      fetch_any(policy, [
        :read_only_access,
        "read_only_access",
        :readOnlyAccess,
        "readOnlyAccess"
      ])
      |> normalize_read_only_access()
      |> only_for_types(type, ["workspaceWrite"])
    )
    |> put_optional(
      "networkAccess",
      normalize_network_access(
        type,
        fetch_any(policy, [:network_access, "network_access", :networkAccess, "networkAccess"])
      )
    )
    |> put_optional(
      "excludeTmpdirEnvVar",
      fetch_any(policy, [
        :exclude_tmpdir_env_var,
        "exclude_tmpdir_env_var",
        :excludeTmpdirEnvVar,
        "excludeTmpdirEnvVar"
      ])
    )
    |> put_optional(
      "excludeSlashTmp",
      fetch_any(policy, [
        :exclude_slash_tmp,
        "exclude_slash_tmp",
        :excludeSlashTmp,
        "excludeSlashTmp"
      ])
    )
    |> case do
      %{} = result when map_size(result) == 0 -> nil
      %{} = result -> result
    end
  end

  defp normalize_policy_type(nil), do: nil
  defp normalize_policy_type(:read_only), do: "readOnly"
  defp normalize_policy_type("read-only"), do: "readOnly"
  defp normalize_policy_type("read_only"), do: "readOnly"
  defp normalize_policy_type("readOnly"), do: "readOnly"
  defp normalize_policy_type(:workspace_write), do: "workspaceWrite"
  defp normalize_policy_type("workspace-write"), do: "workspaceWrite"
  defp normalize_policy_type("workspace_write"), do: "workspaceWrite"
  defp normalize_policy_type("workspaceWrite"), do: "workspaceWrite"
  defp normalize_policy_type(:danger_full_access), do: "dangerFullAccess"
  defp normalize_policy_type("danger-full-access"), do: "dangerFullAccess"
  defp normalize_policy_type("danger_full_access"), do: "dangerFullAccess"
  defp normalize_policy_type("dangerFullAccess"), do: "dangerFullAccess"
  defp normalize_policy_type(:external_sandbox), do: "externalSandbox"
  defp normalize_policy_type("external-sandbox"), do: "externalSandbox"
  defp normalize_policy_type("external_sandbox"), do: "externalSandbox"
  defp normalize_policy_type("externalSandbox"), do: "externalSandbox"
  defp normalize_policy_type(value) when is_atom(value), do: value |> Atom.to_string()
  defp normalize_policy_type(value) when is_binary(value), do: value
  defp normalize_policy_type(_), do: nil

  defp normalize_network_access("externalSandbox", value),
    do: normalize_external_network_access(value)

  defp normalize_network_access(_type, value) do
    case value do
      true -> true
      false -> false
      :enabled -> true
      :restricted -> false
      "enabled" -> true
      "restricted" -> false
      _ -> value
    end
  end

  defp normalize_external_network_access(value) do
    case value do
      :enabled -> "enabled"
      :restricted -> "restricted"
      true -> "enabled"
      false -> "restricted"
      "enabled" -> "enabled"
      "restricted" -> "restricted"
      other -> other
    end
  end

  defp normalize_read_only_access(nil), do: nil

  defp normalize_read_only_access(access) when is_atom(access),
    do: normalize_read_only_access(Atom.to_string(access))

  defp normalize_read_only_access("full_access"), do: %{"type" => "fullAccess"}
  defp normalize_read_only_access("full-access"), do: %{"type" => "fullAccess"}
  defp normalize_read_only_access("fullAccess"), do: %{"type" => "fullAccess"}

  defp normalize_read_only_access("restricted") do
    %{"type" => "restricted", "includePlatformDefaults" => true}
  end

  defp normalize_read_only_access(%{} = access) do
    access = normalize_map(access)
    type = fetch_any(access, [:type, "type"]) |> normalize_read_only_access_type()

    %{}
    |> put_optional("type", type)
    |> put_optional(
      "includePlatformDefaults",
      fetch_any(access, [
        :include_platform_defaults,
        "include_platform_defaults",
        :includePlatformDefaults,
        "includePlatformDefaults"
      ])
    )
    |> put_optional(
      "readableRoots",
      fetch_any(access, [:readable_roots, "readable_roots", :readableRoots, "readableRoots"])
    )
    |> case do
      %{"type" => "fullAccess"} = result -> result
      %{} = result when map_size(result) == 0 -> nil
      %{} = result -> result
    end
  end

  defp normalize_read_only_access(_), do: nil

  defp normalize_read_only_access_type(nil), do: nil
  defp normalize_read_only_access_type(:restricted), do: "restricted"
  defp normalize_read_only_access_type("restricted"), do: "restricted"
  defp normalize_read_only_access_type(:full_access), do: "fullAccess"
  defp normalize_read_only_access_type("full_access"), do: "fullAccess"
  defp normalize_read_only_access_type("full-access"), do: "fullAccess"
  defp normalize_read_only_access_type("fullAccess"), do: "fullAccess"
  defp normalize_read_only_access_type(value) when is_binary(value), do: value
  defp normalize_read_only_access_type(_), do: nil

  defp per_cwd_extra_user_root(entry) when is_list(entry),
    do: entry |> Map.new() |> per_cwd_extra_user_root()

  defp per_cwd_extra_user_root(%{} = entry) do
    entry = normalize_map(entry)
    cwd = fetch_any(entry, [:cwd, "cwd"])

    roots =
      fetch_any(entry, [:extra_user_roots, "extra_user_roots", :extraUserRoots, "extraUserRoots"])

    if is_binary(cwd) and is_list(roots) do
      %{"cwd" => cwd, "extraUserRoots" => roots}
    end
  end

  defp per_cwd_extra_user_root(_), do: nil

  defp put_present(map, key, source, lookup_keys) do
    case fetch_present(source, lookup_keys) do
      {:ok, value} -> Map.put(map, key, value)
      :error -> map
    end
  end

  defp fetch_present(map, keys) when is_map(map) and is_list(keys) do
    Enum.find_value(keys, :error, fn key ->
      case Map.has_key?(map, key) do
        true -> {:ok, Map.get(map, key)}
        false -> nil
      end
    end)
  end

  defp fetch_present(_map, _keys), do: :error

  defp only_for_types(value, nil, _types), do: value

  defp only_for_types(value, type, types) do
    if type in types, do: value, else: nil
  end

  defp truthy?(value), do: value in [true, "true", 1, "1"]

  defp fetch_any(map, keys) when is_list(keys) and is_map(map) do
    Enum.reduce_while(keys, nil, fn key, _acc ->
      case Map.fetch(map, key) do
        {:ok, value} -> {:halt, value}
        :error -> {:cont, nil}
      end
    end)
  end

  def put_optional(map, _key, nil), do: map
  def put_optional(map, _key, []), do: map
  def put_optional(map, key, value), do: Map.put(map, key, value)
end
