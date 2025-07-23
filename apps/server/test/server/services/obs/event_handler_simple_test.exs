defmodule Server.Services.OBS.EventHandlerSimpleTest do
  @moduledoc """
  Simplified unit tests for the OBS EventHandler that don't rely on log capture.

  These tests focus on:
  - Process lifecycle and stability
  - Message handling without crashes
  - State persistence
  """
  use ExUnit.Case, async: true

  alias Server.Services.OBS.EventHandler

  setup do
    # Start PubSub if not already started
    case start_supervised({Phoenix.PubSub, name: Server.PubSub}) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end
  end

  describe "start_link/1" do
    test "starts GenServer with valid session_id" do
      session_id = "test_#{:rand.uniform(10000)}"
      opts = [session_id: session_id, name: :"event_handler_#{session_id}"]

      assert {:ok, pid} = EventHandler.start_link(opts)
      assert Process.alive?(pid)

      # Verify state
      state = :sys.get_state(pid)
      assert %EventHandler{session_id: ^session_id} = state

      GenServer.stop(pid)
    end

    test "crashes without session_id" do
      Process.flag(:trap_exit, true)
      opts = [name: :test_no_session]

      assert {:error, _} = EventHandler.start_link(opts)
    end
  end

  describe "event handling" do
    setup do
      session_id = "test_#{:rand.uniform(10000)}"
      opts = [session_id: session_id, name: :"handler_#{session_id}"]
      {:ok, pid} = start_supervised({EventHandler, opts})
      {:ok, pid: pid, session_id: session_id}
    end

    test "handles scene change events without crashing", %{pid: pid} do
      event = %{
        eventType: "CurrentProgramSceneChanged",
        eventData: %{sceneName: "Test Scene"}
      }

      send(pid, {:obs_event, event})
      Process.sleep(10)

      assert Process.alive?(pid)
    end

    test "handles stream state events without crashing", %{pid: pid} do
      event = %{
        eventType: "StreamStateChanged",
        eventData: %{
          outputActive: true,
          outputState: "OBS_WEBSOCKET_OUTPUT_STARTED"
        }
      }

      send(pid, {:obs_event, event})
      Process.sleep(10)

      assert Process.alive?(pid)
    end

    test "handles record state events without crashing", %{pid: pid} do
      event = %{
        eventType: "RecordStateChanged",
        eventData: %{
          outputActive: false,
          outputState: "OBS_WEBSOCKET_OUTPUT_STOPPED"
        }
      }

      send(pid, {:obs_event, event})
      Process.sleep(10)

      assert Process.alive?(pid)
    end

    test "handles unknown events without crashing", %{pid: pid} do
      event = %{
        eventType: "UnknownEventType",
        eventData: %{some: "data"}
      }

      send(pid, {:obs_event, event})
      Process.sleep(10)

      assert Process.alive?(pid)
    end

    test "handles malformed events without crashing", %{pid: pid} do
      malformed_events = [
        # Missing eventType
        %{},
        %{eventType: nil},
        # Missing eventData
        %{eventType: "Test"},
        nil,
        "not a map"
      ]

      for event <- malformed_events do
        send(pid, {:obs_event, event})
      end

      Process.sleep(20)

      assert Process.alive?(pid)
    end

    test "handles non-event messages without crashing", %{pid: pid} do
      messages = [
        :atom_message,
        {:other_tuple, "data"},
        "string message",
        123,
        [1, 2, 3]
      ]

      for msg <- messages do
        send(pid, msg)
      end

      Process.sleep(20)

      assert Process.alive?(pid)
    end

    test "processes many events in sequence", %{pid: pid} do
      # Send 100 mixed events
      for i <- 1..100 do
        event =
          case rem(i, 4) do
            0 -> %{eventType: "CurrentProgramSceneChanged", eventData: %{sceneName: "Scene #{i}"}}
            1 -> %{eventType: "StreamStateChanged", eventData: %{outputActive: true, outputState: "STARTED"}}
            2 -> %{eventType: "RecordStateChanged", eventData: %{outputActive: false, outputState: "STOPPED"}}
            3 -> %{eventType: "Unknown#{i}", eventData: %{index: i}}
          end

        send(pid, {:obs_event, event})
      end

      Process.sleep(50)

      assert Process.alive?(pid)
    end
  end

  describe "state persistence" do
    test "maintains session_id through event processing" do
      session_id = "persistent_#{:rand.uniform(10000)}"
      opts = [session_id: session_id, name: :"persistent_#{session_id}"]
      {:ok, pid} = EventHandler.start_link(opts)

      # Check initial state
      assert %EventHandler{session_id: ^session_id} = :sys.get_state(pid)

      # Send various events
      events = [
        %{eventType: "SceneChanged", eventData: %{sceneName: "Scene1"}},
        %{eventType: "StreamStarted", eventData: %{}},
        %{eventType: "Unknown", eventData: nil},
        nil,
        :invalid
      ]

      for event <- events do
        case event do
          %{} -> send(pid, {:obs_event, event})
          _ -> send(pid, event)
        end
      end

      Process.sleep(20)

      # State should be unchanged
      assert %EventHandler{session_id: ^session_id} = :sys.get_state(pid)

      GenServer.stop(pid)
    end
  end

  describe "concurrent event handling" do
    setup do
      session_id = "concurrent_#{:rand.uniform(10000)}"
      opts = [session_id: session_id, name: :"concurrent_#{session_id}"]
      {:ok, pid} = start_supervised({EventHandler, opts})
      {:ok, pid: pid}
    end

    test "handles events from multiple concurrent senders", %{pid: pid} do
      tasks =
        for i <- 1..50 do
          Task.async(fn ->
            event = %{
              eventType: "TestEvent#{i}",
              eventData: %{sender: i, timestamp: System.system_time()}
            }

            send(pid, {:obs_event, event})
          end)
        end

      Task.await_many(tasks)
      Process.sleep(50)

      assert Process.alive?(pid)
    end
  end

  describe "PubSub integration" do
    test "receives events via PubSub broadcast" do
      session_id = "pubsub_#{:rand.uniform(10000)}"
      topic = "obs_events:#{session_id}"
      opts = [session_id: session_id, name: :"pubsub_#{session_id}"]

      {:ok, pid} = EventHandler.start_link(opts)

      # Broadcast an event
      event = %{eventType: "PubSubTest", eventData: %{via: "broadcast"}}
      Phoenix.PubSub.broadcast(Server.PubSub, topic, {:obs_event, event})

      Process.sleep(10)

      # Handler should still be alive
      assert Process.alive?(pid)

      GenServer.stop(pid)
    end
  end
end
