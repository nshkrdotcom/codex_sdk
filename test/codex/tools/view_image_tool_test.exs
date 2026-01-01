defmodule Codex.Tools.ViewImageToolTest do
  use ExUnit.Case, async: false

  alias Codex.Options
  alias Codex.Thread
  alias Codex.Thread.Options, as: ThreadOptions
  alias Codex.ToolOutput
  alias Codex.Tools
  alias Codex.Tools.ViewImageTool

  @png_base64 "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR4nGNgYAAAAAMAASsJTYQAAAAASUVORK5CYII="

  setup do
    Tools.reset!()
    Tools.reset_metrics()

    on_exit(fn ->
      Tools.reset!()
      Tools.reset_metrics()
    end)

    :ok
  end

  describe "metadata/0" do
    test "returns valid tool metadata" do
      meta = ViewImageTool.metadata()
      assert meta.name == "view_image"
      assert meta.schema["required"] == ["path"]
      assert meta.schema["properties"]["path"]["type"] == "string"
    end
  end

  describe "invoke/2" do
    test "returns input_image output" do
      tmp_dir = Path.join(System.tmp_dir!(), "view_image_tool_#{:rand.uniform(1_000_000)}")
      File.mkdir_p!(tmp_dir)
      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      file_path = Path.join(tmp_dir, "image.png")
      File.write!(file_path, Base.decode64!(@png_base64))

      assert {:ok, [text, image]} = ViewImageTool.invoke(%{"path" => file_path}, %{})
      assert %ToolOutput.Text{text: "attached local image path"} = text
      assert %ToolOutput.Image{url: url} = image
      assert String.starts_with?(url, "data:image/png;base64,")
    end
  end

  describe "enablement gating" do
    test "disabled when view_image_tool_enabled is false" do
      {:ok, _} = Tools.register(ViewImageTool)
      {:ok, thread_opts} = ThreadOptions.new(%{view_image_tool_enabled: false})
      {:ok, codex_opts} = Options.new(%{api_key: "test"})
      thread = Thread.build(codex_opts, thread_opts)

      assert {:error, {:tool_disabled, "view_image"}} =
               Tools.invoke("view_image", %{"path" => "image.png"}, %{thread: thread})
    end

    test "enabled when config features.view_image_tool is true" do
      {:ok, _} = Tools.register(ViewImageTool)

      {:ok, thread_opts} =
        ThreadOptions.new(%{config: %{"features" => %{"view_image_tool" => true}}})

      {:ok, codex_opts} = Options.new(%{api_key: "test"})
      thread = Thread.build(codex_opts, thread_opts)

      tmp_dir = Path.join(System.tmp_dir!(), "view_image_tool_#{:rand.uniform(1_000_000)}")
      File.mkdir_p!(tmp_dir)
      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      file_path = Path.join(tmp_dir, "image.png")
      File.write!(file_path, Base.decode64!(@png_base64))

      assert {:ok, [_text, _image]} =
               Tools.invoke("view_image", %{"path" => file_path}, %{thread: thread})
    end
  end
end
