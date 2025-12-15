defmodule Codex.ThreadTransportTest do
  use ExUnit.Case, async: true

  alias Codex.{Options, Thread}
  alias Codex.Thread.Options, as: ThreadOptions

  describe "Thread.Options transport" do
    test "defaults to exec transport" do
      assert {:ok, %ThreadOptions{transport: :exec}} = ThreadOptions.new(%{})
    end

    test "accepts explicit exec transport" do
      assert {:ok, %ThreadOptions{transport: :exec}} = ThreadOptions.new(%{transport: :exec})
    end

    test "accepts app-server transport tuple" do
      assert {:ok, %ThreadOptions{transport: {:app_server, pid}}} =
               ThreadOptions.new(%{transport: {:app_server, self()}})

      assert pid == self()
    end

    test "rejects unknown transport" do
      assert {:error, {:invalid_transport, :other}} = ThreadOptions.new(%{transport: :other})
    end
  end

  describe "Thread.build transport" do
    test "stores transport metadata on the thread struct" do
      {:ok, codex_opts} = Options.new(%{api_key: "test"})
      {:ok, thread_opts} = ThreadOptions.new(%{transport: {:app_server, self()}})

      thread = Thread.build(codex_opts, thread_opts)

      assert thread.transport == {:app_server, self()}
      assert is_reference(thread.transport_ref)
    end
  end
end
