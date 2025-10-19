defmodule Codex.Files do
  @moduledoc """
  Attachment staging helpers mirroring the Python SDK file APIs.
  """

  alias Codex.Thread.Options, as: ThreadOptions

  @manifest_table :codex_files_manifest
  @default_staging_dir Path.join(System.tmp_dir!(), "codex_files")

  defmodule Attachment do
    @moduledoc """
    Represents a staged file attachment.
    """

    @enforce_keys [:id, :name, :path, :checksum, :size, :persist]
    defstruct [:id, :name, :path, :checksum, :size, :persist]

    @type t :: %__MODULE__{
            id: String.t(),
            name: String.t(),
            path: Path.t(),
            checksum: String.t(),
            size: non_neg_integer(),
            persist: boolean()
          }
  end

  @doc """
  Returns the staging directory path.
  """
  @spec staging_dir() :: Path.t()
  def staging_dir, do: Application.get_env(:codex_sdk, :staging_dir, @default_staging_dir)

  @doc """
  Stages a file for future attachment invocation.
  """
  @spec stage(Path.t(), keyword()) :: {:ok, Attachment.t()} | {:error, term()}
  def stage(path, opts \\ []) when is_binary(path) do
    with :ok <- ensure_staging_dir(),
         :ok <- ensure_manifest(),
         {:ok, data} <- File.read(path),
         {:ok, stat} <- File.stat(path) do
      checksum = :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)
      persist = Keyword.get(opts, :persist, false)
      name = Keyword.get(opts, :name, Path.basename(path))

      case :ets.lookup(@manifest_table, checksum) do
        [{^checksum, %{persist: existing_persist} = attachment}] ->
          updated = %{attachment | persist: existing_persist || persist}
          :ets.insert(@manifest_table, {checksum, updated})
          {:ok, updated}

        [] ->
          dest_path = attachment_path(checksum, name)
          File.mkdir_p!(Path.dirname(dest_path))
          File.cp!(path, dest_path)

          attachment = %Attachment{
            id: checksum,
            name: name,
            path: dest_path,
            checksum: checksum,
            size: stat.size,
            persist: persist
          }

          :ets.insert(@manifest_table, {checksum, attachment})
          {:ok, attachment}
      end
    end
  end

  @doc """
  Lists staged attachments currently cached.
  """
  @spec list_staged() :: [Attachment.t()]
  def list_staged do
    ensure_manifest()

    :ets.tab2list(@manifest_table)
    |> Enum.map(fn {_checksum, attachment} -> attachment end)
  end

  @doc """
  Removes staged files that are not marked as persistent.
  """
  @spec cleanup!() :: :ok
  def cleanup! do
    ensure_manifest()

    for {checksum, attachment} <- :ets.tab2list(@manifest_table) do
      if attachment.persist do
        :ok
      else
        File.rm_rf(attachment.path)
        :ets.delete(@manifest_table, checksum)
      end
    end

    :ok
  end

  @doc """
  Resets the staging directory and manifest.
  """
  @spec reset!() :: :ok
  def reset! do
    case :ets.whereis(@manifest_table) do
      :undefined -> :ok
      _ -> :ets.delete(@manifest_table)
    end

    File.rm_rf(staging_dir())
    ensure_manifest()
    :ok
  end

  @doc """
  Attaches an `Attachment` to the supplied `ThreadOptions`.
  """
  @spec attach(ThreadOptions.t(), Attachment.t()) :: ThreadOptions.t()
  def attach(%ThreadOptions{} = opts, %Attachment{} = attachment) do
    updated =
      opts.attachments
      |> Enum.reject(&(&1.id == attachment.id))
      |> Kernel.++([attachment])

    %{opts | attachments: updated}
  end

  defp ensure_manifest do
    case :ets.whereis(@manifest_table) do
      :undefined ->
        :ets.new(@manifest_table, [:named_table, :set, :public, read_concurrency: true])
        :ok

      _ ->
        :ok
    end
  end

  defp ensure_staging_dir do
    staging_dir() |> File.mkdir_p()
  end

  defp attachment_path(checksum, name) do
    Path.join([staging_dir(), checksum, name])
  end
end
