defmodule Codex.Plugins.Marketplace do
  @moduledoc """
  Local authoring model for `.agents/plugins/marketplace.json`.
  """

  use TypedStruct

  alias CliSubprocessCore.Schema.Conventions
  alias Codex.Plugins.Paths
  alias Codex.Protocol.Plugin.{AuthPolicy, InstallPolicy}
  alias Codex.Schema

  @key_mapping %{"display_name" => "displayName"}
  @known_fields ["name", "interface", "plugins"]
  @interface_known_fields ["displayName"]
  @plugin_known_fields ["name", "source", "policy", "category"]
  @source_known_fields ["source", "path"]
  @policy_known_fields ["installation", "authentication", "products"]

  @type source_t :: %{
          source: :local,
          path: String.t(),
          extra: map()
        }

  @type policy_t :: %{
          installation: InstallPolicy.t(),
          authentication: AuthPolicy.t(),
          products: [String.t()] | nil,
          extra: map()
        }

  @type plugin_t :: %{
          name: String.t(),
          source: source_t(),
          policy: policy_t(),
          category: String.t(),
          extra: map()
        }

  @type interface_t :: %{
          display_name: String.t() | nil,
          extra: map()
        }

  typedstruct do
    field(:name, String.t(), enforce: true)
    field(:interface, interface_t() | nil)
    field(:plugins, [plugin_t()], default: [])
    field(:extra, map(), default: %{})
  end

  @doc """
  Returns the schema used to validate marketplace data.
  """
  @spec schema() :: Zoi.schema()
  def schema do
    Zoi.map(
      %{
        "name" => Zoi.any() |> Zoi.transform({__MODULE__, :normalize_name, []}),
        "interface" => optional_interface_schema(),
        "plugins" => Zoi.array(plugin_schema())
      },
      unrecognized_keys: :preserve
    )
  end

  @doc """
  Parses marketplace data into a `%Codex.Plugins.Marketplace{}` struct.
  """
  @spec parse(map() | keyword() | t()) ::
          {:ok, t()}
          | {:error, {:invalid_plugin_marketplace, CliSubprocessCore.Schema.error_detail()}}
  def parse(%__MODULE__{} = value), do: parse(to_map(value))

  def parse(data) do
    data
    |> Schema.normalize_input(@key_mapping)
    |> then(&Schema.parse(schema(), &1, :invalid_plugin_marketplace))
    |> project()
  end

  @doc """
  Parses a single marketplace entry for add/update flows.
  """
  @spec parse_plugin(map() | keyword() | plugin_t()) ::
          {:ok, plugin_t()}
          | {:error,
             {:invalid_plugin_marketplace_plugin, CliSubprocessCore.Schema.error_detail()}}
  def parse_plugin(%{} = plugin)
      when is_map_key(plugin, :source) and is_map_key(plugin, :policy) and
             is_map_key(plugin, :name) do
    parse_plugin(to_plugin_map(plugin))
  end

  def parse_plugin(data) do
    data
    |> Schema.normalize_input(@key_mapping)
    |> then(&Schema.parse(plugin_schema(), &1, :invalid_plugin_marketplace_plugin))
    |> case do
      {:ok, parsed} -> {:ok, build_plugin(parsed)}
      {:error, _reason} = error -> error
    end
  end

  @doc """
  Parses marketplace data and raises on invalid input.
  """
  @spec parse!(map() | keyword() | t()) :: t()
  def parse!(data) do
    case parse(data) do
      {:ok, marketplace} -> marketplace
      {:error, {tag, details}} -> raise CliSubprocessCore.Schema.Error, tag: tag, details: details
    end
  end

  @doc """
  Compatibility alias for `parse!/1`.
  """
  @spec from_map(map() | keyword() | t()) :: t()
  def from_map(data), do: parse!(data)

  @doc """
  Serializes a marketplace struct back into canonical JSON-compatible data.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = value) do
    %{}
    |> Schema.put_present("name", value.name)
    |> Schema.put_present("interface", encode_interface(value.interface))
    |> Map.put("plugins", Enum.map(value.plugins, &encode_plugin/1))
    |> Schema.merge_extra(value.extra)
  end

  @doc false
  @spec put_plugin(t(), plugin_t(), keyword()) :: {:ok, t()} | {:error, term()}
  def put_plugin(%__MODULE__{} = marketplace, plugin, opts \\ []) do
    overwrite? = Keyword.get(opts, :overwrite, false)

    case Enum.find_index(marketplace.plugins, &(&1.name == plugin.name)) do
      nil ->
        {:ok, %{marketplace | plugins: marketplace.plugins ++ [plugin]}}

      index when overwrite? ->
        existing_plugin = Enum.at(marketplace.plugins, index)
        merged_plugin = merge_plugin(existing_plugin, plugin)

        {:ok,
         %{marketplace | plugins: List.replace_at(marketplace.plugins, index, merged_plugin)}}

      _index ->
        {:error, {:plugin_conflict, %{plugin_name: plugin.name}}}
    end
  end

  @doc false
  @spec merge(t(), t(), keyword()) :: {:ok, t()} | {:error, term()}
  def merge(%__MODULE__{} = existing, %__MODULE__{} = incoming, opts \\ []) do
    overwrite? = Keyword.get(opts, :overwrite, false)

    with {:ok, plugins} <- merge_plugins(existing.plugins, incoming.plugins, overwrite?) do
      {:ok,
       %__MODULE__{
         name: existing.name || incoming.name,
         interface: merge_interface(existing.interface, incoming.interface),
         plugins: plugins,
         extra: Map.merge(existing.extra, incoming.extra)
       }}
    end
  end

  @doc false
  @spec normalize_name(term(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def normalize_name(value, _opts) when is_binary(value) do
    name = String.trim(value)

    if name == "" do
      {:error, "expected a non-empty marketplace name"}
    else
      {:ok, name}
    end
  end

  def normalize_name(_value, _opts), do: {:error, "expected a marketplace name string"}

  @doc false
  @spec normalize_source_type(term(), keyword()) :: {:ok, :local} | {:error, String.t()}
  def normalize_source_type(:local, _opts), do: {:ok, :local}
  def normalize_source_type("local", _opts), do: {:ok, :local}
  def normalize_source_type(_value, _opts), do: {:error, "expected `local` as the plugin source"}

  @doc false
  @spec normalize_relative_path(term(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def normalize_relative_path(value, _opts), do: Paths.normalize_marketplace_source_path(value)

  defp project({:ok, parsed}), do: {:ok, build(parsed)}
  defp project({:error, _reason} = error), do: error

  defp build(parsed) do
    {known, extra} = Schema.split_extra(parsed, @known_fields)

    %__MODULE__{
      name: Map.fetch!(known, "name"),
      interface: build_interface(Map.get(known, "interface")),
      plugins: Enum.map(Map.get(known, "plugins", []), &build_plugin/1),
      extra: extra
    }
  end

  defp build_interface(nil), do: nil

  defp build_interface(%{} = interface) do
    {known, extra} = Schema.split_extra(interface, @interface_known_fields)
    interface_map = %{display_name: Map.get(known, "displayName"), extra: extra}
    if interface_map.display_name == nil and extra == %{}, do: nil, else: interface_map
  end

  defp build_plugin(parsed) do
    {known, extra} = Schema.split_extra(parsed, @plugin_known_fields)

    %{
      name: Map.fetch!(known, "name"),
      source: build_source(Map.fetch!(known, "source")),
      policy: build_policy(Map.fetch!(known, "policy")),
      category: Map.fetch!(known, "category"),
      extra: extra
    }
  end

  defp build_source(parsed) do
    {known, extra} = Schema.split_extra(parsed, @source_known_fields)

    %{
      source: Map.fetch!(known, "source"),
      path: Map.fetch!(known, "path"),
      extra: extra
    }
  end

  defp build_policy(parsed) do
    {known, extra} = Schema.split_extra(parsed, @policy_known_fields)

    %{
      installation: Map.fetch!(known, "installation"),
      authentication: Map.fetch!(known, "authentication"),
      products: Map.get(known, "products"),
      extra: extra
    }
  end

  defp encode_interface(nil), do: nil

  defp encode_interface(interface) do
    %{}
    |> Schema.put_present("displayName", interface[:display_name])
    |> Schema.merge_extra(interface[:extra] || %{})
  end

  defp encode_plugin(plugin) do
    %{}
    |> Schema.put_present("name", plugin[:name])
    |> Schema.put_present("source", encode_source(plugin[:source]))
    |> Schema.put_present("policy", encode_policy(plugin[:policy]))
    |> Schema.put_present("category", plugin[:category])
    |> Schema.merge_extra(plugin[:extra] || %{})
  end

  defp encode_source(source) do
    %{}
    |> Map.put("source", "local")
    |> Schema.put_present("path", source[:path])
    |> Schema.merge_extra(source[:extra] || %{})
  end

  defp encode_policy(policy) do
    %{}
    |> Map.put("installation", InstallPolicy.to_wire(policy[:installation]))
    |> Map.put("authentication", AuthPolicy.to_wire(policy[:authentication]))
    |> Schema.put_present("products", policy[:products])
    |> Schema.merge_extra(policy[:extra] || %{})
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

  defp optional_interface_schema do
    Zoi.optional(
      Zoi.nullish(Zoi.map(%{"displayName" => optional_string()}, unrecognized_keys: :preserve))
    )
  end

  defp plugin_schema do
    Zoi.map(
      %{
        "name" =>
          Zoi.any() |> Zoi.transform({Codex.Plugins.Manifest, :normalize_plugin_name, []}),
        "source" => source_schema(),
        "policy" => policy_schema(),
        "category" => required_string()
      },
      unrecognized_keys: :preserve
    )
  end

  defp source_schema do
    Zoi.map(
      %{
        "source" => Zoi.any() |> Zoi.transform({__MODULE__, :normalize_source_type, []}),
        "path" => Zoi.any() |> Zoi.transform({__MODULE__, :normalize_relative_path, []})
      },
      unrecognized_keys: :preserve
    )
  end

  defp policy_schema do
    Zoi.map(
      %{
        "installation" => InstallPolicy.schema(),
        "authentication" => AuthPolicy.schema(),
        "products" => optional_string_list()
      },
      unrecognized_keys: :preserve
    )
  end

  defp merge_interface(nil, interface), do: interface
  defp merge_interface(interface, nil), do: interface

  defp merge_interface(existing, incoming) do
    %{
      display_name: existing[:display_name] || incoming[:display_name],
      extra: Map.merge(existing[:extra] || %{}, incoming[:extra] || %{})
    }
  end

  defp merge_plugins(existing_plugins, incoming_plugins, overwrite?) do
    Enum.reduce_while(incoming_plugins, {:ok, existing_plugins}, fn plugin, {:ok, acc} ->
      case put_plugin(%__MODULE__{name: "merged", plugins: acc}, plugin, overwrite: overwrite?) do
        {:ok, %{plugins: plugins}} ->
          {:cont, {:ok, plugins}}

        {:error, {:plugin_conflict, %{plugin_name: plugin_name}}} ->
          {:halt, {:error, {:plugin_conflict, %{plugin_name: plugin_name}}}}
      end
    end)
  end

  defp merge_plugin(nil, incoming), do: incoming

  defp merge_plugin(existing, incoming) do
    %{
      name: incoming[:name] || existing[:name],
      source: merge_source(existing[:source], incoming[:source]),
      policy: merge_policy(existing[:policy], incoming[:policy]),
      category: incoming[:category] || existing[:category],
      extra: Map.merge(existing[:extra] || %{}, incoming[:extra] || %{})
    }
  end

  defp merge_source(nil, source), do: source
  defp merge_source(source, nil), do: source

  defp merge_source(existing, incoming) do
    %{
      source: incoming[:source] || existing[:source],
      path: incoming[:path] || existing[:path],
      extra: Map.merge(existing[:extra] || %{}, incoming[:extra] || %{})
    }
  end

  defp merge_policy(nil, policy), do: policy
  defp merge_policy(policy, nil), do: policy

  defp merge_policy(existing, incoming) do
    %{
      installation: incoming[:installation] || existing[:installation],
      authentication: incoming[:authentication] || existing[:authentication],
      products: incoming[:products] || existing[:products],
      extra: Map.merge(existing[:extra] || %{}, incoming[:extra] || %{})
    }
  end

  defp to_plugin_map(plugin) do
    %{
      "name" => plugin[:name] || plugin["name"],
      "source" => plugin[:source] || plugin["source"],
      "policy" => plugin[:policy] || plugin["policy"],
      "category" => plugin[:category] || plugin["category"]
    }
    |> Schema.merge_extra(Map.get(plugin, :extra, Map.get(plugin, "extra", %{})))
  end
end
