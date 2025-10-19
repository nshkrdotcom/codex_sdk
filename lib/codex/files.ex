defmodule Codex.Files do
  @moduledoc """
  Attachment staging helpers mirroring the Python SDK file APIs.
  """

  alias Codex.Files.Registry
  alias Codex.Thread.Options, as: ThreadOptions

  @default_staging_dir Path.join(System.tmp_dir!(), "codex_files")
  @default_ttl_ms 86_400_000

  defmodule Attachment do
    @moduledoc """
    Represents a staged file attachment.
    """

    @enforce_keys [
      :id,
      :name,
      :path,
      :checksum,
      :size,
      :persist,
      :inserted_at,
      :ttl_ms
    ]
    defstruct [
      :id,
      :name,
      :path,
      :checksum,
      :size,
      :persist,
      :inserted_at,
      :ttl_ms
    ]

    @type ttl :: :infinity | non_neg_integer()

    @type t :: %__MODULE__{
            id: String.t(),
            name: String.t(),
            path: Path.t(),
            checksum: String.t(),
            size: non_neg_integer(),
            persist: boolean(),
            inserted_at: DateTime.t(),
            ttl_ms: ttl()
          }
  end

  @doc """
  Returns the staging directory path.
  """
  @spec staging_dir() :: Path.t()
  def staging_dir, do: Application.get_env(:codex_sdk, :staging_dir, @default_staging_dir)

  @doc """
  Stages a file for future attachment invocation.

  Options:

    * `:name` - override the attachment name (defaults to the basename of `path`)
    * `:persist` - keep file around indefinitely (default: `false`)
    * `:ttl_ms` - custom time-to-live for ephemeral attachments. Accepts `:infinity` or a
      non-negative integer in milliseconds. Defaults to `Application.get_env/3` lookups of
      `:attachment_ttl_ms` and falls back to 24 hours.
  """
  @spec stage(Path.t(), keyword()) :: {:ok, Attachment.t()} | {:error, term()}
  def stage(path, opts \\ []) when is_binary(path) do
    persist = Keyword.get(opts, :persist, false)

    with {:ok, _pid} <- Registry.ensure_started(),
         :ok <- ensure_staging_dir(),
         {:ok, stat} <- File.stat(path),
         {:ok, checksum} <- checksum(path),
         {:ok, ttl_ms} <- resolve_ttl(opts, persist) do
      name = Keyword.get(opts, :name, Path.basename(path))

      stage_opts = %{
        checksum: checksum,
        name: name,
        persist: persist,
        ttl_ms: ttl_ms,
        size: stat.size,
        source_path: path,
        destination_path: attachment_path(checksum, name)
      }

      Registry.stage(stage_opts)
    end
  end

  @doc """
  Lists staged attachments currently cached.
  """
  @spec list_staged() :: [Attachment.t()]
  def list_staged do
    case Registry.ensure_started() do
      {:ok, _pid} -> Registry.list()
      {:error, _reason} -> []
    end
  end

  @doc """
  Removes staged files that are not marked as persistent.
  """
  @spec force_cleanup() :: :ok
  def force_cleanup do
    with {:ok, _pid} <- Registry.ensure_started() do
      Registry.force_cleanup()
    end
  end

  @doc """
  Deprecated alias retained for backwards compatibility.
  """
  @spec cleanup!() :: :ok
  def cleanup!, do: force_cleanup()

  @doc """
  Resets the staging directory and manifest.
  """
  @spec reset!() :: :ok
  def reset! do
    with {:ok, _pid} <- Registry.ensure_started() do
      Registry.reset(staging_dir())
    end
  end

  @doc """
  Returns high-level staging metrics including counts and total bytes.
  """
  @spec metrics() :: map()
  def metrics do
    with {:ok, _pid} <- Registry.ensure_started() do
      Registry.metrics()
    end
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

  defp checksum(path) do
    with {:ok, data} <- File.read(path) do
      {:ok, :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)}
    end
  end

  defp resolve_ttl(_opts, true), do: {:ok, :infinity}

  defp resolve_ttl(opts, false) do
    case Keyword.get(opts, :ttl_ms, default_ttl()) do
      :infinity ->
        {:ok, :infinity}

      ttl when is_integer(ttl) and ttl >= 0 ->
        {:ok, ttl}

      invalid ->
        {:error, {:invalid_ttl, invalid}}
    end
  end

  defp default_ttl do
    Application.get_env(:codex_sdk, :attachment_ttl_ms, @default_ttl_ms)
  end

  defp ensure_staging_dir do
    File.mkdir_p(staging_dir())
  end

  defp attachment_path(checksum, name) do
    Path.join([staging_dir(), checksum, name])
  end
end
