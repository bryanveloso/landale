defmodule Server.Services.OBS.EventHandlerUnifiedTest do
  @moduledoc """
  Tests OBS EventHandler integration with unified event system.

  This test verifies that the EventHandler routes events through both
  the unified system (Server.Events.process_event/2) and maintains
  backward compatibility with existing broadcasts.
  """
  use ExUnit.Case, async: true

  alias Server.Events
  alias Server.Services.OBS.EventHandler

  @moduletag :unit

  describe "OBS EventHandler dual-write pattern" do
    setup do
      # Start EventHandler for testing
      opts = [session_id: "test-session", name: :"test-event-handler-#{:rand.uniform(10000)}"]
      {:ok, handler} = EventHandler.start_link(opts)

      # Subscribe to verify legacy broadcasts still work
      Phoenix.PubSub.subscribe(Server.PubSub, "overlay:scene_changed")
      Phoenix.PubSub.subscribe(Server.PubSub, "overlay:stream_state")
      Phoenix.PubSub.subscribe(Server.PubSub, "overlay:record_state")
      Phoenix.PubSub.subscribe(Server.PubSub, "overlay:unhandled_event")

      # Subscribe to unified events to verify routing
      Phoenix.PubSub.subscribe(Server.PubSub, "events")
      Phoenix.PubSub.subscribe(Server.PubSub, "dashboard")

      %{handler: handler}
    end

    test "routes CurrentProgramSceneChanged through unified system", %{handler: handler} do
      scene_event = %{
        eventType: "CurrentProgramSceneChanged",
        eventData: %{sceneName: "Test Scene"}
      }

      # Send event to handler
      send(handler, {:obs_event, scene_event})

      # Should receive legacy broadcast (backward compatibility)
      assert_receive %{scene: "Test Scene", session_id: "test-session"}

      # Should receive unified event
      assert_receive {:event, unified_event}
      assert unified_event.type == "obs.scene_changed"
      assert unified_event.source == :obs
      assert unified_event.scene_name == "Test Scene"
      assert unified_event.session_id == "test-session"

      # Should receive unified event on dashboard topic
      assert_receive {:event, dashboard_event}
      assert dashboard_event.type == "obs.scene_changed"
      assert dashboard_event.source == :obs
    end

    test "routes StreamStateChanged through unified system", %{handler: handler} do
      stream_event = %{
        eventType: "StreamStateChanged",
        eventData: %{outputActive: true, outputState: "OBS_WEBSOCKET_OUTPUT_STARTING"}
      }

      # Send event to handler
      send(handler, {:obs_event, stream_event})

      # Should receive legacy broadcast (backward compatibility)
      assert_receive %{active: true, state: "OBS_WEBSOCKET_OUTPUT_STARTING", session_id: "test-session"}

      # Should receive unified event for stream started
      assert_receive {:event, unified_event}
      assert unified_event.type == "obs.stream_started"
      assert unified_event.source == :obs
      assert unified_event.output_active == true
      assert unified_event.session_id == "test-session"
    end

    test "routes RecordStateChanged through unified system", %{handler: handler} do
      record_event = %{
        eventType: "RecordStateChanged",
        eventData: %{outputActive: false, outputState: "OBS_WEBSOCKET_OUTPUT_STOPPED"}
      }

      # Send event to handler
      send(handler, {:obs_event, record_event})

      # Should receive legacy broadcast (backward compatibility)
      assert_receive %{active: false, state: "OBS_WEBSOCKET_OUTPUT_STOPPED", session_id: "test-session"}

      # Should receive unified event for recording stopped
      assert_receive {:event, unified_event}
      assert unified_event.type == "obs.recording_stopped"
      assert unified_event.source == :obs
      assert unified_event.output_active == false
      assert unified_event.session_id == "test-session"
    end

    test "routes unknown events through unified system", %{handler: handler} do
      unknown_event = %{
        eventType: "TotallyUnknownOBSEvent",
        eventData: %{customField: "customValue"}
      }

      # Send event to handler
      send(handler, {:obs_event, unknown_event})

      # Should receive legacy broadcast (backward compatibility)
      assert_receive %{event_type: "TotallyUnknownOBSEvent", session_id: "test-session"}

      # Should receive unified event for unknown event
      assert_receive {:event, unified_event}
      assert unified_event.type == "obs.unknown_event"
      assert unified_event.source == :obs
      assert unified_event.obs_event_type == "TotallyUnknownOBSEvent"
      assert unified_event.session_id == "test-session"
    end

    test "handles malformed events gracefully", %{handler: handler} do
      malformed_event = "not a map"

      # Send malformed event to handler
      send(handler, {:obs_event, malformed_event})

      # Should not crash and not send any unified events
      refute_receive {:event, _}

      # Handler should still be alive
      assert Process.alive?(handler)
    end
  end
end
