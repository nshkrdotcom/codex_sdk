Mix.Task.run("app.start")

Code.require_file(Path.expand("support/example_helper.exs", __DIR__))

alias CodexExamples.Support

Support.init!()

defmodule CodexExamples.LiveAppServerFilesystem do
  @moduledoc false

  @demo_contents "hello from codex_sdk app-server filesystem\n"

  def main(_argv) do
    case run() do
      :ok ->
        :ok

      {:skip, reason} ->
        IO.puts("SKIPPED: #{reason}")

      {:error, reason} ->
        Mix.raise("Filesystem example failed: #{inspect(reason)}")
    end
  end

  defp run do
    with {:ok, codex_opts} <- Support.codex_options(%{}, missing_cli: :skip),
         :ok <- Support.ensure_auth_available(),
         :ok <- Support.ensure_app_server_supported(codex_opts),
         {:ok, conn} <- Codex.AppServer.connect(codex_opts, init_timeout_ms: 30_000) do
      root =
        Path.join(
          System.tmp_dir!(),
          "codex_sdk_app_server_fs_#{System.unique_integer([:positive])}"
        )

      nested = Path.join(root, "nested")
      file_path = Path.join(nested, "demo.txt")
      copy_path = Path.join(root, "demo-copy.txt")
      encoded = Base.encode64(@demo_contents)

      try do
        with {:ok, %{}} <-
               request_or_skip(
                 Codex.AppServer.fs_create_directory(conn, nested, recursive: true),
                 "fs/* filesystem"
               ),
             {:ok, %{}} <-
               request_or_skip(
                 Codex.AppServer.fs_write_file(conn, file_path, encoded),
                 "fs/* filesystem"
               ),
             {:ok, %{"dataBase64" => read_back}} <-
               request_or_skip(Codex.AppServer.fs_read_file(conn, file_path), "fs/* filesystem"),
             {:ok, %{"entries" => entries}} <-
               request_or_skip(
                 Codex.AppServer.fs_read_directory(conn, root),
                 "fs/* filesystem"
               ),
             {:ok, metadata} <-
               request_or_skip(
                 Codex.AppServer.fs_get_metadata(conn, file_path),
                 "fs/* filesystem"
               ),
             {:ok, %{}} <-
               request_or_skip(
                 Codex.AppServer.fs_copy(conn, file_path, copy_path, recursive: false),
                 "fs/* filesystem"
               ),
             {:ok, %{"dataBase64" => copied_back}} <-
               request_or_skip(Codex.AppServer.fs_read_file(conn, copy_path), "fs/* filesystem"),
             {:ok, %{}} <-
               request_or_skip(
                 Codex.AppServer.fs_remove(conn, copy_path, force: true),
                 "fs/* filesystem"
               ) do
          decoded = Base.decode64!(read_back)
          copied = Base.decode64!(copied_back)

          IO.puts("""
          App-server filesystem demo completed.
            root: #{root}
            file: #{file_path}
            copy: #{copy_path}
          """)

          IO.puts("Decoded file contents:")
          IO.puts(decoded)

          IO.puts("Directory entries:")

          entries
          |> Enum.sort_by(&Map.get(&1, "fileName", ""))
          |> Enum.each(fn entry ->
            IO.puts(
              "  - #{entry["fileName"]} (dir=#{inspect(entry["isDirectory"])}, file=#{inspect(entry["isFile"])})"
            )
          end)

          IO.puts("""
          Metadata:
            isDirectory: #{inspect(metadata["isDirectory"])}
            isFile: #{inspect(metadata["isFile"])}
            createdAtMs: #{inspect(metadata["createdAtMs"])}
            modifiedAtMs: #{inspect(metadata["modifiedAtMs"])}
            copied_contents_match?: #{decoded == copied}
          """)

          :ok
        end
      after
        _ = Codex.AppServer.fs_remove(conn, root, recursive: true, force: true)
        :ok = Codex.AppServer.disconnect(conn)
      end
    end
  end

  defp request_or_skip({:ok, result}, _feature), do: {:ok, result}

  defp request_or_skip({:error, %{"code" => code, "message" => message}}, feature)
       when code in [-32_601, -32_600, -32601, -32600] do
    {:skip, "#{feature} APIs are not supported by this `codex app-server` build: #{message}"}
  end

  defp request_or_skip({:error, reason}, _feature), do: {:error, reason}
end

CodexExamples.LiveAppServerFilesystem.main(System.argv())
