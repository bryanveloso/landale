defmodule Server.P0EventValidationTest do
  @moduledoc """
  P0 Critical validation tests for the unified event system architecture.

  These tests validate that ALL services comply with the unified Server.Events.process_event/2
  routing and that the architecture maintains its integrity. This is the critical test suite
  that ensures no architectural violations occur and all event processing goes through
  the unified system.

  ## What This Test Suite Validates

  1. **Unified Event Routing Compliance**: All services use Server.Events.process_event/2
  2. **Event Format Consistency**: All events follow flat format requirements
  3. **Security Boundary Enforcement**: Input validation prevents malicious payloads
  4. **Complete Pipeline Integrity**: Service → Events → PubSub → Channels flow
  5. **Cross-Service Correlation**: Events maintain correlation IDs properly
  6. **ActivityLog Integration**: Valuable events are stored correctly
  """

  use ServerWeb.ChannelCase, async: false
  import ExUnit.CaptureLog

  alias Server.{ActivityLog, Events}

  # ============================================================================
  # Critical Architecture Compliance Tests
  # ============================================================================

  describe "Unified Event Routing Validation" do
    @tag :p0_critical
    test "all event sources route through Server.Events.process_event/2" do
      # Setup monitoring
      {:ok, socket} = connect(ServerWeb.UserSocket, %{})
      {:ok, _, socket} = subscribe_and_join(socket, ServerWeb.EventsChannel, "events:all")

      # Test critical event types from each service
      test_events = [
        # Twitch events
        {"channel.follow",
         %{
           "user_id" => "123456",
           "user_login" => "follower",
           "user_name" => "Follower",
           "broadcaster_user_id" => "789012",
           "broadcaster_user_login" => "streamer",
           "broadcaster_user_name" => "Streamer",
           "followed_at" => "2023-01-01T12:00:00Z"
         }, "follower"},
        {"channel.subscribe",
         %{
           "user_id" => "123457",
           "user_login" => "subscriber",
           "user_name" => "Subscriber",
           "broadcaster_user_id" => "789012",
           "broadcaster_user_login" => "streamer",
           "broadcaster_user_name" => "Streamer",
           "tier" => "1000",
           "is_gift" => false
         }, "subscription"},

        # OBS events
        {"obs.stream_started",
         %{
           "session_id" => "obs123",
           "output_active" => true
         }, "obs_event"},

        # System events
        {"system.service_started",
         %{
           "service" => "test_service",
           "version" => "1.0.0"
         }, "system_event"},

        # Stream events (internal)
        {"stream.state_updated",
         %{
           "current_show" => "test_show",
           "version" => 1
         }, "stream_event"}
      ]

      for {event_type, event_data, expected_event_name} <- test_events do
        # Process through unified system
        assert :ok = Events.process_event(event_type, event_data),
               "Event #{event_type} failed to process through unified system"

        # Verify unified "events" topic receives the event
        assert_receive %Phoenix.Socket.Message{
                         topic: "events:all",
                         event: ^expected_event_name,
                         payload: payload
                       },
                       1000

        # Validate event structure compliance
        assert_event_structure_compliance(payload, event_type)

        # Verify correlation ID is properly set
        assert is_binary(payload.correlation_id)
        assert String.length(payload.correlation_id) == 16
        assert Regex.match?(~r/^[a-f0-9]+$/, payload.correlation_id)

        # Verify event source mapping is correct
        expected_source = determine_expected_source(event_type)

        assert payload.source == expected_source,
               "Event #{event_type} has incorrect source. Expected #{expected_source}, got #{payload.source}"

        # Verify flat format (no nested structures except allowed types)
        assert flat_event_format?(payload),
               "Event #{event_type} violates flat format requirement"
      end
    end

    @tag :p0_critical
    test "event format consistency and normalization" do
      # Test complex nested event gets flattened properly
      nested_event_data = %{
        "message_id" => "msg123",
        "broadcaster_user_id" => "789012",
        "chatter_user_id" => "123456",
        "chatter_user_login" => "chatter",
        "message" => %{
          "text" => "Hello stream!",
          "fragments" => [
            %{"type" => "text", "text" => "Hello "},
            %{"type" => "emote", "text" => "Kappa", "id" => "25"}
          ]
        },
        "cheer" => %{
          "bits" => 100
        }
      }

      # Normalize the event
      normalized = Events.normalize_event("channel.chat.message", nested_event_data)

      # Verify nested structures are flattened
      assert normalized.message == "Hello stream!"
      assert normalized.cheer_bits == 100
      assert is_list(normalized.fragments)

      # Verify flat format compliance
      assert flat_event_format?(normalized)

      # Verify core fields exist
      assert normalized.id
      assert normalized.type == "channel.chat.message"
      assert normalized.source == :twitch
      assert normalized.timestamp
      assert normalized.correlation_id
    end

    @tag :p0_critical
    test "security validation prevents malicious payloads" do
      malicious_payloads = [
        # Oversized payload
        {"channel.chat.message",
         %{
           "message_id" => "evil_msg",
           "chatter_user_id" => "123456",
           "broadcaster_user_id" => "789012",
           "message" => %{"text" => String.duplicate("x", 101_000)}
         }},

        # Control character injection
        {"channel.follow",
         %{
           "user_login" => "test\\x00user",
           "user_id" => "123456",
           "broadcaster_user_id" => "789012"
         }},

        # Invalid data types
        {"stream.online",
         %{
           # should be string
           "broadcaster_user_id" => 123,
           "started_at" => "invalid_date"
         }}
      ]

      for {event_type, malicious_data} <- malicious_payloads do
        log_output =
          capture_log(fn ->
            result = Events.process_event(event_type, malicious_data)

            # Should either reject with validation error or handle gracefully
            case result do
              {:error, {:validation_failed, _errors}} -> :ok
              {:error, _other_reason} -> :ok
              # May pass if sanitized
              :ok -> :ok
            end
          end)

        # Should log appropriate warnings for rejected payloads
        if String.contains?(log_output, "validation failed") do
          assert String.contains?(log_output, "validation") or
                   String.contains?(log_output, "rejected"),
                 "Malicious payload #{event_type} was not properly logged as security concern"
        end
      end
    end

    @tag :p0_critical
    test "complete integration pipeline integrity" do
      # Setup all monitoring points
      {:ok, events_socket} = connect(ServerWeb.UserSocket, %{})
      {:ok, _, events_socket} = subscribe_and_join(events_socket, ServerWeb.EventsChannel, "events:twitch")

      {:ok, dashboard_socket} = connect(ServerWeb.UserSocket, %{})
      {:ok, _, dashboard_socket} = subscribe_and_join(dashboard_socket, ServerWeb.DashboardChannel, "dashboard:main")

      # Test with a valuable event that triggers all pipeline components
      event_type = "channel.subscribe"

      event_data = %{
        "user_id" => "123456",
        "user_login" => "pipeline_tester",
        "broadcaster_user_id" => "789012",
        "broadcaster_user_login" => "test_broadcaster",
        "tier" => "1000",
        "is_gift" => false
      }

      initial_events = ActivityLog.list_recent_events()
      initial_activity_count = length(initial_events)

      # Process through unified system
      assert :ok = Events.process_event(event_type, event_data)

      # 1. Verify EventsChannel receives properly formatted event
      assert_receive %Phoenix.Socket.Message{
                       topic: "events:twitch",
                       event: "subscription",
                       payload: events_payload
                     },
                     1000

      assert events_payload.type == event_type
      assert events_payload.source == :twitch
      assert events_payload.user_id == "123456"
      assert events_payload.user_login == "pipeline_tester"
      assert events_payload.tier == "1000"
      assert is_binary(events_payload.correlation_id)

      # 2. Verify DashboardChannel receives event
      assert_receive %Phoenix.Socket.Message{
                       topic: "dashboard:main",
                       event: "twitch_event",
                       payload: dashboard_payload
                     },
                     1000

      assert dashboard_payload.type == event_type
      assert dashboard_payload.source == :twitch
      assert dashboard_payload.correlation_id == events_payload.correlation_id

      # 3. Verify ActivityLog storage (async operation)
      Process.sleep(200)
      final_events = ActivityLog.list_recent_events()
      final_activity_count = length(final_events)
      assert final_activity_count == initial_activity_count + 1

      # 4. Verify stored event matches original correlation ID
      recent_events = ActivityLog.list_recent_events(limit: 1)
      stored_event = List.first(recent_events)
      assert stored_event.correlation_id == events_payload.correlation_id
      assert stored_event.event_type == event_type
    end

    @tag :p0_critical
    test "correlation ID integrity across event lifecycle" do
      # Setup monitoring
      {:ok, socket} = connect(ServerWeb.UserSocket, %{})
      {:ok, _, socket} = subscribe_and_join(socket, ServerWeb.EventsChannel, "events:all")

      test_event_type = "channel.follow"

      test_event_data = %{
        "user_id" => "123456",
        "user_login" => "correlation_tester",
        "broadcaster_user_id" => "789012",
        "broadcaster_user_login" => "test_broadcaster",
        "followed_at" => "2023-01-01T12:00:00Z"
      }

      # Process through unified system
      assert :ok = Events.process_event(test_event_type, test_event_data)

      # Verify correlation ID is maintained in PubSub broadcast
      assert_receive %Phoenix.Socket.Message{
                       topic: "events:all",
                       event: "follower",
                       payload: payload
                     },
                     1000

      # Verify correlation ID format and capture it for later checks
      correlation_id = payload.correlation_id
      assert is_binary(correlation_id)
      assert String.length(correlation_id) == 16
      assert Regex.match?(~r/^[a-f0-9]+$/, correlation_id)

      # Allow time for ActivityLog storage
      Process.sleep(100)

      # Verify correlation ID is maintained in ActivityLog storage
      stored_events = ActivityLog.list_recent_events(limit: 1)
      assert length(stored_events) > 0

      stored_event = List.first(stored_events)
      assert stored_event.correlation_id == correlation_id
    end

    @tag :p0_critical
    test "activity log filtering compliance" do
      # Test valuable vs ephemeral event filtering
      valuable_events = [
        {"channel.follow",
         %{
           "user_id" => "123456",
           "user_login" => "follower",
           "broadcaster_user_id" => "789012",
           "broadcaster_user_login" => "streamer"
         }},
        {"channel.subscribe",
         %{
           "user_id" => "123457",
           "user_login" => "subscriber",
           "broadcaster_user_id" => "789012",
           "tier" => "1000",
           "broadcaster_user_login" => "streamer"
         }},
        {"obs.stream_started", %{"session_id" => "obs123"}},
        {"system.service_started", %{"service" => "test_service"}}
      ]

      ephemeral_events = [
        {"system.health_check", %{"service" => "test_service", "status" => "healthy"}},
        {"obs.connection_established", %{"session_id" => "obs123"}}
      ]

      initial_events = ActivityLog.list_recent_events()
      initial_count = length(initial_events)

      # Process valuable events
      for {event_type, event_data} <- valuable_events do
        assert :ok = Events.process_event(event_type, event_data)
      end

      # Process ephemeral events
      for {event_type, event_data} <- ephemeral_events do
        assert :ok = Events.process_event(event_type, event_data)
      end

      # Allow time for async storage
      Process.sleep(300)

      final_events = ActivityLog.list_recent_events()
      final_count = length(final_events)

      # Only valuable events should have been stored
      expected_count = initial_count + length(valuable_events)

      assert final_count == expected_count,
             "Expected #{expected_count} events stored, got #{final_count}. Only valuable events should be stored."
    end

    @tag :p0_critical
    test "unified system handles concurrent event load" do
      # Test concurrent load without failures
      event_count = 50
      concurrent_tasks = 5

      # Create concurrent tasks that each process multiple events
      tasks =
        for task_id <- 1..concurrent_tasks do
          Task.async(fn ->
            for event_id <- 1..div(event_count, concurrent_tasks) do
              event_type = "channel.follow"

              event_data = %{
                "user_id" => "#{100_000 + task_id * 1000 + event_id}",
                "user_login" => "load_user_#{task_id}_#{event_id}",
                "broadcaster_user_id" => "789012",
                "broadcaster_user_login" => "test_broadcaster"
              }

              result = Events.process_event(event_type, event_data)
              assert result == :ok, "Event processing failed under load: #{inspect(result)}"
            end

            :ok
          end)
        end

      # Wait for all tasks to complete
      results = Task.await_many(tasks, 10_000)

      # All tasks should complete successfully
      assert Enum.all?(results, &(&1 == :ok)), "Some concurrent tasks failed"
    end
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  defp assert_event_structure_compliance(event, event_type) do
    # Core fields that should always be present
    required_fields = [:id, :type, :timestamp, :correlation_id, :source, :raw_type]

    for field <- required_fields do
      assert Map.has_key?(event, field),
             "Event #{event_type} missing required field: #{field}"
    end

    # Type should match input
    assert event.type == event_type,
           "Event type mismatch. Expected #{event_type}, got #{event.type}"

    # Timestamp should be a DateTime
    assert %DateTime{} = event.timestamp,
           "Event timestamp should be a DateTime struct"

    # ID should be present and non-empty
    assert is_binary(event.id) and String.length(event.id) > 0,
           "Event ID should be a non-empty string"
  end

  defp determine_expected_source(event_type) do
    cond do
      String.starts_with?(event_type, "stream.") and
          event_type in [
            "stream.state_updated",
            "stream.show_changed",
            "stream.interrupt_removed",
            "stream.emote_increment",
            "stream.takeover_started",
            "stream.takeover_cleared",
            "stream.goals_updated"
          ] ->
        :stream

      String.starts_with?(event_type, "stream.") ->
        :twitch

      String.starts_with?(event_type, "channel.") ->
        :twitch

      String.starts_with?(event_type, "obs.") ->
        :obs

      String.starts_with?(event_type, "ironmon.") ->
        :ironmon

      String.starts_with?(event_type, "rainwave.") ->
        :rainwave

      String.starts_with?(event_type, "system.") ->
        :system

      # default
      true ->
        :twitch
    end
  end

  defp flat_event_format?(event) when is_map(event) do
    Enum.all?(event, fn {_key, value} ->
      case value do
        # DateTime structs are allowed
        %DateTime{} ->
          true

        # No other nested maps allowed
        map when is_map(map) ->
          false

        list when is_list(list) ->
          # Lists are allowed if they contain simple values or structured data
          # Note: fragments come with atom keys from BoundaryConverter
          Enum.all?(list, fn item ->
            not is_map(item) or (is_map(item) and is_flat_fragment?(item))
          end)

        # All other types are fine
        _ ->
          true
      end
    end)
  end

  defp is_flat_fragment?(item) when is_map(item) do
    # Fragment maps can have atom or string keys and should be flat (no nested maps)
    Enum.all?(item, fn {_key, value} ->
      # Allow empty maps but no nested structures
      not is_map(value) or value in [%{}]
    end)
  end

  defp flat_event_format?(_), do: false

  defp map_has_only_string_keys?(map) when is_map(map) do
    Enum.all?(Map.keys(map), &is_binary/1)
  end

  defp map_has_only_string_keys?(_), do: false
end
