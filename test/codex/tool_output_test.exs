defmodule Codex.ToolOutputTest do
  use ExUnit.Case, async: true

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

  defp tmp_file!(name, contents) do
    dir = Path.join(System.tmp_dir!(), "codex_tool_output_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    path = Path.join(dir, name)
    File.write!(path, contents)
    path
  end
end
