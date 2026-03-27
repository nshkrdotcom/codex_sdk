defmodule Codex.Plugins.Manifest do
  @moduledoc """
  Local authoring model for `.codex-plugin/plugin.json`.
  """

  use TypedStruct

  alias CliSubprocessCore.Schema.Conventions
  alias Codex.Plugins.Paths
  alias Codex.Schema

  @key_mapping %{
    "mcp_servers" => "mcpServers",
    "display_name" => "displayName",
    "short_description" => "shortDescription",
    "long_description" => "longDescription",
    "developer_name" => "developerName",
    "website_url" => "websiteURL",
    "websiteUrl" => "websiteURL",
    "privacy_policy_url" => "privacyPolicyURL",
    "privacyPolicyUrl" => "privacyPolicyURL",
    "terms_of_service_url" => "termsOfServiceURL",
    "termsOfServiceUrl" => "termsOfServiceURL",
    "default_prompt" => "defaultPrompt",
    "brand_color" => "brandColor",
    "composer_icon" => "composerIcon"
  }
  @known_fields [
    "name",
    "version",
    "description",
    "author",
    "homepage",
    "repository",
    "license",
    "keywords",
    "skills",
    "hooks",
    "mcpServers",
    "apps",
    "interface"
  ]
  @author_known_fields ["name", "email", "url"]
  @interface_known_fields [
    "displayName",
    "shortDescription",
    "longDescription",
    "developerName",
    "category",
    "capabilities",
    "websiteURL",
    "privacyPolicyURL",
    "termsOfServiceURL",
    "defaultPrompt",
    "brandColor",
    "composerIcon",
    "logo",
    "screenshots"
  ]

  @type author_t :: %{
          name: String.t() | nil,
          email: String.t() | nil,
          url: String.t() | nil,
          extra: map()
        }

  @type interface_t :: %{
          display_name: String.t() | nil,
          short_description: String.t() | nil,
          long_description: String.t() | nil,
          developer_name: String.t() | nil,
          category: String.t() | nil,
          capabilities: [String.t()] | nil,
          website_url: String.t() | nil,
          privacy_policy_url: String.t() | nil,
          terms_of_service_url: String.t() | nil,
          default_prompt: [String.t()] | nil,
          brand_color: String.t() | nil,
          composer_icon: String.t() | nil,
          logo: String.t() | nil,
          screenshots: [String.t()] | nil,
          extra: map()
        }

  typedstruct do
    field(:name, String.t(), enforce: true)
    field(:version, String.t() | nil)
    field(:description, String.t() | nil)
    field(:author, author_t() | nil)
    field(:homepage, String.t() | nil)
    field(:repository, String.t() | nil)
    field(:license, String.t() | nil)
    field(:keywords, [String.t()] | nil)
    field(:skills, String.t() | nil)
    field(:hooks, String.t() | nil)
    field(:mcp_servers, String.t() | nil)
    field(:apps, String.t() | nil)
    field(:interface, interface_t() | nil)
    field(:extra, map(), default: %{})
  end

  @doc """
  Returns the schema used to validate manifest data.
  """
  @spec schema() :: Zoi.schema()
  def schema do
    Zoi.map(
      %{
        "name" => Zoi.any() |> Zoi.transform({__MODULE__, :normalize_plugin_name, []}),
        "version" => optional_string(),
        "description" => optional_string(),
        "author" => optional_author_schema(),
        "homepage" => optional_string(),
        "repository" => optional_string(),
        "license" => optional_string(),
        "keywords" => optional_string_list(),
        "skills" => optional_relative_path_schema("skills"),
        "hooks" => optional_relative_path_schema("hooks"),
        "mcpServers" => optional_relative_path_schema("mcpServers"),
        "apps" => optional_relative_path_schema("apps"),
        "interface" => optional_interface_schema()
      },
      unrecognized_keys: :preserve
    )
  end

  @doc """
  Parses manifest data into a `%Codex.Plugins.Manifest{}` struct.
  """
  @spec parse(map() | keyword() | t()) ::
          {:ok, t()}
          | {:error, {:invalid_plugin_manifest, CliSubprocessCore.Schema.error_detail()}}
  def parse(%__MODULE__{} = value), do: parse(to_map(value))

  def parse(data) do
    data
    |> normalize_input()
    |> then(&Schema.parse(schema(), &1, :invalid_plugin_manifest))
    |> project()
  end

  @doc """
  Parses manifest data and raises on invalid input.
  """
  @spec parse!(map() | keyword() | t()) :: t()
  def parse!(data) do
    case parse(data) do
      {:ok, manifest} -> manifest
      {:error, {tag, details}} -> raise CliSubprocessCore.Schema.Error, tag: tag, details: details
    end
  end

  @doc """
  Compatibility alias for `parse!/1`.
  """
  @spec from_map(map() | keyword() | t()) :: t()
  def from_map(data), do: parse!(data)

  @doc """
  Serializes a manifest struct back into canonical JSON-compatible data.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = value) do
    %{}
    |> maybe_put("name", value.name)
    |> maybe_put("version", value.version)
    |> maybe_put("description", value.description)
    |> maybe_put("author", encode_author(value.author))
    |> maybe_put("homepage", value.homepage)
    |> maybe_put("repository", value.repository)
    |> maybe_put("license", value.license)
    |> maybe_put("keywords", value.keywords)
    |> maybe_put("skills", value.skills)
    |> maybe_put("hooks", value.hooks)
    |> maybe_put("mcpServers", value.mcp_servers)
    |> maybe_put("apps", value.apps)
    |> maybe_put("interface", encode_interface(value.interface))
    |> Schema.merge_extra(value.extra)
  end

  @doc false
  @spec normalize_plugin_name(term(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def normalize_plugin_name(value, _opts) when is_binary(value) do
    name = String.trim(value)

    cond do
      name == "" ->
        {:error, "expected a non-empty plugin name"}

      Regex.match?(~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/, name) ->
        {:ok, name}

      true ->
        {:error, "expected a kebab-case plugin name"}
    end
  end

  def normalize_plugin_name(_value, _opts), do: {:error, "expected a plugin name string"}

  @doc false
  @spec normalize_relative_path(term(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, String.t()}
  def normalize_relative_path(value, _field, _opts) do
    Paths.normalize_relative_path(value)
  end

  @doc false
  @spec normalize_default_prompt(term(), keyword()) ::
          {:ok, [String.t()]} | {:error, String.t()}
  def normalize_default_prompt(value, _opts) when is_binary(value) do
    prompt = String.trim(value)

    if prompt == "" do
      {:error, "expected a non-empty prompt string"}
    else
      {:ok, [prompt]}
    end
  end

  def normalize_default_prompt(values, _opts) when is_list(values) do
    values
    |> Enum.reduce_while({:ok, []}, fn
      value, {:ok, acc} when is_binary(value) ->
        prompt = String.trim(value)

        if prompt == "" do
          {:halt, {:error, "expected non-empty prompt strings"}}
        else
          {:cont, {:ok, acc ++ [prompt]}}
        end

      _value, _acc ->
        {:halt, {:error, "expected a string or a list of strings"}}
    end)
  end

  def normalize_default_prompt(_value, _opts),
    do: {:error, "expected a string or a list of strings"}

  defp project({:ok, parsed}), do: {:ok, build(parsed)}
  defp project({:error, _reason} = error), do: error

  defp build(parsed) do
    {known, extra} = Schema.split_extra(parsed, @known_fields)

    %__MODULE__{
      name: Map.fetch!(known, "name"),
      version: Map.get(known, "version"),
      description: Map.get(known, "description"),
      author: build_author(Map.get(known, "author")),
      homepage: Map.get(known, "homepage"),
      repository: Map.get(known, "repository"),
      license: Map.get(known, "license"),
      keywords: Map.get(known, "keywords"),
      skills: Map.get(known, "skills"),
      hooks: Map.get(known, "hooks"),
      mcp_servers: Map.get(known, "mcpServers"),
      apps: Map.get(known, "apps"),
      interface: build_interface(Map.get(known, "interface")),
      extra: extra
    }
  end

  defp build_author(nil), do: nil

  defp build_author(%{} = author) do
    {known, extra} = Schema.split_extra(author, @author_known_fields)

    author_map = %{
      name: Map.get(known, "name"),
      email: Map.get(known, "email"),
      url: Map.get(known, "url"),
      extra: extra
    }

    if author_empty?(author_map), do: nil, else: author_map
  end

  defp build_interface(nil), do: nil

  defp build_interface(%{} = interface) do
    {known, extra} = Schema.split_extra(interface, @interface_known_fields)

    interface_map = %{
      display_name: Map.get(known, "displayName"),
      short_description: Map.get(known, "shortDescription"),
      long_description: Map.get(known, "longDescription"),
      developer_name: Map.get(known, "developerName"),
      category: Map.get(known, "category"),
      capabilities: Map.get(known, "capabilities"),
      website_url: Map.get(known, "websiteURL"),
      privacy_policy_url: Map.get(known, "privacyPolicyURL"),
      terms_of_service_url: Map.get(known, "termsOfServiceURL"),
      default_prompt: Map.get(known, "defaultPrompt"),
      brand_color: Map.get(known, "brandColor"),
      composer_icon: Map.get(known, "composerIcon"),
      logo: Map.get(known, "logo"),
      screenshots: Map.get(known, "screenshots"),
      extra: extra
    }

    if interface_empty?(interface_map), do: nil, else: interface_map
  end

  defp encode_author(nil), do: nil

  defp encode_author(author) do
    %{}
    |> maybe_put("name", author[:name])
    |> maybe_put("email", author[:email])
    |> maybe_put("url", author[:url])
    |> Schema.merge_extra(author[:extra] || %{})
  end

  defp encode_interface(nil), do: nil

  defp encode_interface(interface) do
    %{}
    |> maybe_put("displayName", interface[:display_name])
    |> maybe_put("shortDescription", interface[:short_description])
    |> maybe_put("longDescription", interface[:long_description])
    |> maybe_put("developerName", interface[:developer_name])
    |> maybe_put("category", interface[:category])
    |> maybe_put("capabilities", interface[:capabilities])
    |> maybe_put("websiteURL", interface[:website_url])
    |> maybe_put("privacyPolicyURL", interface[:privacy_policy_url])
    |> maybe_put("termsOfServiceURL", interface[:terms_of_service_url])
    |> maybe_put("defaultPrompt", interface[:default_prompt])
    |> maybe_put("brandColor", interface[:brand_color])
    |> maybe_put("composerIcon", interface[:composer_icon])
    |> maybe_put("logo", interface[:logo])
    |> maybe_put("screenshots", interface[:screenshots])
    |> Schema.merge_extra(interface[:extra] || %{})
  end

  defp optional_string do
    Zoi.optional(Zoi.nullish(Conventions.trimmed_string()))
  end

  defp required_string do
    Conventions.trimmed_string()
    |> Zoi.min(1)
  end

  defp optional_string_list do
    Zoi.optional(Zoi.nullish(Zoi.array(required_string())))
  end

  defp optional_author_schema do
    Zoi.optional(
      Zoi.nullish(
        Zoi.map(
          %{
            "name" => optional_string(),
            "email" => optional_string(),
            "url" => optional_string()
          },
          unrecognized_keys: :preserve
        )
      )
    )
  end

  defp optional_interface_schema do
    Zoi.optional(
      Zoi.nullish(
        Zoi.map(
          %{
            "displayName" => optional_string(),
            "shortDescription" => optional_string(),
            "longDescription" => optional_string(),
            "developerName" => optional_string(),
            "category" => optional_string(),
            "capabilities" => optional_string_list(),
            "websiteURL" => optional_string(),
            "privacyPolicyURL" => optional_string(),
            "termsOfServiceURL" => optional_string(),
            "defaultPrompt" =>
              Zoi.optional(
                Zoi.nullish(
                  Zoi.any()
                  |> Zoi.transform({__MODULE__, :normalize_default_prompt, []})
                )
              ),
            "brandColor" => optional_string(),
            "composerIcon" => optional_relative_path_schema("interface.composerIcon"),
            "logo" => optional_relative_path_schema("interface.logo"),
            "screenshots" =>
              Zoi.optional(
                Zoi.nullish(
                  Zoi.array(
                    Zoi.any()
                    |> Zoi.transform(
                      {__MODULE__, :normalize_relative_path, ["interface.screenshots"]}
                    )
                  )
                )
              )
          },
          unrecognized_keys: :preserve
        )
      )
    )
  end

  defp optional_relative_path_schema(field) do
    Zoi.optional(
      Zoi.nullish(Zoi.any() |> Zoi.transform({__MODULE__, :normalize_relative_path, [field]}))
    )
  end

  defp normalize_input(nil), do: %{}

  defp normalize_input(list) when is_list(list) do
    if list != [] and Keyword.keyword?(list) do
      list
      |> Enum.into(%{})
      |> normalize_input()
    else
      list
    end
  end

  defp normalize_input(%{} = value) do
    value
    |> Enum.map(fn {key, nested_value} ->
      {normalize_key(key), normalize_value(nested_value)}
    end)
    |> Map.new()
  end

  defp normalize_input(value), do: value

  defp normalize_key(key) when is_atom(key), do: key |> Atom.to_string() |> normalize_key()
  defp normalize_key(key) when is_binary(key), do: Map.get(@key_mapping, key, key)

  defp normalize_value(%{} = value), do: normalize_input(value)

  defp normalize_value(values) when is_list(values) do
    if values != [] and Keyword.keyword?(values) do
      values
      |> Enum.into(%{})
      |> normalize_input()
    else
      Enum.map(values, &normalize_value/1)
    end
  end

  defp normalize_value(value), do: value

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp author_empty?(author) do
    Enum.all?([author[:name], author[:email], author[:url]], &is_nil/1) and author[:extra] == %{}
  end

  defp interface_empty?(interface) do
    Enum.all?(
      [
        interface[:display_name],
        interface[:short_description],
        interface[:long_description],
        interface[:developer_name],
        interface[:category],
        interface[:capabilities],
        interface[:website_url],
        interface[:privacy_policy_url],
        interface[:terms_of_service_url],
        interface[:default_prompt],
        interface[:brand_color],
        interface[:composer_icon],
        interface[:logo],
        interface[:screenshots]
      ],
      &is_nil/1
    ) and interface[:extra] == %{}
  end
end
