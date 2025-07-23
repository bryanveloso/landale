defmodule Server.Services.OBS.EventHandlerTest do
  @moduledoc """
  Unit tests for the OBS EventHandler GenServer.

  Tests event processing and routing including:
  - GenServer initialization with session ID
  - PubSub subscription on init
  - Event message handling and routing
  - Scene change event processing
  - Stream state event processing
  - Record state event processing
  - Generic event handling
  """
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog

  alias Server.Services.OBS.EventHandler

  @test_session_id "test_event_handler_#{:rand.uniform(10000)}"

  setup do
    # Start PubSub if not already started
    case start_supervised({Phoenix.PubSub, name: Server.PubSub}) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end
  end

  describe "start_link/1" do
    test "starts GenServer with session_id" do
      opts = [session_id: @test_session_id, name: :"test_event_handler_#{@test_session_id}"]

      assert {:ok, pid} = EventHandler.start_link(opts)
      assert Process.alive?(pid)

      # Verify state was initialized correctly
      state = :sys.get_state(pid)
      assert %EventHandler{session_id: @test_session_id} = state
    end

    test "requires session_id in options" do
      opts = [name: :test_no_session]

      assert_raise KeyError, ~r/key :session_id not found/, fn ->
        EventHandler.start_link(opts)
      end
    end

    test "subscribes to PubSub topic on init" do
      topic = "obs_events:#{@test_session_id}"
      opts = [session_id: @test_session_id, name: :"test_pubsub_#{@test_session_id}"]

      # Start handler
      {:ok, pid} = EventHandler.start_link(opts)

      # Send a test message to verify subscription
      Phoenix.PubSub.broadcast(Server.PubSub, topic, {:obs_event, %{eventType: "TestEvent"}})

      # Give it time to process
      Process.sleep(10)

      # Handler should still be alive (didn't crash on message)
      assert Process.alive?(pid)
    end
  end

  describe "handle_info/2 - OBS events" do
    setup do
      opts = [session_id: @test_session_id, name: :"test_handler_#{:rand.uniform(10000)}"]
      {:ok, pid} = start_supervised({EventHandler, opts})
      {:ok, pid: pid}
    end

    test "logs debug message for all events", %{pid: pid} do
      event = %{
        eventType: "SomeEvent",
        eventData: %{data: "test"}
      }

      log =
        capture_log([level: :debug], fn ->
          send(pid, {:obs_event, event})
          Process.sleep(10)
        end)

      assert log =~ "OBS event received"
      assert log =~ "event_type: SomeEvent"
    end

    test "handles CurrentProgramSceneChanged event", %{pid: pid} do
      event = %{
        eventType: "CurrentProgramSceneChanged",
        eventData: %{sceneName: "New Scene"}
      }

      log =
        capture_log([level: :debug], fn ->
          send(pid, {:obs_event, event})
          Process.sleep(10)
        end)

      assert log =~ "Scene changed to: New Scene"
      assert log =~ "session_id: #{@test_session_id}"
    end

    test "handles StreamStateChanged event", %{pid: pid} do
      event = %{
        eventType: "StreamStateChanged",
        eventData: %{
          outputActive: true,
          outputState: "OBS_WEBSOCKET_OUTPUT_STARTED"
        }
      }

      log =
        capture_log([level: :debug], fn ->
          send(pid, {:obs_event, event})
          Process.sleep(10)
        end)

      assert log =~ "Stream state changed"
      assert log =~ "active: true"
      assert log =~ "state: OBS_WEBSOCKET_OUTPUT_STARTED"
    end

    test "handles RecordStateChanged event", %{pid: pid} do
      event = %{
        eventType: "RecordStateChanged",
        eventData: %{
          outputActive: false,
          outputState: "OBS_WEBSOCKET_OUTPUT_STOPPED"
        }
      }

      log =
        capture_log([level: :debug], fn ->
          send(pid, {:obs_event, event})
          Process.sleep(10)
        end)

      assert log =~ "Record state changed"
      assert log =~ "active: false"
      assert log =~ "state: OBS_WEBSOCKET_OUTPUT_STOPPED"
    end

    test "handles unknown events gracefully", %{pid: pid} do
      event = %{
        eventType: "UnknownEventType",
        eventData: %{random: "data"}
      }

      log =
        capture_log([level: :debug], fn ->
          send(pid, {:obs_event, event})
          Process.sleep(10)
        end)

      assert log =~ "Unhandled OBS event"
      assert log =~ "event_type: UnknownEventType"

      # Should not crash
      assert Process.alive?(pid)
    end

    test "handles events with missing data gracefully", %{pid: pid} do
      # Event without eventData
      event = %{eventType: "StreamStateChanged"}

      capture_log([level: :debug], fn ->
        send(pid, {:obs_event, event})
        Process.sleep(10)
      end)

      # Should not crash
      assert Process.alive?(pid)
    end

    test "processes multiple events in sequence", %{pid: pid} do
      events = [
        %{eventType: "CurrentProgramSceneChanged", eventData: %{sceneName: "Scene 1"}},
        %{eventType: "StreamStateChanged", eventData: %{outputActive: true, outputState: "STARTED"}},
        %{eventType: "UnknownEvent", eventData: %{}},
        %{eventType: "RecordStateChanged", eventData: %{outputActive: true, outputState: "STARTED"}},
        %{eventType: "CurrentProgramSceneChanged", eventData: %{sceneName: "Scene 2"}}
      ]

      log =
        capture_log([level: :debug], fn ->
          Enum.each(events, &send(pid, {:obs_event, &1}))
          Process.sleep(50)
        end)

      # Verify all events were processed
      assert log =~ "Scene changed to: Scene 1"
      assert log =~ "Stream state changed"
      assert log =~ "Unhandled OBS event"
      assert log =~ "Record state changed"
      assert log =~ "Scene changed to: Scene 2"

      # Should still be alive after all events
      assert Process.alive?(pid)
    end
  end

  describe "concurrent event handling" do
    setup do
      opts = [session_id: @test_session_id, name: :"test_concurrent_#{:rand.uniform(10000)}"]
      {:ok, pid} = start_supervised({EventHandler, opts})
      {:ok, pid: pid}
    end

    test "handles concurrent events from multiple sources", %{pid: pid} do
      # Spawn multiple processes to send events concurrently
      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            event = %{
              eventType: "CurrentProgramSceneChanged",
              eventData: %{sceneName: "Scene #{i}"}
            }

            send(pid, {:obs_event, event})
          end)
        end

      # Wait for all tasks
      Task.await_many(tasks)
      Process.sleep(50)

      # Handler should still be alive
      assert Process.alive?(pid)
    end
  end

  describe "state management" do
    test "maintains session_id throughout lifecycle" do
      session_id = "persistent_session_#{:rand.uniform(10000)}"
      opts = [session_id: session_id, name: :"test_state_#{session_id}"]

      {:ok, pid} = EventHandler.start_link(opts)

      # Check initial state
      assert %EventHandler{session_id: ^session_id} = :sys.get_state(pid)

      # Send some events
      for i <- 1..5 do
        event = %{eventType: "TestEvent", eventData: %{index: i}}
        send(pid, {:obs_event, event})
      end

      Process.sleep(20)

      # State should still have the same session_id
      assert %EventHandler{session_id: ^session_id} = :sys.get_state(pid)
    end
  end

  describe "error scenarios" do
    setup do
      opts = [session_id: @test_session_id, name: :"test_error_#{:rand.uniform(10000)}"]
      {:ok, pid} = start_supervised({EventHandler, opts})
      {:ok, pid: pid}
    end

    test "handles malformed events", %{pid: pid} do
      malformed_events = [
        nil,
        "not a map",
        # Missing eventType
        %{},
        %{eventType: nil},
        # Non-string type
        %{eventType: 123}
      ]

      for event <- malformed_events do
        send(pid, {:obs_event, event})
      end

      Process.sleep(20)

      # Should not crash
      assert Process.alive?(pid)
    end

    test "handles non-obs_event messages", %{pid: pid} do
      # Send various non-event messages
      send(pid, :unexpected_atom)
      send(pid, {:other_tuple, "data"})
      send(pid, "string message")

      Process.sleep(20)

      # Should ignore and not crash
      assert Process.alive?(pid)
    end
  end
end
