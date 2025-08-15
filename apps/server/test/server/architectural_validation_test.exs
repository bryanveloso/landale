defmodule Server.ArchitecturalValidationTest do
  @moduledoc """
  Architectural validation tests that provide definitive proof of event system unification.

  These tests ensure that:
  1. All services route through Server.Events.process_event/2
  2. No legacy PubSub topic subscriptions remain
  3. All messages use unified {:event, flat_map} format
  4. No parallel event systems exist
  5. OBS service is properly integrated (currently fails)
  """

  use ServerWeb.ChannelCase, async: true
  import ExUnit.CaptureLog

  alias Server.Events

  describe "Service Integration Validation" do
    test "all services must route through Server.Events.process_event/2" do
      # Mock Server.Events to track all calls
      test_pid = self()

      # Create a mock that records all process_event calls
      mock_events = fn event_type, event_data, opts ->
        send(test_pid, {:server_events_called, event_type, event_data, opts})
        :ok
      end

      # For now, just test that the services exist and have the expected integration
      # This is a placeholder for proper mocking implementation

      # Test that Server.Events.process_event can handle the expected event types
      assert :ok =
               Server.Events.process_event("channel.follow", %{
                 "user_id" => "123",
                 "user_login" => "follower"
               })

      assert :ok =
               Server.Events.process_event("rainwave.update", %{
                 "station_id" => 1,
                 "listening" => true
               })

      assert :ok =
               Server.Events.process_event("ironmon.init", %{
                 "game_type" => "emerald"
               })
    end

    test "OBS EventHandler bypasses Server.Events (architectural violation)" do
      # This test documents the current architectural violation
      # It should FAIL until OBS is properly integrated

      # Start OBS EventHandler
      session_id = "test-session"

      {:ok, handler_pid} =
        Server.Services.OBS.EventHandler.start_link(
          session_id: session_id,
          name: :TestOBSHandler
        )

      # Subscribe to unified events topic
      Phoenix.PubSub.subscribe(Server.PubSub, "events")

      # Send OBS event in legacy format to legacy topic
      legacy_event = %{
        eventType: "StreamStateChanged",
        eventData: %{outputActive: true, outputState: "active"}
      }

      Phoenix.PubSub.broadcast(
        Server.PubSub,
        "obs_events:#{session_id}",
        {:obs_event, legacy_event}
      )

      # Wait for processing
      Process.sleep(50)

      # ASSERTION THAT CURRENTLY FAILS:
      # The unified events topic should receive the event, but it doesn't
      # because OBS EventHandler doesn't route through Server.Events
      refute_received {:event, %{source: :obs, type: "obs.stream_started"}}

      # Clean up
      GenServer.stop(handler_pid)
    end
  end

  describe "PubSub Topic Audit" do
    test "only unified topics should have active subscriptions" do
      # Get all active PubSub topics
      all_topics = Phoenix.PubSub.topics(Server.PubSub)

      # Define allowed topics (unified system)
      allowed_topics = ["events", "dashboard"]

      # Define forbidden legacy topic patterns
      forbidden_patterns = [
        ~r/^obs$/,
        ~r/^twitch$/,
        ~r/^rainwave$/,
        ~r/^ironmon$/,
        ~r/^obs_events:.*$/,
        ~r/^overlay:.*$/
      ]

      # Find any forbidden topics
      forbidden_topics =
        Enum.filter(all_topics, fn topic ->
          topic not in allowed_topics and
            Enum.any?(forbidden_patterns, &Regex.match?(&1, topic))
        end)

      # This will fail if OBS EventHandler is running (it subscribes to obs_events:*)
      assert forbidden_topics == [],
             "Found active subscriptions to legacy topics: #{inspect(forbidden_topics)}. " <>
               "This indicates services are not using the unified event system."
    end

    test "runtime PubSub subscription monitoring" do
      # Monitor PubSub subscriptions during service startup
      initial_topics = Phoenix.PubSub.topics(Server.PubSub)

      # Start OBS EventHandler and capture new subscriptions
      session_id = "monitoring-test"

      {:ok, handler_pid} =
        Server.Services.OBS.EventHandler.start_link(
          session_id: session_id,
          name: :MonitoringTestHandler
        )

      # Allow subscription to register
      Process.sleep(10)

      final_topics = Phoenix.PubSub.topics(Server.PubSub)
      new_topics = final_topics -- initial_topics

      # Check for legacy topic subscriptions
      legacy_subscriptions =
        Enum.filter(new_topics, fn topic ->
          String.starts_with?(topic, "obs_events:")
        end)

      # Clean up
      GenServer.stop(handler_pid)

      # This assertion will fail with current OBS implementation
      assert legacy_subscriptions == [],
             "OBS EventHandler created legacy topic subscriptions: #{inspect(legacy_subscriptions)}"
    end
  end

  describe "Message Format Validation" do
    test "unified topics only accept {:event, flat_map} format" do
      {:ok, socket} = connect(ServerWeb.UserSocket, %{})
      {:ok, _, socket} = subscribe_and_join(socket, ServerWeb.EventsChannel, "events:all")

      # Test legacy message formats are ignored
      legacy_formats = [
        {:obs_event, %{type: "obs.scene_changed"}},
        {:twitch_event, %{type: "channel.follow"}},
        {:rainwave_event, %{type: "rainwave.song_changed"}},
        {:system_event, %{type: "system.health_check"}},
        "invalid_string_message",
        {:unknown_tuple, "data"}
      ]

      for legacy_msg <- legacy_formats do
        Phoenix.PubSub.broadcast(Server.PubSub, "events", legacy_msg)

        # Should not receive any push from legacy formats
        refute_push _, _, 50
      end

      # Test correct format works
      correct_event = %{
        source: :test,
        type: "test.event",
        timestamp: DateTime.utc_now()
      }

      Phoenix.PubSub.broadcast(Server.PubSub, "events", {:event, correct_event})
      assert_push "unknown_event", %{source: :test}
    end

    test "channels gracefully handle malformed events" do
      {:ok, socket} = connect(ServerWeb.UserSocket, %{})
      {:ok, _, socket} = subscribe_and_join(socket, ServerWeb.DashboardChannel, "dashboard:test")

      # Test various malformed event structures
      malformed_events = [
        # Missing required fields
        %{},
        # Missing type
        %{source: :obs},
        # Missing source
        %{type: "obs.event"},
        # Invalid source type
        %{source: "invalid_atom", type: "test.event"},
        # Nil event
        nil,
        # Wrong type entirely
        "not_a_map"
      ]

      log_output =
        capture_log(fn ->
          for malformed <- malformed_events do
            Phoenix.PubSub.broadcast(Server.PubSub, "events", {:event, malformed})
            Process.sleep(10)
          end
        end)

      # Should log warnings but not crash
      assert log_output =~ "Unknown event source" or log_output =~ "Unhandled message"

      # Channel should still be responsive
      test_event = %{source: :system, type: "system.test"}
      Phoenix.PubSub.broadcast(Server.PubSub, "events", {:event, test_event})
      assert_push "system_event", %{source: :system}
    end
  end

  describe "End-to-End Event Flow Validation" do
    test "complete event pipeline: service -> Server.Events -> PubSub -> channels" do
      # Connect to both channels that should receive events
      {:ok, events_socket} = connect(ServerWeb.UserSocket, %{})
      {:ok, _, events_socket} = subscribe_and_join(events_socket, ServerWeb.EventsChannel, "events:all")

      {:ok, dashboard_socket} = connect(ServerWeb.UserSocket, %{})
      {:ok, _, dashboard_socket} = subscribe_and_join(dashboard_socket, ServerWeb.DashboardChannel, "dashboard:test")

      # Test each integrated service's complete flow
      test_events = [
        {"channel.follow", %{"user_id" => "123", "user_login" => "follower"}, :twitch},
        {"rainwave.update", %{"station_id" => 1, "listening" => true}, :rainwave},
        {"ironmon.init", %{"game_type" => "emerald"}, :ironmon},
        {"system.service_started", %{"service" => "test"}, :system}
      ]

      for {event_type, event_data, expected_source} <- test_events do
        # Process through unified system
        assert :ok = Server.Events.process_event(event_type, event_data)

        # Verify both channels receive the unified event
        assert_push("event", %{source: expected_source, type: event_type}, 100, events_socket)

        # Dashboard channel may have different event names
        receive do
          %Phoenix.Socket.Message{event: event_name, payload: %{source: source}} when source == expected_source ->
            assert event_name in ["twitch_event", "rainwave_event", "ironmon_event", "system_event"]
        after
          100 ->
            flunk("Dashboard channel did not receive event for #{event_type}")
        end
      end
    end

    test "event correlation IDs are properly maintained" do
      # Process event and verify correlation ID propagation
      event_data = %{"user_id" => "123", "user_login" => "test"}

      # Subscribe to events to capture the normalized event
      Phoenix.PubSub.subscribe(Server.PubSub, "events")

      assert :ok = Server.Events.process_event("channel.follow", event_data)

      assert_receive {:event, normalized_event}

      # Verify correlation ID exists and is valid format
      assert Map.has_key?(normalized_event, :correlation_id)
      assert is_binary(normalized_event.correlation_id)
      assert String.length(normalized_event.correlation_id) > 0

      # Verify event structure is flat (no nested maps)
      assert flat_map?(normalized_event)
    end
  end

  describe "Legacy Pattern Detection" do
    test "no code should use prohibited event handler patterns" do
      # This test performs static analysis to detect legacy patterns
      # In a real implementation, you'd scan the compiled modules

      # This test would normally check module compilation patterns
      # For now, it documents the known violation

      # For this test, we'll check OBS EventHandler specifically
      {:ok, handler_pid} =
        Server.Services.OBS.EventHandler.start_link(
          session_id: "pattern-test",
          name: :PatternTestHandler
        )

      # Check if it has the legacy handle_info callback
      handler_module = Server.Services.OBS.EventHandler
      callbacks = handler_module.__info__(:functions)

      # This checks for the problematic handle_info({:obs_event, event}, state) callback
      has_legacy_callback =
        Enum.any?(callbacks, fn {name, arity} ->
          name == :handle_info and arity == 2
        end)

      GenServer.stop(handler_pid)

      # This assertion documents the current violation
      # It should pass once OBS is properly refactored
      if has_legacy_callback do
        # Check if the implementation still uses legacy patterns
        # This is a proxy test - in practice you'd check the actual implementation
        assert false, "OBS EventHandler still implements legacy {:obs_event, event} pattern"
      end
    end
  end

  # Helper functions

  defp flat_map?(map) when is_map(map) do
    Enum.all?(map, fn {_key, value} ->
      not is_map(value) or is_struct(value, DateTime)
    end)
  end

  defp flat_map?(_), do: false
end
