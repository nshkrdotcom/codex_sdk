defmodule Codex.IO.Transport.ErlexecTest do
  use ExUnit.Case, async: true

  alias Codex.IO.Transport.Erlexec, as: ErlexecTransport

  defp create_test_script(body) do
    dir = Path.join(System.tmp_dir!(), "erlexec_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    path = Path.join(dir, "test.sh")

    File.write!(path, """
    #!/usr/bin/env bash
    set -euo pipefail
    #{body}
    """)

    File.chmod!(path, 0o755)
    on_exit(fn -> File.rm_rf!(dir) end)
    path
  end

  describe "tagged subscriber dispatch" do
    test "streams stdout lines to tagged subscribers" do
      ref = make_ref()
      script = create_test_script("echo hello; echo world")

      {:ok, _transport} =
        ErlexecTransport.start_link(
          command: script,
          args: [],
          subscriber: {self(), ref}
        )

      assert_receive {:codex_io_transport, ^ref, {:message, "hello"}}, 2_000
      assert_receive {:codex_io_transport, ^ref, {:message, "world"}}, 2_000
      assert_receive {:codex_io_transport, ^ref, {:exit, _}}, 2_000
    end
  end

  describe "legacy subscriber dispatch" do
    test "streams stdout lines to legacy subscribers" do
      script = create_test_script("echo hello; echo world")

      {:ok, _transport} =
        ErlexecTransport.start_link(
          command: script,
          args: [],
          subscriber: {self(), :legacy}
        )

      assert_receive {:transport_message, "hello"}, 2_000
      assert_receive {:transport_message, "world"}, 2_000
      assert_receive {:transport_exit, _}, 2_000
    end
  end

  describe "error handling" do
    test "start wraps init failures as transport errors" do
      echo = System.find_executable("echo") || "/bin/echo"

      assert {:error, {:transport, :invalid_subscriber}} =
               ErlexecTransport.start(command: echo, args: ["ok"], subscriber: :invalid)
    end
  end

  describe "buffer management" do
    test "flushes partial line on process exit" do
      ref = make_ref()
      script = create_test_script("printf 'no-newline'")

      {:ok, _transport} =
        ErlexecTransport.start_link(
          command: script,
          args: [],
          subscriber: {self(), ref}
        )

      assert_receive {:codex_io_transport, ^ref, {:message, "no-newline"}}, 2_000
      assert_receive {:codex_io_transport, ^ref, {:exit, _}}, 2_000
    end

    test "emits buffer overflow and resumes at next complete line" do
      ref = make_ref()
      script = create_test_script(~s|python3 -c "print('x' * 2000000); print('after')"|)

      {:ok, _transport} =
        ErlexecTransport.start_link(
          command: script,
          args: [],
          subscriber: {self(), ref},
          max_buffer_size: 1024
        )

      assert_receive {:codex_io_transport, ^ref, {:error, _overflow}}, 5_000
      assert_receive {:codex_io_transport, ^ref, {:message, "after"}}, 5_000
    end

    test "handles UTF-8 codepoint split across stdout chunks" do
      ref = make_ref()
      script = create_test_script("sleep 5")

      {:ok, transport} =
        ErlexecTransport.start_link(
          command: script,
          args: [],
          subscriber: {self(), ref}
        )

      try do
        state = :sys.get_state(transport)
        {_exec_pid, os_pid} = state.subprocess

        line = "hello — world\n"
        {idx, _len} = :binary.match(line, <<226, 128, 148>>)
        chunk1 = :binary.part(line, 0, idx + 1)
        chunk2 = :binary.part(line, idx + 1, byte_size(line) - idx - 1)

        send(transport, {:stdout, os_pid, chunk1})
        send(transport, {:stdout, os_pid, chunk2})

        assert_receive {:codex_io_transport, ^ref, {:message, "hello — world"}}, 2_000
      after
        _ = ErlexecTransport.force_close(transport)
      end
    end
  end

  describe "stderr" do
    test "captures stderr and makes it available via stderr/1" do
      ref = make_ref()
      script = create_test_script("echo err >&2; sleep 0.2; echo out")

      {:ok, transport} =
        ErlexecTransport.start_link(
          command: script,
          args: [],
          subscriber: {self(), ref}
        )

      Process.sleep(50)
      assert ErlexecTransport.stderr(transport) =~ "err"
      assert_receive {:codex_io_transport, ^ref, {:message, "out"}}, 2_000
      assert_receive {:codex_io_transport, ^ref, {:exit, _}}, 2_000
    end

    test "caps stderr buffer to configured tail size" do
      ref = make_ref()

      script =
        create_test_script(
          ~s|python3 -c "import sys; sys.stderr.write('x' * 1000000)"; echo done|
        )

      {:ok, transport} =
        ErlexecTransport.start_link(
          command: script,
          args: [],
          subscriber: {self(), ref},
          max_stderr_buffer_size: 256
        )

      assert_receive {:codex_io_transport, ^ref, {:exit, _}}, 5_000
      stderr = ErlexecTransport.stderr(transport)
      assert byte_size(stderr) <= 256
    end
  end

  describe "end_input" do
    test "supports end_input/1 for EOF" do
      ref = make_ref()
      script = create_test_script("while read -r line; do echo \"got: $line\"; done; echo done")

      {:ok, transport} =
        ErlexecTransport.start_link(
          command: script,
          args: [],
          subscriber: {self(), ref}
        )

      :ok = ErlexecTransport.send(transport, "hello\n")
      assert_receive {:codex_io_transport, ^ref, {:message, "got: hello"}}, 2_000

      :ok = ErlexecTransport.end_input(transport)
      assert_receive {:codex_io_transport, ^ref, {:message, "done"}}, 2_000
      assert_receive {:codex_io_transport, ^ref, {:exit, _}}, 2_000
    end
  end

  describe "subscriber lifecycle" do
    test "stops transport when last subscriber goes down" do
      ref = make_ref()
      script = create_test_script("while read -r line; do echo $line; done")

      subscriber =
        spawn(fn ->
          receive do
            :stop -> :ok
          end
        end)

      {:ok, transport} =
        ErlexecTransport.start_link(
          command: script,
          args: [],
          subscriber: {subscriber, ref}
        )

      transport_monitor = Process.monitor(transport)
      send(subscriber, :stop)

      assert_receive {:DOWN, ^transport_monitor, :process, ^transport, _}, 5_000
    end
  end

  describe "close/force_close" do
    test "returns typed not_connected errors after transport exits" do
      ref = make_ref()
      script = create_test_script("echo hi")

      {:ok, transport} =
        ErlexecTransport.start_link(
          command: script,
          args: [],
          subscriber: {self(), ref}
        )

      assert_receive {:codex_io_transport, ^ref, {:exit, _}}, 2_000
      Process.sleep(100)
      assert {:error, {:transport, :not_connected}} = ErlexecTransport.send(transport, "data")
    end

    test "force_close returns :ok" do
      ref = make_ref()
      script = create_test_script("while read -r line; do echo $line; done")

      {:ok, transport} =
        ErlexecTransport.start_link(
          command: script,
          args: [],
          subscriber: {self(), ref}
        )

      assert :ok = ErlexecTransport.force_close(transport)
    end
  end

  describe "headless timeout" do
    test "headless transports auto-stop after idle timeout" do
      script = create_test_script("sleep 60")

      {:ok, transport} =
        ErlexecTransport.start_link(
          command: script,
          args: [],
          headless_timeout_ms: 100
        )

      transport_monitor = Process.monitor(transport)
      assert_receive {:DOWN, ^transport_monitor, :process, ^transport, _}, 2_000
    end
  end
end
