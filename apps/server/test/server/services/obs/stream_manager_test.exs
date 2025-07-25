defmodule Server.Services.OBS.StreamManagerTest do
  @moduledoc """
  Behavior-driven tests for the OBS StreamManager GenServer.

  Tests focus on observable behavior through public APIs rather than
  internal message handling. Events are delivered through the proper
  PubSub channel as they would be in production.
  """
  use ExUnit.Case, async: true

  alias Server.Services.OBS.StreamManager

  def test_session_id, do: "test_stream_manager_#{:rand.uniform(100_000)}_#{System.unique_integer([:positive])}"

  setup do
    # Start PubSub if not already started
    case start_supervised({Phoenix.PubSub, name: Server.PubSub}) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end
  end

  describe "start_link/1 and initialization" do
    test "starts GenServer with session_id" do
      session_id = test_session_id()
      opts = [session_id: session_id, name: :"stream_manager_#{session_id}"]

      assert {:ok, pid} = StreamManager.start_link(opts)
      assert Process.alive?(pid)

      # Verify initial state through public API
      assert StreamManager.streaming?(pid) == false
      assert StreamManager.recording?(pid) == false
      assert StreamManager.recording_paused?(pid) == false
      assert StreamManager.virtual_cam_active?(pid) == false
      assert StreamManager.replay_buffer_active?(pid) == false

      # Clean up
      GenServer.stop(pid)
    end

    test "requires session_id in options" do
      Process.flag(:trap_exit, true)
      opts = [name: :test_no_session]

      assert {:error, _} = StreamManager.start_link(opts)
    end
  end

  describe "public API queries" do
    setup do
      session_id = test_session_id()
      opts = [session_id: session_id, name: :"stream_state_#{:rand.uniform(10000)}"]
      {:ok, pid} = start_supervised({StreamManager, opts})
      {:ok, pid: pid, session_id: session_id}
    end

    test "get_stream_info returns comprehensive state", %{pid: pid, session_id: session_id} do
      info = StreamManager.get_stream_info(pid)

      assert %{
               streaming: false,
               recording: false,
               recording_paused: false,
               virtual_cam: false,
               replay_buffer: false,
               session_id: ^session_id
             } = info
    end

    test "individual state queries work correctly", %{pid: pid} do
      assert StreamManager.streaming?(pid) == false
      assert StreamManager.recording?(pid) == false
      assert StreamManager.recording_paused?(pid) == false
      assert StreamManager.virtual_cam_active?(pid) == false
      assert StreamManager.replay_buffer_active?(pid) == false
    end
  end

  describe "streaming state changes" do
    setup do
      session_id = test_session_id()
      opts = [session_id: session_id, name: :"stream_change_#{:rand.uniform(10000)}"]
      {:ok, pid} = start_supervised({StreamManager, opts})

      # Subscribe to broadcast topic for verification
      Phoenix.PubSub.subscribe(Server.PubSub, "obs:events")

      {:ok, pid: pid, session_id: session_id}
    end

    test "updates streaming state when stream starts", %{pid: pid, session_id: session_id} do
      # Simulate OBS event through proper channel
      Phoenix.PubSub.broadcast(
        Server.PubSub,
        "obs_events:#{session_id}",
        {:obs_event,
         %{
           eventType: "StreamStateChanged",
           eventData: %{outputActive: true}
         }}
      )

      # Allow time for async processing
      Process.sleep(10)

      # Verify state through public API
      assert StreamManager.streaming?(pid) == true

      # Verify broadcast was sent
      assert_receive {:stream_started,
                      %{
                        session_id: ^session_id,
                        active: true
                      }},
                     100
    end

    test "updates streaming state when stream stops", %{pid: pid, session_id: session_id} do
      # Start stream first
      Phoenix.PubSub.broadcast(
        Server.PubSub,
        "obs_events:#{session_id}",
        {:obs_event,
         %{
           eventType: "StreamStateChanged",
           eventData: %{outputActive: true}
         }}
      )

      Process.sleep(10)
      assert StreamManager.streaming?(pid) == true

      # Stop stream
      Phoenix.PubSub.broadcast(
        Server.PubSub,
        "obs_events:#{session_id}",
        {:obs_event,
         %{
           eventType: "StreamStateChanged",
           eventData: %{outputActive: false}
         }}
      )

      Process.sleep(10)

      # Verify state change
      assert StreamManager.streaming?(pid) == false

      # Verify broadcast was sent
      assert_receive {:stream_stopped,
                      %{
                        session_id: ^session_id,
                        active: false
                      }},
                     100
    end
  end

  describe "recording state changes" do
    setup do
      session_id = test_session_id()
      opts = [session_id: session_id, name: :"record_change_#{:rand.uniform(10000)}"]
      {:ok, pid} = start_supervised({StreamManager, opts})

      # Subscribe to broadcast topic
      Phoenix.PubSub.subscribe(Server.PubSub, "obs:events")

      {:ok, pid: pid, session_id: session_id}
    end

    test "updates recording state when recording starts", %{pid: pid, session_id: session_id} do
      Phoenix.PubSub.broadcast(
        Server.PubSub,
        "obs_events:#{session_id}",
        {:obs_event,
         %{
           eventType: "RecordStateChanged",
           eventData: %{outputActive: true}
         }}
      )

      Process.sleep(10)

      assert StreamManager.recording?(pid) == true

      assert_receive {:record_started,
                      %{
                        session_id: ^session_id,
                        active: true
                      }},
                     100
    end

    test "updates recording state when recording stops", %{pid: pid, session_id: session_id} do
      # Start recording first
      Phoenix.PubSub.broadcast(
        Server.PubSub,
        "obs_events:#{session_id}",
        {:obs_event,
         %{
           eventType: "RecordStateChanged",
           eventData: %{outputActive: true}
         }}
      )

      Process.sleep(10)
      assert StreamManager.recording?(pid) == true

      # Stop recording
      Phoenix.PubSub.broadcast(
        Server.PubSub,
        "obs_events:#{session_id}",
        {:obs_event,
         %{
           eventType: "RecordStateChanged",
           eventData: %{outputActive: false}
         }}
      )

      Process.sleep(10)

      assert StreamManager.recording?(pid) == false

      assert_receive {:record_stopped,
                      %{
                        session_id: ^session_id,
                        active: false
                      }},
                     100
    end

    test "handles recording pause state", %{pid: pid, session_id: session_id} do
      # Pause recording
      Phoenix.PubSub.broadcast(
        Server.PubSub,
        "obs_events:#{session_id}",
        {:obs_event,
         %{
           eventType: "RecordPauseStateChanged",
           eventData: %{outputPaused: true}
         }}
      )

      Process.sleep(10)
      assert StreamManager.recording_paused?(pid) == true

      # Resume recording
      Phoenix.PubSub.broadcast(
        Server.PubSub,
        "obs_events:#{session_id}",
        {:obs_event,
         %{
           eventType: "RecordPauseStateChanged",
           eventData: %{outputPaused: false}
         }}
      )

      Process.sleep(10)
      assert StreamManager.recording_paused?(pid) == false
    end
  end

  describe "other output states" do
    setup do
      session_id = test_session_id()
      opts = [session_id: session_id, name: :"output_#{:rand.uniform(10000)}"]
      {:ok, pid} = start_supervised({StreamManager, opts})
      {:ok, pid: pid, session_id: session_id}
    end

    test "updates virtual camera state", %{pid: pid, session_id: session_id} do
      # Enable virtual camera
      Phoenix.PubSub.broadcast(
        Server.PubSub,
        "obs_events:#{session_id}",
        {:obs_event,
         %{
           eventType: "VirtualCamStateChanged",
           eventData: %{outputActive: true}
         }}
      )

      Process.sleep(10)
      assert StreamManager.virtual_cam_active?(pid) == true

      # Disable virtual camera
      Phoenix.PubSub.broadcast(
        Server.PubSub,
        "obs_events:#{session_id}",
        {:obs_event,
         %{
           eventType: "VirtualCamStateChanged",
           eventData: %{outputActive: false}
         }}
      )

      Process.sleep(10)
      assert StreamManager.virtual_cam_active?(pid) == false
    end

    test "updates replay buffer state", %{pid: pid, session_id: session_id} do
      # Enable replay buffer
      Phoenix.PubSub.broadcast(
        Server.PubSub,
        "obs_events:#{session_id}",
        {:obs_event,
         %{
           eventType: "ReplayBufferStateChanged",
           eventData: %{outputActive: true}
         }}
      )

      Process.sleep(10)
      assert StreamManager.replay_buffer_active?(pid) == true

      # Disable replay buffer
      Phoenix.PubSub.broadcast(
        Server.PubSub,
        "obs_events:#{session_id}",
        {:obs_event,
         %{
           eventType: "ReplayBufferStateChanged",
           eventData: %{outputActive: false}
         }}
      )

      Process.sleep(10)
      assert StreamManager.replay_buffer_active?(pid) == false
    end
  end

  describe "comprehensive workflow" do
    setup do
      session_id = test_session_id()
      opts = [session_id: session_id, name: :"stream_flow_#{:rand.uniform(10000)}"]
      {:ok, pid} = start_supervised({StreamManager, opts})

      # Subscribe to broadcasts
      Phoenix.PubSub.subscribe(Server.PubSub, "obs:events")

      {:ok, pid: pid, session_id: session_id}
    end

    test "handles complete streaming workflow", %{pid: pid, session_id: session_id} do
      # Start streaming
      Phoenix.PubSub.broadcast(
        Server.PubSub,
        "obs_events:#{session_id}",
        {:obs_event,
         %{
           eventType: "StreamStateChanged",
           eventData: %{outputActive: true}
         }}
      )

      # Start recording
      Phoenix.PubSub.broadcast(
        Server.PubSub,
        "obs_events:#{session_id}",
        {:obs_event,
         %{
           eventType: "RecordStateChanged",
           eventData: %{outputActive: true}
         }}
      )

      # Enable virtual camera
      Phoenix.PubSub.broadcast(
        Server.PubSub,
        "obs_events:#{session_id}",
        {:obs_event,
         %{
           eventType: "VirtualCamStateChanged",
           eventData: %{outputActive: true}
         }}
      )

      # Pause recording
      Phoenix.PubSub.broadcast(
        Server.PubSub,
        "obs_events:#{session_id}",
        {:obs_event,
         %{
           eventType: "RecordPauseStateChanged",
           eventData: %{outputPaused: true}
         }}
      )

      # Wait for all events to process
      Process.sleep(20)

      # Verify state through public API
      info = StreamManager.get_stream_info(pid)
      assert info.streaming == true
      assert info.recording == true
      assert info.recording_paused == true
      assert info.virtual_cam == true

      # Verify broadcasts were received
      assert_received {:stream_started, %{session_id: ^session_id, active: true}}
      assert_received {:record_started, %{session_id: ^session_id, active: true}}

      # Stop everything
      Phoenix.PubSub.broadcast(
        Server.PubSub,
        "obs_events:#{session_id}",
        {:obs_event,
         %{
           eventType: "StreamStateChanged",
           eventData: %{outputActive: false}
         }}
      )

      Phoenix.PubSub.broadcast(
        Server.PubSub,
        "obs_events:#{session_id}",
        {:obs_event,
         %{
           eventType: "RecordStateChanged",
           eventData: %{outputActive: false}
         }}
      )

      Process.sleep(20)

      # Verify final state
      assert StreamManager.streaming?(pid) == false
      assert StreamManager.recording?(pid) == false

      # Verify stop broadcasts
      assert_received {:stream_stopped, %{session_id: ^session_id, active: false}}
      assert_received {:record_stopped, %{session_id: ^session_id, active: false}}
    end
  end

  describe "concurrent state updates" do
    setup do
      session_id = test_session_id()
      opts = [session_id: session_id, name: :"stream_concurrent_#{:rand.uniform(10000)}"]
      {:ok, pid} = start_supervised({StreamManager, opts})
      {:ok, pid: pid, session_id: session_id}
    end

    test "handles rapid state changes correctly", %{pid: pid, session_id: session_id} do
      # Send many state changes rapidly through proper channel
      events = [
        %{eventType: "StreamStateChanged", eventData: %{outputActive: true}},
        %{eventType: "RecordStateChanged", eventData: %{outputActive: true}},
        %{eventType: "VirtualCamStateChanged", eventData: %{outputActive: true}},
        %{eventType: "ReplayBufferStateChanged", eventData: %{outputActive: true}},
        %{eventType: "RecordPauseStateChanged", eventData: %{outputPaused: true}},
        %{eventType: "StreamStateChanged", eventData: %{outputActive: false}},
        %{eventType: "RecordPauseStateChanged", eventData: %{outputPaused: false}},
        %{eventType: "VirtualCamStateChanged", eventData: %{outputActive: false}}
      ]

      # Broadcast all events without delay
      Enum.each(events, fn event ->
        Phoenix.PubSub.broadcast(
          Server.PubSub,
          "obs_events:#{session_id}",
          {:obs_event, event}
        )
      end)

      Process.sleep(50)

      # Final state should reflect last value for each field
      info = StreamManager.get_stream_info(pid)
      assert info.streaming == false
      assert info.recording == true
      assert info.recording_paused == false
      assert info.virtual_cam == false
      assert info.replay_buffer == true
    end
  end

  describe "resilience" do
    setup do
      session_id = test_session_id()
      opts = [session_id: session_id, name: :"stream_resilience_#{:rand.uniform(10000)}"]
      {:ok, pid} = start_supervised({StreamManager, opts})
      {:ok, pid: pid, session_id: session_id}
    end

    test "ignores unknown event types", %{pid: pid, session_id: session_id} do
      initial_info = StreamManager.get_stream_info(pid)

      # Send unknown event
      Phoenix.PubSub.broadcast(
        Server.PubSub,
        "obs_events:#{session_id}",
        {:obs_event,
         %{
           eventType: "UnknownEventType",
           eventData: %{some: "data"}
         }}
      )

      Process.sleep(10)

      # State should be unchanged
      final_info = StreamManager.get_stream_info(pid)
      assert initial_info == final_info
    end

    test "handles malformed events gracefully", %{pid: pid, session_id: session_id} do
      # Send events with missing data
      Phoenix.PubSub.broadcast(
        Server.PubSub,
        "obs_events:#{session_id}",
        {:obs_event,
         %{
           eventType: "StreamStateChanged",
           eventData: %{}
         }}
      )

      Process.sleep(10)

      # Should not crash, state should have reasonable default
      assert Process.alive?(pid)
    end
  end
end
