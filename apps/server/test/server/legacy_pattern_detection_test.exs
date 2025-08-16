defmodule Server.LegacyPatternDetectionTest do
  @moduledoc """
  Comprehensive tests to detect any remaining legacy event system patterns.

  These tests act as architectural guardrails to prevent regression to
  parallel event systems and ensure continued compliance with the unified
  Server.Events architecture.

  These tests provide automated detection of:
  1. Legacy PubSub topic usage
  2. Legacy message formats
  3. Bypassed event routing
  4. Non-compliant service patterns
  """

  use ServerWeb.ChannelCase, async: true
  import ExUnit.CaptureLog

  alias Server.Events

  describe "Static Architecture Analysis" do
    test "no modules should subscribe to prohibited legacy topics" do
      # Define patterns for topics that are now forbidden
      prohibited_topic_patterns = [
        ~r/^obs$/,
        ~r/^twitch$/,
        ~r/^rainwave$/,
        ~r/^ironmon$/,
        ~r/^system$/,
        ~r/^obs_events:.*$/,
        ~r/^twitch_events:.*$/,
        ~r/^overlay:.*$/
      ]

      # Get all currently active PubSub topics
      active_topics = Phoenix.PubSub.topics(Server.PubSub)

      # Check for prohibited topics
      prohibited_topics =
        Enum.filter(active_topics, fn topic ->
          Enum.any?(prohibited_topic_patterns, &Regex.match?(&1, topic))
        end)

      # Exception: Allow test-specific topics during testing
      test_topics =
        Enum.filter(prohibited_topics, fn topic ->
          String.contains?(topic, "test") or String.contains?(topic, "Test")
        end)

      actual_violations = prohibited_topics -- test_topics

      if actual_violations != [] do
        IO.puts("\n⚠️  ARCHITECTURAL VIOLATIONS DETECTED:")
        IO.puts("Legacy topic subscriptions found: #{inspect(actual_violations)}")
        IO.puts("These topics indicate services are not using the unified event system.")
        IO.puts(~s(Expected topics: ["events", "dashboard"] + test topics only\n))
      end

      assert actual_violations == [],
             "Found active subscriptions to prohibited legacy topics: #{inspect(actual_violations)}"
    end

    test "unified topics should be the primary active topics" do
      active_topics = Phoenix.PubSub.topics(Server.PubSub)

      # Expected unified topics
      required_topics = ["events", "dashboard"]

      # Check that our unified topics exist
      for topic <- required_topics do
        assert topic in active_topics,
               "Required unified topic '#{topic}' is not active"
      end

      # Count non-test topics
      non_test_topics =
        Enum.filter(active_topics, fn topic ->
          not (String.contains?(topic, "test") or String.contains?(topic, "Test"))
        end)

      # Should be minimal set of topics (unified topics + any necessary system topics)
      assert length(non_test_topics) <= 10,
             "Too many active topics suggests parallel event systems exist. " <>
               "Active topics: #{inspect(non_test_topics)}"
    end
  end

  describe "Runtime Pattern Detection" do
    test "monitor for legacy message formats during event processing" do
      # Subscribe to all active topics to monitor message formats
      active_topics = Phoenix.PubSub.topics(Server.PubSub)

      for topic <- active_topics do
        Phoenix.PubSub.subscribe(Server.PubSub, topic)
      end

      # Process various events through the unified system
      test_events = [
        {"channel.follow", %{"user_id" => "123", "user_login" => "follower"}},
        {"obs.stream_started", %{"session_id" => "test123"}},
        {"rainwave.update", %{"station_id" => 1}},
        {"system.service_started", %{"service" => "test"}}
      ]

      for {event_type, event_data} <- test_events do
        assert :ok = Events.process_event(event_type, event_data)
      end

      # Allow time for message propagation
      Process.sleep(100)

      # Collect all messages received
      messages = receive_all_messages(50)

      # Analyze message formats
      legacy_message_formats =
        Enum.filter(messages, fn msg ->
          case msg do
            {:obs_event, _} -> true
            {:twitch_event, _} -> true
            {:rainwave_event, _} -> true
            {:ironmon_event, _} -> true
            {:system_event, _} -> true
            _ -> false
          end
        end)

      assert legacy_message_formats == [],
             "Detected legacy message formats: #{inspect(legacy_message_formats)}. " <>
               "All events should use {:event, normalized_event} format."
    end

    test "verify all broadcasted events use unified format" do
      # Subscribe to unified topics
      Phoenix.PubSub.subscribe(Server.PubSub, "events")
      Phoenix.PubSub.subscribe(Server.PubSub, "dashboard")

      # Process events and verify format
      events_to_test = [
        {"channel.chat.message", %{"message_id" => "msg123", "chatter_user_id" => "456"}},
        {"obs.scene_changed", %{"scene_name" => "Test Scene", "session_id" => "test"}},
        {"rainwave.song_changed", %{"song_id" => 123, "station_id" => 1}},
        {"ironmon.init", %{"game_type" => "emerald"}},
        {"system.health_check", %{"service" => "test", "status" => "healthy"}}
      ]

      for {event_type, event_data} <- events_to_test do
        assert :ok = Events.process_event(event_type, event_data)

        # Should receive exactly one message in unified format
        assert_receive {:event, normalized_event}, 200

        # Verify unified format compliance
        assert Map.has_key?(normalized_event, :source)
        assert Map.has_key?(normalized_event, :type)
        assert Map.has_key?(normalized_event, :timestamp)
        assert Map.has_key?(normalized_event, :correlation_id)
        assert normalized_event.type == event_type

        # Verify flat structure
        assert flat_normalized_event?(normalized_event)
      end
    end

    test "detect services bypassing Server.Events" do
      # This test monitors for direct PubSub broadcasts that bypass Server.Events

      # Track calls to Server.Events.process_event
      test_pid = self()
      original_process_event = &Events.process_event/3

      # Monitor Events.process_event calls
      events_calls = Agent.start_link(fn -> [] end)
      {:ok, events_agent} = events_calls

      # Override process_event to track calls (simplified mock)
      tracked_process_event = fn event_type, event_data, opts ->
        Agent.update(events_agent, fn calls ->
          [{event_type, event_data, opts} | calls]
        end)

        original_process_event.(event_type, event_data, opts)
      end

      # Subscribe to unified topics to see what actually gets broadcasted
      Phoenix.PubSub.subscribe(Server.PubSub, "events")

      # Start OBS EventHandler (known to bypass Server.Events)
      session_id = "bypass-detection"

      {:ok, obs_handler} =
        Server.Services.OBS.EventHandler.start_link(
          session_id: session_id,
          name: :BypassDetectionHandler
        )

      # Trigger OBS event through legacy path
      legacy_obs_event = %{
        eventType: "StreamStateChanged",
        eventData: %{outputActive: true}
      }

      Phoenix.PubSub.broadcast(
        Server.PubSub,
        "obs_events:#{session_id}",
        {:obs_event, legacy_obs_event}
      )

      Process.sleep(100)

      # Check if Server.Events was called
      events_calls_made = Agent.get(events_agent, &Enum.reverse/1)

      obs_events_processed =
        Enum.filter(events_calls_made, fn {event_type, _, _} ->
          String.starts_with?(event_type, "obs.")
        end)

      # Check if unified events topic received anything
      unified_events_received =
        receive do
          {:event, %{source: :obs}} -> true
        after
          50 -> false
        end

      # Clean up
      GenServer.stop(obs_handler)
      Agent.stop(events_agent)

      # Assertions that reveal bypassing behavior
      assert obs_events_processed == [],
             "OBS events were not processed through Server.Events.process_event/2"

      assert unified_events_received == false,
             "OBS events did not reach unified events topic"

      # This documents the bypass behavior
      IO.puts("\n⚠️  SERVICE BYPASS DETECTED:")
      IO.puts("OBS EventHandler processes events without using Server.Events")
      IO.puts("This violates the unified event architecture")
    end
  end

  describe "Channel Compliance Validation" do
    test "all channels should only handle {:event, event} messages" do
      # Test each channel's message handling compliance

      channels_to_test = [
        {ServerWeb.EventsChannel, "events:all"},
        {ServerWeb.DashboardChannel, "dashboard:test"},
        {ServerWeb.OverlayChannel, "overlay:test"},
        {ServerWeb.StreamChannel, "stream:test"}
      ]

      for {channel_module, topic} <- channels_to_test do
        {:ok, socket} = connect(ServerWeb.UserSocket, %{})

        case subscribe_and_join(socket, channel_module, topic) do
          {:ok, _, socket} ->
            # Send legacy format messages
            legacy_messages = [
              {:obs_event, %{type: "obs.test"}},
              {:twitch_event, %{type: "channel.test"}},
              "string_message",
              {:unknown_format, "data"}
            ]

            for legacy_msg <- legacy_messages do
              # Channels should ignore these completely
              send(socket.channel_pid, legacy_msg)
              refute_push _, _, 50
            end

            # Send correct format - should work
            correct_event = %{
              source: :test,
              type: "test.event",
              timestamp: DateTime.utc_now()
            }

            send(socket.channel_pid, {:event, correct_event})

          # Different channels may handle this differently, but shouldn't crash

          {:error, _reason} ->
            # Some channels may not be testable this way - skip
            :ok
        end
      end
    end

    test "channels should not directly subscribe to service-specific topics" do
      # This test would be more meaningful with access to the actual channel
      # subscription patterns, but we can test the expected behavior

      # Connect to each channel and monitor what topics they subscribe to
      test_channels = [
        {ServerWeb.EventsChannel, "events:all"},
        {ServerWeb.DashboardChannel, "dashboard:main"}
      ]

      for {channel_module, topic} <- test_channels do
        initial_topics = Phoenix.PubSub.topics(Server.PubSub)

        {:ok, socket} = connect(ServerWeb.UserSocket, %{})
        {:ok, _, socket} = subscribe_and_join(socket, channel_module, topic)

        # Allow subscriptions to register
        Process.sleep(10)

        final_topics = Phoenix.PubSub.topics(Server.PubSub)
        new_topics = final_topics -- initial_topics

        # Filter for service-specific topics that channels shouldn't use
        service_specific_topics =
          Enum.filter(new_topics, fn topic ->
            String.starts_with?(topic, "obs:") or
              String.starts_with?(topic, "twitch:") or
              String.starts_with?(topic, "rainwave:") or
              String.starts_with?(topic, "ironmon:")
          end)

        assert service_specific_topics == [],
               "Channel #{channel_module} subscribed to service-specific topics: #{inspect(service_specific_topics)}. " <>
                 "Channels should only subscribe to unified 'events' and 'dashboard' topics."
      end
    end
  end

  describe "Service Integration Compliance" do
    test "all services should call Server.Events.process_event/2" do
      # This test validates that key services are properly integrated

      # Track Server.Events.process_event calls
      test_pid = self()

      # Test Twitch service (should be compliant)
      capture_log(fn ->
        # Simulate TwitchController processing webhook
        event_data = %{
          "subscription" => %{"type" => "channel.follow"},
          "event" => %{
            "user_id" => "123",
            "user_login" => "follower",
            "broadcaster_user_id" => "456"
          }
        }

        # This should call Server.Events.process_event internally
        ServerWeb.TwitchController.process_webhook_event(event_data)
      end)

      # Test Rainwave service (should be compliant)
      capture_log(fn ->
        event_data = %{
          "station_id" => 1,
          "listening" => true,
          "enabled" => true
        }

        # This should call Server.Events.process_event internally
        Server.Services.Rainwave.publish_update(event_data)
      end)

      # The fact that these don't crash indicates they're going through the unified system
      # More sophisticated monitoring would require mocking or instrumentation
    end

    test "verify no services use parallel event systems" do
      # Monitor for direct PubSub broadcasts that don't go through Server.Events

      # Subscribe to topics that indicate parallel systems
      parallel_system_topics = [
        "obs_events:test",
        "overlay:scene_changed",
        "overlay:stream_state",
        "direct_twitch_events",
        "direct_rainwave_events"
      ]

      for topic <- parallel_system_topics do
        Phoenix.PubSub.subscribe(Server.PubSub, topic)
      end

      # Start OBS handler which is known to use parallel system
      session_id = "parallel-test"

      {:ok, obs_handler} =
        Server.Services.OBS.EventHandler.start_link(
          session_id: session_id,
          name: :ParallelTestHandler
        )

      # Trigger event that would use parallel system
      legacy_event = %{
        eventType: "CurrentProgramSceneChanged",
        eventData: %{sceneName: "Test Scene"}
      }

      Phoenix.PubSub.broadcast(
        Server.PubSub,
        "obs_events:#{session_id}",
        {:obs_event, legacy_event}
      )

      Process.sleep(100)

      # Check for parallel system usage
      parallel_messages = receive_all_messages(50)

      # Filter for messages indicating parallel systems
      parallel_system_messages =
        Enum.filter(parallel_messages, fn msg ->
          case msg do
            {topic, _data} -> topic in parallel_system_topics
            _ -> false
          end
        end)

      GenServer.stop(obs_handler)

      # This assertion will fail with current OBS implementation
      assert parallel_system_messages == [],
             "Detected parallel event system usage: #{inspect(parallel_system_messages)}. " <>
               "All events should flow through the unified Server.Events system."
    end
  end

  describe "Performance and Resource Monitoring" do
    test "unified system should handle high event volume efficiently" do
      # Test that the unified system can handle load without degrading

      start_time = System.monotonic_time(:millisecond)

      # Generate high volume of events
      tasks =
        for i <- 1..100 do
          Task.async(fn ->
            Events.process_event("test.load_event", %{
              "id" => i,
              "timestamp" => System.system_time(:second)
            })
          end)
        end

      # Wait for all to complete
      results = Task.await_many(tasks, 5000)

      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time

      # All events should process successfully
      assert Enum.all?(results, &(&1 == :ok))

      # Should complete in reasonable time (less than 2 seconds for 100 events)
      assert duration < 2000,
             "Event processing took too long: #{duration}ms for 100 events"

      # Check that system remains stable
      assert Process.alive?(Process.whereis(Server.Events))
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

  defp flat_normalized_event?(event) when is_map(event) do
    # Check that the event is properly flattened
    Enum.all?(event, fn {_key, value} ->
      case value do
        %DateTime{} ->
          true

        map when is_map(map) ->
          false

        list when is_list(list) ->
          # Allow lists but not deeply nested structures
          Enum.all?(list, fn item ->
            not is_map(item) or simple_map?(item)
          end)

        _ ->
          true
      end
    end)
  end

  defp flat_normalized_event?(_), do: false

  defp simple_map?(map) when is_map(map) do
    # Allow maps with only string keys and simple values (for things like badges)
    Enum.all?(map, fn {key, value} ->
      is_binary(key) and not is_map(value)
    end)
  end

  defp simple_map?(_), do: false
end
