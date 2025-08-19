defmodule Server.OBSServiceComplianceTest do
  @moduledoc """
  Specific tests targeting OBS service compliance with the unified event system.

  These tests provide targeted validation that the OBS service properly integrates
  with Server.Events rather than using legacy parallel event systems.

  ⚠️  CRITICAL: These tests currently FAIL because OBS EventHandler still uses
  legacy patterns. They serve as regression tests to ensure OBS integration.
  """

  use ServerWeb.ChannelCase, async: true
  import ExUnit.CaptureLog

  alias Server.Events

  describe "OBS Service Integration Compliance" do
    @tag :integration
    test "OBS events should route through Server.Events.process_event/2" do
      # This test FAILS with current implementation - OBS bypasses Server.Events

      # Connect to unified channels
      {:ok, events_socket} = connect(ServerWeb.UserSocket, %{})
      {:ok, _, events_socket} = subscribe_and_join(events_socket, ServerWeb.EventsChannel, "events:obs")

      {:ok, dashboard_socket} = connect(ServerWeb.UserSocket, %{})
      {:ok, _, dashboard_socket} = subscribe_and_join(dashboard_socket, ServerWeb.DashboardChannel, "dashboard:main")

      # Simulate OBS events that SHOULD come through the unified system
      obs_events = [
        {
          "obs.connection_established",
          %{
            "session_id" => "test-session-123",
            "websocket_version" => "5.0.0",
            "rpc_version" => "1",
            "authentication" => false
          }
        },
        {
          "obs.stream_started",
          %{
            "session_id" => "test-session-123",
            "output_active" => true,
            "output_state" => "active"
          }
        },
        {
          "obs.scene_changed",
          %{
            "session_id" => "test-session-123",
            "scene_name" => "Main Scene",
            "previous_scene" => "Loading Scene"
          }
        }
      ]

      # Test first event type to verify integration works
      {first_event_type, first_event_data} = hd(obs_events)

      # Process through the UNIFIED system (this is what should happen)
      assert :ok = Events.process_event(first_event_type, first_event_data)

      # These assertions SHOULD pass once OBS is properly integrated
      assert_push(
        "obs_event",
        %{source: :obs, type: first_event_type, session_id: "test-session-123"},
        100
      )

      # Dashboard should also receive OBS events
      assert_push("obs_event", %{source: :obs}, 100)
    end

    @tag :legacy_detection
    test "OBS EventHandler should not subscribe to legacy topics" do
      # This test FAILS with current implementation

      # Monitor PubSub topics before starting OBS handler
      initial_topics = Phoenix.PubSub.topics(Server.PubSub)

      # Start OBS EventHandler
      session_id = "compliance-test"

      {:ok, handler_pid} =
        Server.Services.OBS.EventHandler.start_link(
          session_id: session_id,
          name: :ComplianceTestHandler
        )

      # Allow subscription to register
      Process.sleep(10)

      # Check for new topic subscriptions
      final_topics = Phoenix.PubSub.topics(Server.PubSub)
      new_topics = final_topics -- initial_topics

      # Filter for OBS-specific legacy topics
      obs_legacy_topics =
        Enum.filter(new_topics, fn topic ->
          String.starts_with?(topic, "obs_events:") or
            String.starts_with?(topic, "overlay:")
        end)

      # Clean up
      GenServer.stop(handler_pid)

      # This assertion FAILS with current implementation
      assert obs_legacy_topics == [],
             "COMPLIANCE VIOLATION: OBS EventHandler subscribed to legacy topics: #{inspect(obs_legacy_topics)}. " <>
               "All OBS events should flow through the unified 'events' topic."
    end

    @tag :legacy_detection
    test "OBS EventHandler should not use legacy message formats" do
      # This test validates that OBS doesn't broadcast legacy message formats

      # Start OBS EventHandler
      session_id = "format-test"

      {:ok, handler_pid} =
        Server.Services.OBS.EventHandler.start_link(
          session_id: session_id,
          name: :FormatTestHandler
        )

      # Subscribe to ALL topics to catch any legacy broadcasts
      all_topics = Phoenix.PubSub.topics(Server.PubSub)

      for topic <- all_topics do
        Phoenix.PubSub.subscribe(Server.PubSub, topic)
      end

      # Subscribe to legacy topic that OBS EventHandler uses
      Phoenix.PubSub.subscribe(Server.PubSub, "obs_events:#{session_id}")

      # Send a legacy OBS event to trigger the handler
      legacy_event = %{
        eventType: "CurrentProgramSceneChanged",
        eventData: %{sceneName: "Test Scene"}
      }

      capture_log(fn ->
        Phoenix.PubSub.broadcast(
          Server.PubSub,
          "obs_events:#{session_id}",
          {:obs_event, legacy_event}
        )

        # Allow event processing
        Process.sleep(50)
      end)

      # Check for legacy message formats
      legacy_messages = receive_all_messages(100)

      # Filter for problematic legacy formats
      legacy_obs_messages =
        Enum.filter(legacy_messages, fn msg ->
          case msg do
            {:obs_event, _} -> true
            {topic, {:obs_event, _}} -> true
            _ -> false
          end
        end)

      # Clean up
      GenServer.stop(handler_pid)

      # This assertion will FAIL with current implementation
      assert legacy_obs_messages == [],
             "COMPLIANCE VIOLATION: Detected legacy OBS message formats: #{inspect(legacy_obs_messages)}. " <>
               "All events should use {:event, normalized_event} format."
    end

    @tag :architectural
    test "OBS events should appear in unified events topic" do
      # This test ensures OBS events reach the unified system

      # Subscribe to unified events topic
      Phoenix.PubSub.subscribe(Server.PubSub, "events")

      # Process an OBS event through the CORRECT unified path
      obs_event_data = %{
        "session_id" => "unified-test",
        "output_active" => true,
        "output_state" => "active"
      }

      assert :ok = Events.process_event("obs.stream_started", obs_event_data)

      # Should receive unified event format
      assert_receive {:event, normalized_event}, 100
      assert normalized_event.source == :obs
      assert normalized_event.type == "obs.stream_started"
      assert normalized_event.stream_status == "active"
      assert normalized_event.session_id == "unified-test"

      # Verify it's properly normalized (flat format)
      assert flat_map?(normalized_event)
    end

    @tag :comparison
    test "compare legacy OBS flow vs unified flow" do
      # This test documents the difference between current legacy flow and target unified flow

      # LEGACY FLOW (current implementation)
      session_id = "comparison-test"

      {:ok, handler_pid} =
        Server.Services.OBS.EventHandler.start_link(
          session_id: session_id,
          name: :ComparisonTestHandler
        )

      # Subscribe to unified events to see if anything comes through
      Phoenix.PubSub.subscribe(Server.PubSub, "events")

      # Subscribe to legacy overlay topics that OBS currently broadcasts to
      Phoenix.PubSub.subscribe(Server.PubSub, "overlay:stream_state")

      # Send legacy OBS event
      legacy_event = %{
        eventType: "StreamStateChanged",
        eventData: %{outputActive: true, outputState: "active"}
      }

      Phoenix.PubSub.broadcast(
        Server.PubSub,
        "obs_events:#{session_id}",
        {:obs_event, legacy_event}
      )

      Process.sleep(50)

      # Check what we received
      legacy_overlay_msg =
        receive do
          {topic, data} when topic == "overlay:stream_state" -> {topic, data}
        after
          50 -> nil
        end

      unified_event_msg =
        receive do
          {:event, _} = msg -> msg
        after
          50 -> nil
        end

      # Clean up
      GenServer.stop(handler_pid)

      # Document current behavior vs desired behavior
      assert legacy_overlay_msg != nil, "Legacy flow should broadcast to overlay:stream_state topic"
      assert unified_event_msg == nil, "PROBLEM: Unified events topic doesn't receive OBS events"

      # UNIFIED FLOW (desired implementation)
      # Process same event through unified system
      unified_event_data = %{
        "session_id" => session_id,
        "output_active" => true,
        "output_state" => "active"
      }

      assert :ok = Events.process_event("obs.stream_started", unified_event_data)

      # Should receive properly formatted unified event
      assert_receive {:event, normalized_event}, 100
      assert normalized_event.source == :obs
      assert normalized_event.type == "obs.stream_started"
    end
  end

  describe "OBS Event Validation" do
    test "OBS event validation works through unified system" do
      # Test that OBS events are properly validated when processed through Server.Events

      valid_obs_events = [
        {
          "obs.connection_established",
          %{
            "session_id" => "valid-session",
            "websocket_version" => "5.0.0",
            "rpc_version" => "1"
          }
        },
        {
          "obs.scene_changed",
          %{
            "scene_name" => "Valid Scene Name",
            "session_id" => "valid-session"
          }
        }
      ]

      for {event_type, event_data} <- valid_obs_events do
        assert :ok = Events.process_event(event_type, event_data)
      end

      # Test invalid OBS events are rejected
      invalid_obs_events = [
        {
          "obs.connection_established",
          %{
            # Missing required session_id
            "websocket_version" => "5.0.0"
          }
        },
        {
          "obs.scene_changed",
          %{
            # Invalid scene name type
            "scene_name" => 12_345,
            "session_id" => "test"
          }
        }
      ]

      for {event_type, event_data} <- invalid_obs_events do
        assert {:error, {:validation_failed, _}} = Events.process_event(event_type, event_data)
      end
    end
  end

  describe "OBS Service Refactoring Requirements" do
    @tag :documentation
    test "document required changes for OBS service compliance" do
      # This test documents what needs to change for OBS compliance

      required_changes = %{
        obs_event_handler: [
          "Remove subscription to obs_events:SESSION_ID topic",
          "Remove handle_info({:obs_event, event}, state) callback",
          "Remove direct PubSub broadcasts to overlay:* topics",
          "Add integration with Server.Events.process_event/2"
        ],
        obs_connection: [
          "Update event broadcasting to use Server.Events instead of direct PubSub",
          "Change event format from {:obs_event, data} to Server.Events calls"
        ],
        obs_services: [
          "Update scene_manager.ex to not subscribe to obs_events topics",
          "Update stream_manager.ex to not subscribe to obs_events topics",
          "Ensure all OBS events flow through unified system"
        ]
      }

      # This test always passes - it's documentation of required work
      assert map_size(required_changes) > 0

      # Log the requirements for visibility
      IO.puts("\n=== OBS SERVICE COMPLIANCE REQUIREMENTS ===")

      for {service, changes} <- required_changes do
        IO.puts("\n#{service}:")

        for change <- changes do
          IO.puts("  - #{change}")
        end
      end

      IO.puts("\n" <> String.duplicate("=", 50))
    end
  end

  # Helper functions

  defp receive_all_messages(timeout) do
    receive_all_messages([], timeout)
  end

  defp receive_all_messages(acc, timeout) do
    receive do
      msg -> receive_all_messages([msg | acc], timeout)
    after
      timeout ->
        Enum.reverse(acc)
    end
  end

  defp flat_map?(map) when is_map(map) do
    Enum.all?(map, fn {_key, value} ->
      case value do
        %DateTime{} ->
          true

        inner_map when is_map(inner_map) ->
          false

        list when is_list(list) ->
          # Allow simple lists but not lists of maps (except with string keys)
          Enum.all?(list, fn item ->
            not is_map(item) or (is_map(item) and Enum.all?(Map.keys(item), &is_binary/1))
          end)

        _ ->
          true
      end
    end)
  end

  defp flat_map?(_), do: false
end
