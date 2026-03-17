defmodule Codex.Voice.Models.OpenAISTTTest do
  use ExUnit.Case, async: true
  use Codex.TestSupport.AuthEnv

  alias Codex.Voice.Config.STTSettings
  alias Codex.Voice.Input.StreamedAudioInput
  alias Codex.Voice.Models.OpenAISTT
  alias Codex.Voice.Models.OpenAISTTSession
  import Codex.Test.ModelFixtures

  describe "new/2" do
    test "creates with default model" do
      model = OpenAISTT.new()
      assert model.model == stt_model()
    end

    test "creates with custom model" do
      model = OpenAISTT.new("whisper-1")
      assert model.model == "whisper-1"
    end

    test "creates with custom options" do
      model = OpenAISTT.new("whisper-1", api_key: "sk-test", base_url: "https://custom.api.com")
      assert model.model == "whisper-1"
      assert model.api_key == "sk-test"
      assert model.base_url == "https://custom.api.com"
    end

    test "uses default base URL" do
      model = OpenAISTT.new()
      assert model.base_url == "https://api.openai.com/v1"
    end
  end

  describe "model_name/0" do
    test "returns default model name" do
      assert OpenAISTT.model_name() == stt_model()
    end
  end

  describe "struct" do
    test "has expected fields" do
      model = %OpenAISTT{}
      assert Map.has_key?(model, :model)
      assert Map.has_key?(model, :client)
      assert Map.has_key?(model, :api_key)
      assert Map.has_key?(model, :base_url)
    end
  end

  describe "OpenAISTTSession" do
    test "starts with required options" do
      input = StreamedAudioInput.new()
      settings = STTSettings.new()

      assert {:ok, pid} =
               OpenAISTTSession.start_link(
                 input: input,
                 settings: settings
               )

      assert is_pid(pid)
      OpenAISTTSession.close(pid)
    end

    test "starts with all options" do
      input = StreamedAudioInput.new()
      settings = STTSettings.new(language: "en", temperature: 0.0)

      assert {:ok, pid} =
               OpenAISTTSession.start_link(
                 input: input,
                 settings: settings,
                 model: "whisper-1",
                 api_key: "sk-test",
                 trace_include_sensitive_data: false,
                 trace_include_sensitive_audio_data: false
               )

      assert is_pid(pid)
      OpenAISTTSession.close(pid)
    end

    test "default_turn_detection returns semantic_vad" do
      assert OpenAISTTSession.default_turn_detection() == %{"type" => "semantic_vad"}
    end

    test "close/1 stops the session" do
      input = StreamedAudioInput.new()
      settings = STTSettings.new()

      {:ok, pid} =
        OpenAISTTSession.start_link(
          input: input,
          settings: settings
        )

      assert Process.alive?(pid)
      assert :ok = OpenAISTTSession.close(pid)
      refute Process.alive?(pid)
    end

    test "close/1 cleans up websocket, tasks, and waiters" do
      input = StreamedAudioInput.new()
      settings = STTSettings.new()

      {:ok, pid} =
        OpenAISTTSession.start_link(
          input: input,
          settings: settings
        )

      waiter =
        start_task(fn ->
          GenServer.call(pid, :get_transcript, :infinity)
        end)

      websocket =
        spawn(fn ->
          receive do
            :stop -> :ok
          end
        end)

      listener_task =
        start_task(fn ->
          receive do
            :stop -> :ok
          end
        end)

      stream_task =
        start_task(fn ->
          receive do
            :stop -> :ok
          end
        end)

      Process.sleep(25)

      :sys.replace_state(pid, fn state ->
        %{
          state
          | websocket: websocket,
            listener_task: listener_task,
            stream_task: stream_task
        }
      end)

      assert :ok = OpenAISTTSession.close(pid)
      assert Task.await(waiter, 1_000) == {:error, :closed}
      refute Process.alive?(websocket)
      refute Process.alive?(listener_task.pid)
      refute Process.alive?(stream_task.pid)
    end

    test "defaults api_key to Codex auth precedence" do
      System.put_env("CODEX_API_KEY", "sk-codex-priority")
      System.delete_env("OPENAI_API_KEY")

      input = StreamedAudioInput.new()
      settings = STTSettings.new()

      {:ok, pid} =
        OpenAISTTSession.start_link(
          input: input,
          settings: settings
        )

      assert :sys.get_state(pid).api_key == "sk-codex-priority"
      OpenAISTTSession.close(pid)
    end

    test "falls back to OPENAI_API_KEY when Codex key sources are absent", %{
      codex_home: codex_home
    } do
      refute File.exists?(Path.join(codex_home, "auth.json"))

      System.delete_env("CODEX_API_KEY")
      System.put_env("OPENAI_API_KEY", "sk-openai-env")

      input = StreamedAudioInput.new()
      settings = STTSettings.new()

      {:ok, pid} =
        OpenAISTTSession.start_link(
          input: input,
          settings: settings
        )

      assert :sys.get_state(pid).api_key == "sk-openai-env"
      OpenAISTTSession.close(pid)
    end

    test "removes dead transcript waiters on caller DOWN" do
      input = StreamedAudioInput.new()
      settings = STTSettings.new()

      {:ok, pid} =
        OpenAISTTSession.start_link(
          input: input,
          settings: settings
        )

      waiter =
        spawn(fn ->
          _ = GenServer.call(pid, :get_transcript, :infinity)
        end)

      wait_for_waiter_count(pid, 1)
      Process.exit(waiter, :kill)
      Process.sleep(50)

      assert waiter_count(pid) == 0
      OpenAISTTSession.close(pid)
    end

    test "transcribe_turns completes when streamed input is already closed" do
      input = StreamedAudioInput.new()
      StreamedAudioInput.close(input)
      settings = STTSettings.new()

      {:ok, pid} =
        OpenAISTTSession.start_link(
          input: input,
          settings: settings
        )

      task =
        Task.async(fn ->
          OpenAISTTSession.transcribe_turns(pid)
          |> Enum.to_list()
        end)

      assert Task.yield(task, 200) == {:ok, []}
      OpenAISTTSession.close(pid)
    end

    test "transcribe_turns uses the configured model and STT settings" do
      parent = self()
      input = StreamedAudioInput.new()
      StreamedAudioInput.add(input, <<0, 0, 1, 1>>)
      StreamedAudioInput.close(input)

      settings =
        STTSettings.new(
          language: "fr",
          prompt: "Bonjour",
          temperature: 0.25
        )

      model =
        OpenAISTT.new("whisper-1",
          api_key: "sk-stream",
          base_url: "https://stt.example.test/v1",
          client: fn url, opts ->
            send(parent, {:stt_request, url, opts})
            {:ok, %{status: 200, body: %{"text" => "salut"}}}
          end
        )

      {:ok, pid} =
        OpenAISTTSession.start_link(
          input: input,
          settings: settings,
          stt_model: model
        )

      assert ["salut"] =
               OpenAISTTSession.transcribe_turns(pid)
               |> Enum.to_list()

      assert_receive {:stt_request, "https://stt.example.test/v1/audio/transcriptions", opts}

      assert {"Authorization", "Bearer sk-stream"} in opts[:headers]
      assert {:model, "whisper-1"} in opts[:form_multipart]
      assert {:language, "fr"} in opts[:form_multipart]
      assert {:prompt, "Bonjour"} in opts[:form_multipart]
      assert {:temperature, "0.25"} in opts[:form_multipart]

      OpenAISTTSession.close(pid)
    end
  end

  describe "transcribe/5 (integration)" do
    @describetag :integration

    @tag :skip
    test "transcribes audio input" do
      # This test requires a real API key and would make actual API calls
      # Uncomment and set OPENAI_API_KEY to run
      #
      # model = OpenAISTT.new()
      # audio_data = File.read!("test/fixtures/sample.wav")
      # input = AudioInput.new(audio_data)
      # settings = STTSettings.new(language: "en")
      #
      # {:ok, text} = OpenAISTT.transcribe(model, input, settings, true, false)
      # assert is_binary(text)
    end
  end

  defp start_task(fun) when is_function(fun, 0) do
    case Process.whereis(Codex.TaskSupervisor) do
      nil ->
        {:ok, supervisor} = Task.Supervisor.start_link()
        Task.Supervisor.async_nolink(supervisor, fun)

      _pid ->
        Task.Supervisor.async_nolink(Codex.TaskSupervisor, fun)
    end
  end

  defp wait_for_waiter_count(pid, expected) do
    started = System.monotonic_time(:millisecond)
    do_wait_for_waiter_count(pid, expected, started)
  end

  defp do_wait_for_waiter_count(pid, expected, started) do
    if waiter_count(pid) == expected do
      :ok
    else
      if System.monotonic_time(:millisecond) - started > 500 do
        flunk("timed out waiting for waiter count #{expected}")
      else
        Process.sleep(10)
        do_wait_for_waiter_count(pid, expected, started)
      end
    end
  end

  defp waiter_count(pid) do
    state = :sys.get_state(pid)
    length(state.waiters)
  end
end
