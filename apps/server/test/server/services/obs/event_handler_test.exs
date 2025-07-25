defmodule Server.Services.OBS.EventHandlerTest do
  @moduledoc """
  Behavior-driven tests for the OBS EventHandler GenServer.

  Tests focus on observable behavior through public APIs rather than
  internal message handling. Events are delivered through the proper
  PubSub channel as they would be in production.
  """
  use ExUnit.Case, async: true

  alias Server.Services.OBS.EventHandler

  def test_session_id, do: "test_event_handler_#{:rand.uniform(100_000)}_#{System.unique_integer([:positive])}"

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
      opts = [session_id: session_id, name: :"event_handler_#{session_id}"]

      assert {:ok, pid} = EventHandler.start_link(opts)
      assert Process.alive?(pid)

      # Verify state through public API
      assert EventHandler.get_session_id(pid) == session_id

      # Clean up
      GenServer.stop(pid)
    end

    test "requires session_id in options" do
      Process.flag(:trap_exit, true)
      opts = [name: :test_no_session]

      assert {:error, _} = EventHandler.start_link(opts)
    end

    test "subscribes to PubSub topic on init" do
      session_id = test_session_id()
      topic = "obs_events:#{session_id}"
      opts = [session_id: session_id, name: :"test_pubsub_#{session_id}"]

      # Start handler
      {:ok, pid} = EventHandler.start_link(opts)

      # Send a test message to verify subscription
      Phoenix.PubSub.broadcast(Server.PubSub, topic, {:obs_event, %{eventType: "TestEvent"}})

      # Give it time to process
      Process.sleep(10)

      # Handler should still be alive (didn't crash on message)
      assert Process.alive?(pid)

      # Clean up
      GenServer.stop(pid)
    end
  end

  describe "event processing resilience" do
    setup do
      session_id = test_session_id()
      opts = [session_id: session_id, name: :"test_handler_#{:rand.uniform(10000)}"]
      {:ok, pid} = start_supervised({EventHandler, opts})
      {:ok, pid: pid, session_id: session_id}
    end

    test "processes events without crashing", %{pid: pid, session_id: session_id} do
      event = %{
        eventType: "SomeEvent",
        eventData: %{data: "test"}
      }

      # Event should be processed without crashing
      Phoenix.PubSub.broadcast(
        Server.PubSub,
        "obs_events:#{session_id}",
        {:obs_event, event}
      )

      Process.sleep(10)

      # Handler should remain alive
      assert Process.alive?(pid)
    end

    test "handles CurrentProgramSceneChanged event", %{pid: pid, session_id: session_id} do
      event = %{
        eventType: "CurrentProgramSceneChanged",
        eventData: %{sceneName: "New Scene"}
      }

      # Event should be processed without crashing
      Phoenix.PubSub.broadcast(
        Server.PubSub,
        "obs_events:#{session_id}",
        {:obs_event, event}
      )

      Process.sleep(10)

      # Handler should remain alive
      assert Process.alive?(pid)
    end

    test "handles StreamStateChanged event", %{pid: pid, session_id: session_id} do
      event = %{
        eventType: "StreamStateChanged",
        eventData: %{
          outputActive: true,
          outputState: "OBS_WEBSOCKET_OUTPUT_STARTED"
        }
      }

      # Event should be processed without crashing
      Phoenix.PubSub.broadcast(
        Server.PubSub,
        "obs_events:#{session_id}",
        {:obs_event, event}
      )

      Process.sleep(10)

      # Handler should remain alive
      assert Process.alive?(pid)
    end

    test "handles RecordStateChanged event", %{pid: pid, session_id: session_id} do
      event = %{
        eventType: "RecordStateChanged",
        eventData: %{
          outputActive: false,
          outputState: "OBS_WEBSOCKET_OUTPUT_STOPPED"
        }
      }

      # Event should be processed without crashing
      Phoenix.PubSub.broadcast(
        Server.PubSub,
        "obs_events:#{session_id}",
        {:obs_event, event}
      )

      Process.sleep(10)

      # Handler should remain alive
      assert Process.alive?(pid)
    end

    test "handles unknown events gracefully", %{pid: pid, session_id: session_id} do
      event = %{
        eventType: "UnknownEventType",
        eventData: %{random: "data"}
      }

      # Event should be processed without crashing
      Phoenix.PubSub.broadcast(
        Server.PubSub,
        "obs_events:#{session_id}",
        {:obs_event, event}
      )

      Process.sleep(10)

      # Should not crash
      assert Process.alive?(pid)
    end

    test "handles events with missing data gracefully", %{pid: pid, session_id: session_id} do
      # Event without eventData
      event = %{eventType: "StreamStateChanged"}

      # Event should be processed without crashing
      Phoenix.PubSub.broadcast(
        Server.PubSub,
        "obs_events:#{session_id}",
        {:obs_event, event}
      )

      Process.sleep(10)

      # Should not crash
      assert Process.alive?(pid)
    end

    test "processes multiple events in sequence", %{pid: pid, session_id: session_id} do
      events = [
        %{eventType: "CurrentProgramSceneChanged", eventData: %{sceneName: "Scene 1"}},
        %{eventType: "StreamStateChanged", eventData: %{outputActive: true, outputState: "STARTED"}},
        %{eventType: "UnknownEvent", eventData: %{}},
        %{eventType: "RecordStateChanged", eventData: %{outputActive: true, outputState: "STARTED"}},
        %{eventType: "CurrentProgramSceneChanged", eventData: %{sceneName: "Scene 2"}}
      ]

      # Send all events
      Enum.each(events, fn event ->
        Phoenix.PubSub.broadcast(
          Server.PubSub,
          "obs_events:#{session_id}",
          {:obs_event, event}
        )
      end)

      Process.sleep(50)

      # Should still be alive after all events
      assert Process.alive?(pid)
    end
  end

  describe "concurrent event handling" do
    setup do
      session_id = test_session_id()
      opts = [session_id: session_id, name: :"test_concurrent_#{:rand.uniform(10000)}"]
      {:ok, pid} = start_supervised({EventHandler, opts})
      {:ok, pid: pid, session_id: session_id}
    end

    test "handles concurrent events from multiple sources", %{pid: pid, session_id: session_id} do
      # Spawn multiple processes to send events concurrently
      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            event = %{
              eventType: "CurrentProgramSceneChanged",
              eventData: %{sceneName: "Scene #{i}"}
            }

            Phoenix.PubSub.broadcast(
              Server.PubSub,
              "obs_events:#{session_id}",
              {:obs_event, event}
            )
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

      # Verify initial session ID through public API
      assert EventHandler.get_session_id(pid) == session_id

      # Send some events
      for i <- 1..5 do
        event = %{eventType: "TestEvent", eventData: %{index: i}}

        Phoenix.PubSub.broadcast(
          Server.PubSub,
          "obs_events:#{session_id}",
          {:obs_event, event}
        )
      end

      Process.sleep(20)

      # State should still have the same session_id
      assert EventHandler.get_session_id(pid) == session_id

      # Clean up
      GenServer.stop(pid)
    end
  end

  describe "error scenarios" do
    setup do
      session_id = test_session_id()
      opts = [session_id: session_id, name: :"test_error_#{:rand.uniform(10000)}"]
      {:ok, pid} = start_supervised({EventHandler, opts})
      {:ok, pid: pid, session_id: session_id}
    end

    test "handles malformed events", %{pid: pid, session_id: session_id} do
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
        Phoenix.PubSub.broadcast(
          Server.PubSub,
          "obs_events:#{session_id}",
          {:obs_event, event}
        )
      end

      Process.sleep(20)

      # Should not crash
      assert Process.alive?(pid)
    end

    test "handles non-obs_event messages", %{pid: pid} do
      # Send various non-event messages directly (these won't come through PubSub)
      send(pid, :unexpected_atom)
      send(pid, {:other_tuple, "data"})
      send(pid, "string message")

      Process.sleep(20)

      # Should ignore and not crash
      assert Process.alive?(pid)
    end
  end
end
