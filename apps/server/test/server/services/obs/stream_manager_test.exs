defmodule Server.Services.OBS.StreamManagerTest do
  @moduledoc """
  Unit tests for the OBS StreamManager GenServer.

  Tests stream and recording state management including:
  - GenServer initialization
  - Streaming state changes and broadcasts
  - Recording state changes and broadcasts
  - Recording pause state tracking
  - Virtual camera state tracking
  - Replay buffer state tracking
  - PubSub event handling and broadcasting
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

      # Verify state initialization
      state = StreamManager.get_state(pid)

      assert %StreamManager{
               session_id: ^session_id,
               streaming_active: false,
               streaming_timecode: "00:00:00",
               streaming_duration: 0,
               streaming_congestion: 0,
               streaming_bytes: 0,
               streaming_skipped_frames: 0,
               streaming_total_frames: 0,
               recording_active: false,
               recording_paused: false,
               recording_timecode: "00:00:00",
               recording_duration: 0,
               recording_bytes: 0,
               virtual_cam_active: false,
               replay_buffer_active: false
             } = state

      # Clean up
      GenServer.stop(pid)
    end

    test "requires session_id in options" do
      Process.flag(:trap_exit, true)
      opts = [name: :test_no_session]

      assert {:error, _} = StreamManager.start_link(opts)
    end

    test "subscribes to PubSub topic on init" do
      session_id = test_session_id()
      opts = [session_id: session_id, name: :"stream_pubsub_#{session_id}"]
      {:ok, pid} = StreamManager.start_link(opts)

      # Send test event to verify subscription
      topic = "obs_events:#{session_id}"
      event = %{eventType: "StreamStateChanged", eventData: %{outputActive: true}}
      Phoenix.PubSub.broadcast(Server.PubSub, topic, {:obs_event, event})

      Process.sleep(10)

      # State should have been updated
      state = StreamManager.get_state(pid)
      assert state.streaming_active == true

      GenServer.stop(pid)
    end
  end

  describe "get_state/1" do
    setup do
      session_id = test_session_id()
      opts = [session_id: session_id, name: :"stream_state_#{:rand.uniform(10000)}"]
      {:ok, pid} = start_supervised({StreamManager, opts})
      {:ok, pid: pid, session_id: session_id}
    end

    test "returns current state", %{pid: pid, session_id: session_id} do
      state = StreamManager.get_state(pid)

      assert %StreamManager{
               session_id: ^session_id,
               streaming_active: false,
               recording_active: false
             } = state
    end
  end

  describe "handle_info - StreamStateChanged" do
    setup do
      session_id = test_session_id()
      opts = [session_id: session_id, name: :"stream_change_#{:rand.uniform(10000)}"]
      {:ok, pid} = start_supervised({StreamManager, opts})

      # Subscribe to broadcast topic
      Phoenix.PubSub.subscribe(Server.PubSub, "obs:events")

      {:ok, pid: pid, session_id: session_id}
    end

    test "updates streaming state to active and broadcasts event", %{pid: pid, session_id: session_id} do
      event = %{
        eventType: "StreamStateChanged",
        eventData: %{outputActive: true}
      }

      send(pid, {:obs_event, event})

      # Should receive broadcast
      assert_receive {:stream_started,
                      %{
                        session_id: ^session_id,
                        active: true
                      }},
                     100

      # Check state was updated
      state = StreamManager.get_state(pid)
      assert state.streaming_active == true
    end

    test "updates streaming state to inactive and broadcasts event", %{pid: pid, session_id: session_id} do
      # First set to active
      send(
        pid,
        {:obs_event,
         %{
           eventType: "StreamStateChanged",
           eventData: %{outputActive: true}
         }}
      )

      Process.sleep(10)

      # Then set to inactive
      event = %{
        eventType: "StreamStateChanged",
        eventData: %{outputActive: false}
      }

      send(pid, {:obs_event, event})

      # Should receive broadcast
      assert_receive {:stream_stopped,
                      %{
                        session_id: ^session_id,
                        active: false
                      }},
                     100

      # Check state was updated
      state = StreamManager.get_state(pid)
      assert state.streaming_active == false
    end
  end

  describe "handle_info - RecordStateChanged" do
    setup do
      session_id = test_session_id()
      opts = [session_id: session_id, name: :"record_change_#{:rand.uniform(10000)}"]
      {:ok, pid} = start_supervised({StreamManager, opts})

      # Subscribe to broadcast topic
      Phoenix.PubSub.subscribe(Server.PubSub, "obs:events")

      {:ok, pid: pid, session_id: session_id}
    end

    test "updates recording state to active and broadcasts event", %{pid: pid, session_id: session_id} do
      event = %{
        eventType: "RecordStateChanged",
        eventData: %{outputActive: true}
      }

      send(pid, {:obs_event, event})

      # Should receive broadcast
      assert_receive {:record_started,
                      %{
                        session_id: ^session_id,
                        active: true
                      }},
                     100

      # Check state was updated
      state = StreamManager.get_state(pid)
      assert state.recording_active == true
    end

    test "updates recording state to inactive and broadcasts event", %{pid: pid, session_id: session_id} do
      # First set to active
      send(
        pid,
        {:obs_event,
         %{
           eventType: "RecordStateChanged",
           eventData: %{outputActive: true}
         }}
      )

      Process.sleep(10)

      # Then set to inactive
      event = %{
        eventType: "RecordStateChanged",
        eventData: %{outputActive: false}
      }

      send(pid, {:obs_event, event})

      # Should receive broadcast
      assert_receive {:record_stopped,
                      %{
                        session_id: ^session_id,
                        active: false
                      }},
                     100

      # Check state was updated
      state = StreamManager.get_state(pid)
      assert state.recording_active == false
    end
  end

  describe "handle_info - RecordPauseStateChanged" do
    setup do
      session_id = test_session_id()
      opts = [session_id: session_id, name: :"record_pause_#{:rand.uniform(10000)}"]
      {:ok, pid} = start_supervised({StreamManager, opts})
      {:ok, pid: pid, session_id: session_id}
    end

    test "updates recording pause state", %{pid: pid} do
      # Pause recording
      event = %{
        eventType: "RecordPauseStateChanged",
        eventData: %{outputPaused: true}
      }

      send(pid, {:obs_event, event})
      Process.sleep(10)

      state = StreamManager.get_state(pid)
      assert state.recording_paused == true

      # Resume recording
      event2 = %{
        eventType: "RecordPauseStateChanged",
        eventData: %{outputPaused: false}
      }

      send(pid, {:obs_event, event2})
      Process.sleep(10)

      state2 = StreamManager.get_state(pid)
      assert state2.recording_paused == false
    end
  end

  describe "handle_info - VirtualCamStateChanged" do
    setup do
      session_id = test_session_id()
      opts = [session_id: session_id, name: :"vcam_#{:rand.uniform(10000)}"]
      {:ok, pid} = start_supervised({StreamManager, opts})
      {:ok, pid: pid, session_id: session_id}
    end

    test "updates virtual camera state", %{pid: pid} do
      # Enable virtual camera
      event = %{
        eventType: "VirtualCamStateChanged",
        eventData: %{outputActive: true}
      }

      send(pid, {:obs_event, event})
      Process.sleep(10)

      state = StreamManager.get_state(pid)
      assert state.virtual_cam_active == true

      # Disable virtual camera
      event2 = %{
        eventType: "VirtualCamStateChanged",
        eventData: %{outputActive: false}
      }

      send(pid, {:obs_event, event2})
      Process.sleep(10)

      state2 = StreamManager.get_state(pid)
      assert state2.virtual_cam_active == false
    end
  end

  describe "handle_info - ReplayBufferStateChanged" do
    setup do
      session_id = test_session_id()
      opts = [session_id: session_id, name: :"replay_#{:rand.uniform(10000)}"]
      {:ok, pid} = start_supervised({StreamManager, opts})
      {:ok, pid: pid, session_id: session_id}
    end

    test "updates replay buffer state", %{pid: pid} do
      # Enable replay buffer
      event = %{
        eventType: "ReplayBufferStateChanged",
        eventData: %{outputActive: true}
      }

      send(pid, {:obs_event, event})
      Process.sleep(10)

      state = StreamManager.get_state(pid)
      assert state.replay_buffer_active == true

      # Disable replay buffer
      event2 = %{
        eventType: "ReplayBufferStateChanged",
        eventData: %{outputActive: false}
      }

      send(pid, {:obs_event, event2})
      Process.sleep(10)

      state2 = StreamManager.get_state(pid)
      assert state2.replay_buffer_active == false
    end
  end

  describe "handle_info - unknown events" do
    setup do
      session_id = test_session_id()
      opts = [session_id: session_id, name: :"stream_unknown_#{:rand.uniform(10000)}"]
      {:ok, pid} = start_supervised({StreamManager, opts})
      {:ok, pid: pid, session_id: session_id}
    end

    test "ignores unknown event types", %{pid: pid} do
      initial_state = StreamManager.get_state(pid)

      event = %{
        eventType: "UnknownEventType",
        eventData: %{some: "data"}
      }

      send(pid, {:obs_event, event})
      Process.sleep(10)

      # State should be unchanged
      final_state = StreamManager.get_state(pid)
      assert initial_state == final_state
    end
  end

  describe "comprehensive stream management flow" do
    setup do
      session_id = test_session_id()
      opts = [session_id: session_id, name: :"stream_flow_#{:rand.uniform(10000)}"]
      {:ok, pid} = start_supervised({StreamManager, opts})

      # Subscribe to broadcasts
      Phoenix.PubSub.subscribe(Server.PubSub, "obs:events")

      {:ok, pid: pid, session_id: session_id}
    end

    test "handles complete streaming workflow", %{pid: pid, session_id: session_id} do
      # 1. Start streaming
      send(
        pid,
        {:obs_event,
         %{
           eventType: "StreamStateChanged",
           eventData: %{outputActive: true}
         }}
      )

      # 2. Start recording
      send(
        pid,
        {:obs_event,
         %{
           eventType: "RecordStateChanged",
           eventData: %{outputActive: true}
         }}
      )

      # 3. Enable virtual camera
      send(
        pid,
        {:obs_event,
         %{
           eventType: "VirtualCamStateChanged",
           eventData: %{outputActive: true}
         }}
      )

      # 4. Pause recording
      send(
        pid,
        {:obs_event,
         %{
           eventType: "RecordPauseStateChanged",
           eventData: %{outputPaused: true}
         }}
      )

      # Wait for all events to process
      Process.sleep(20)

      # Verify final state
      state = StreamManager.get_state(pid)
      assert state.streaming_active == true
      assert state.recording_active == true
      assert state.recording_paused == true
      assert state.virtual_cam_active == true

      # Verify broadcasts were received
      assert_received {:stream_started,
                       %{
                         session_id: ^session_id,
                         active: true
                       }}

      assert_received {:record_started,
                       %{
                         session_id: ^session_id,
                         active: true
                       }}

      # 5. Stop everything
      send(
        pid,
        {:obs_event,
         %{
           eventType: "StreamStateChanged",
           eventData: %{outputActive: false}
         }}
      )

      send(
        pid,
        {:obs_event,
         %{
           eventType: "RecordStateChanged",
           eventData: %{outputActive: false}
         }}
      )

      Process.sleep(20)

      # Verify stopped broadcasts
      assert_received {:stream_stopped,
                       %{
                         session_id: ^session_id,
                         active: false
                       }}

      assert_received {:record_stopped,
                       %{
                         session_id: ^session_id,
                         active: false
                       }}
    end
  end

  describe "concurrent state updates" do
    setup do
      session_id = test_session_id()
      opts = [session_id: session_id, name: :"stream_concurrent_#{:rand.uniform(10000)}"]
      {:ok, pid} = start_supervised({StreamManager, opts})
      {:ok, pid: pid, session_id: session_id}
    end

    test "handles rapid state changes without data loss", %{pid: pid} do
      # Send many state changes rapidly
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

      # Send all events without delay
      Enum.each(events, &send(pid, {:obs_event, &1}))

      Process.sleep(50)

      # Final state should reflect last value for each field
      state = StreamManager.get_state(pid)
      assert state.streaming_active == false
      assert state.recording_active == true
      assert state.recording_paused == false
      assert state.virtual_cam_active == false
      assert state.replay_buffer_active == true
    end
  end
end
