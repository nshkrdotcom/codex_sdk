defmodule Codex.AppServer.Params do
  @moduledoc false

  alias Codex.Protocol.ByteRange
  alias Codex.Protocol.CollaborationMode
  alias Codex.Protocol.TextElement

  @spec normalize_map(map() | keyword() | nil) :: map()
  def normalize_map(nil), do: %{}
  def normalize_map(%{} = map), do: map
  def normalize_map(list) when is_list(list), do: Map.new(list)

  @spec ask_for_approval(atom() | String.t() | nil) :: String.t() | nil
  def ask_for_approval(nil), do: nil
  def ask_for_approval(:untrusted), do: "untrusted"
  def ask_for_approval(:on_failure), do: "on-failure"
  def ask_for_approval(:on_request), do: "on-request"
  def ask_for_approval(:never), do: "never"
  def ask_for_approval("untrusted"), do: "untrusted"
  def ask_for_approval("on-failure"), do: "on-failure"
  def ask_for_approval("on-request"), do: "on-request"
  def ask_for_approval("never"), do: "never"
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
  def personality("friendly"), do: "friendly"
  def personality("pragmatic"), do: "pragmatic"
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
      "writableRoots",
      fetch_any(policy, [:writable_roots, "writable_roots", :writableRoots, "writableRoots"])
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
