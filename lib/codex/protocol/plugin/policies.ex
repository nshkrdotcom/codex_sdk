defmodule Codex.Protocol.Plugin.InstallPolicy do
  @moduledoc """
  Plugin install policy values returned by the app-server plugin APIs.
  """

  alias Codex.Schema

  @mapping %{
    "NOT_AVAILABLE" => :not_available,
    "not_available" => :not_available,
    "AVAILABLE" => :available,
    "available" => :available,
    "INSTALLED_BY_DEFAULT" => :installed_by_default,
    "installed_by_default" => :installed_by_default
  }
  @schema Zoi.any() |> Zoi.transform({__MODULE__, :normalize_zoi, []})

  @type t :: :not_available | :available | :installed_by_default | String.t()

  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @spec parse(term()) ::
          {:ok, t()}
          | {:error, {:invalid_plugin_install_policy, CliSubprocessCore.Schema.error_detail()}}
  def parse(value), do: Schema.parse(@schema, value, :invalid_plugin_install_policy)

  @spec parse!(term()) :: t()
  def parse!(value), do: Schema.parse!(@schema, value, :invalid_plugin_install_policy)

  @spec normalize_zoi(term(), keyword()) :: {:ok, t()} | {:error, String.t()}
  def normalize_zoi(value, _opts) do
    normalize(value)
  end

  @spec normalize(term()) :: {:ok, t()} | {:error, String.t()}
  def normalize(value) when is_atom(value), do: normalize(Atom.to_string(value))

  def normalize(value) when is_binary(value) do
    trimmed = String.trim(value)

    cond do
      trimmed == "" ->
        {:error, "expected a non-empty install policy"}

      mapped = @mapping[trimmed] ->
        {:ok, mapped}

      true ->
        {:ok, trimmed}
    end
  end

  def normalize(_value), do: {:error, "expected a plugin install policy string"}

  @spec to_wire(t()) :: String.t()
  def to_wire(:not_available), do: "NOT_AVAILABLE"
  def to_wire(:available), do: "AVAILABLE"
  def to_wire(:installed_by_default), do: "INSTALLED_BY_DEFAULT"
  def to_wire(value) when is_binary(value), do: value
  def to_wire(value) when is_atom(value), do: Atom.to_string(value)
end

defmodule Codex.Protocol.Plugin.AuthPolicy do
  @moduledoc """
  Plugin auth policy values returned by the app-server plugin APIs.
  """

  alias Codex.Schema

  @mapping %{
    "ON_INSTALL" => :on_install,
    "on_install" => :on_install,
    "ON_USE" => :on_use,
    "on_use" => :on_use
  }
  @schema Zoi.any() |> Zoi.transform({__MODULE__, :normalize_zoi, []})

  @type t :: :on_install | :on_use | String.t()

  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @spec parse(term()) ::
          {:ok, t()}
          | {:error, {:invalid_plugin_auth_policy, CliSubprocessCore.Schema.error_detail()}}
  def parse(value), do: Schema.parse(@schema, value, :invalid_plugin_auth_policy)

  @spec parse!(term()) :: t()
  def parse!(value), do: Schema.parse!(@schema, value, :invalid_plugin_auth_policy)

  @spec normalize_zoi(term(), keyword()) :: {:ok, t()} | {:error, String.t()}
  def normalize_zoi(value, _opts) do
    normalize(value)
  end

  @spec normalize(term()) :: {:ok, t()} | {:error, String.t()}
  def normalize(value) when is_atom(value), do: normalize(Atom.to_string(value))

  def normalize(value) when is_binary(value) do
    trimmed = String.trim(value)

    cond do
      trimmed == "" ->
        {:error, "expected a non-empty auth policy"}

      mapped = @mapping[trimmed] ->
        {:ok, mapped}

      true ->
        {:ok, trimmed}
    end
  end

  def normalize(_value), do: {:error, "expected a plugin auth policy string"}

  @spec to_wire(t()) :: String.t()
  def to_wire(:on_install), do: "ON_INSTALL"
  def to_wire(:on_use), do: "ON_USE"
  def to_wire(value) when is_binary(value), do: value
  def to_wire(value) when is_atom(value), do: Atom.to_string(value)
end
