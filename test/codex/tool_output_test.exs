defmodule Codex.ToolOutputTest do
  use ExUnit.Case, async: false

  alias Codex.Files
  alias Codex.ToolOutput

  setup do
    Files.reset!()

    on_exit(fn -> Files.reset!() end)

    :ok
  end

  test "normalizes file outputs with ids, urls, and filenames" do
    output =
      ToolOutput.file(
        file_id: "file_123",
        url: "https://example.com/report.pdf",
        filename: "report.pdf",
        mime_type: "application/pdf"
      )

    assert %{
             "type" => "input_file",
             "file_data" => %{
               "file_id" => "file_123",
               "file_url" => "https://example.com/report.pdf",
               "filename" => "report.pdf",
               "mime_type" => "application/pdf"
             }
           } = ToolOutput.normalize(output)
  end

  test "converts staged attachments into input_file payloads" do
    attachment =
      "attachment.txt"
      |> tmp_file!("hello file")
      |> then(fn path ->
        {:ok, attachment} = Files.stage(path)
        attachment
      end)

    normalized = ToolOutput.normalize(attachment)
    id = attachment.id
    filename = attachment.name
    data = attachment.path |> File.read!() |> Base.encode64()

    assert normalized["type"] == "input_file"

    assert %{
             "file_id" => ^id,
             "filename" => ^filename,
             "data" => ^data
           } = normalized["file_data"]
  end

  test "flattens and deduplicates nested structured outputs" do
    outputs = [
      ToolOutput.file(file_id: "file_a"),
      [
        ToolOutput.file(file_id: "file_a"),
        ToolOutput.image(file_id: "img_1", detail: "low"),
        [ToolOutput.image(file_id: "img_1")]
      ]
    ]

    assert ToolOutput.normalize(outputs) == [
             %{"type" => "input_file", "file_data" => %{"file_id" => "file_a"}},
             %{
               "type" => "input_image",
               "image_url" => %{"file_id" => "img_1", "detail" => "low"}
             }
           ]
  end

  test "image/1 and file/1 reject unknown string keys without interning atoms" do
    image_key = fresh_missing_key("unknown_image")
    file_key = fresh_missing_key("unknown_file")

    assert_raise KeyError, fn ->
      ToolOutput.image(%{image_key => "https://example.com/image.png"})
    end

    assert_raise KeyError, fn ->
      ToolOutput.file(%{file_key => "file_123"})
    end

    refute atom_exists?(image_key)
    refute atom_exists?(file_key)
  end

  defp tmp_file!(name, contents) do
    dir = Path.join(System.tmp_dir!(), "codex_tool_output_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    path = Path.join(dir, name)
    File.write!(path, contents)
    path
  end

  defp unique_key(prefix) do
    suffix = :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
    "#{prefix}_#{suffix}"
  end

  defp fresh_missing_key(prefix) do
    key = unique_key(prefix)

    if atom_exists?(key) do
      fresh_missing_key(prefix)
    else
      key
    end
  end

  defp atom_exists?(key) do
    _ = String.to_existing_atom(key)
    true
  rescue
    ArgumentError -> false
  end
end
