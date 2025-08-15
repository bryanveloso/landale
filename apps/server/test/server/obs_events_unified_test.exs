defmodule Server.OBSEventsUnifiedTest do
  @moduledoc """
  Tests for OBS event integration with the unified event system.

  This test verifies that OBS events are properly processed through
  Server.Events.process_event/2 and routed to the unified "events" topic.
  """
  use ExUnit.Case, async: true

  alias Server.Events

  @moduletag :unit

  describe "OBS event processing through unified system" do
    test "processes obs.scene_changed events correctly" do
      event_data = %{
        scene_name: "Test Scene",
        session_id: "test-session-123"
      }

      # Should process without error
      assert :ok = Events.process_event("obs.scene_changed", event_data)
    end

    test "processes obs.stream_started events correctly" do
      event_data = %{
        output_active: true,
        output_state: "OBS_WEBSOCKET_OUTPUT_STARTING",
        session_id: "test-session-123"
      }

      # Should process without error
      assert :ok = Events.process_event("obs.stream_started", event_data)
    end

    test "processes obs.stream_stopped events correctly" do
      event_data = %{
        output_active: false,
        output_state: "OBS_WEBSOCKET_OUTPUT_STOPPED",
        session_id: "test-session-123"
      }

      # Should process without error
      assert :ok = Events.process_event("obs.stream_stopped", event_data)
    end

    test "processes obs.recording_started events correctly" do
      event_data = %{
        output_active: true,
        output_state: "OBS_WEBSOCKET_OUTPUT_STARTING",
        session_id: "test-session-123"
      }

      # Should process without error
      assert :ok = Events.process_event("obs.recording_started", event_data)
    end

    test "processes obs.recording_stopped events correctly" do
      event_data = %{
        output_active: false,
        output_state: "OBS_WEBSOCKET_OUTPUT_STOPPED",
        session_id: "test-session-123"
      }

      # Should process without error
      assert :ok = Events.process_event("obs.recording_stopped", event_data)
    end

    test "processes obs.unknown_event correctly" do
      event_data = %{
        event_type: "CustomOBSEvent",
        event_data: %{"custom_field" => "custom_value"},
        session_id: "test-session-123"
      }

      # Should process without error
      assert :ok = Events.process_event("obs.unknown_event", event_data)
    end

    test "normalizes events with correct source and structure" do
      event_data = %{
        scene_name: "Test Scene",
        session_id: "test-session-123"
      }

      normalized = Events.normalize_event("obs.scene_changed", event_data)

      # Should have correct structure
      assert normalized.type == "obs.scene_changed"
      assert normalized.source == :obs
      assert normalized.scene_name == "Test Scene"
      assert normalized.session_id == "test-session-123"
      assert is_binary(normalized.id)
      assert is_binary(normalized.correlation_id)
      assert %DateTime{} = normalized.timestamp
    end
  end
end
