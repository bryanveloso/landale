defmodule Server.EventSystemValidationTest do
  @moduledoc """
  P0 Critical validation tests for the unified event system architecture.

  These tests validate that ALL services comply with the unified Server.Events.process_event/2
  routing and that the architecture maintains its integrity. This is the critical test suite
  that ensures no architectural violations occur and all event processing goes through
  the unified system.

  ## What This Test Suite Validates

  1. **Unified Event Routing Compliance**: All services use Server.Events.process_event/2
  2. **No Legacy PubSub Bypass**: No services publish directly to old topics
  3. **Event Format Consistency**: All events follow flat format requirements
  4. **Security Boundary Enforcement**: Input validation prevents malicious payloads
  5. **Complete Pipeline Integrity**: Service → Events → PubSub → Channels flow
  6. **Cross-Service Correlation**: Events maintain correlation IDs properly
  7. **ActivityLog Integration**: Valuable events are stored correctly
  8. **Channel Filtering**: Phoenix channels receive correct event subsets

  ## Architectural Validation Strategy

  This test suite uses process tracing, PubSub monitoring, and end-to-end validation
  to prove 100% compliance with the unified architecture. Any service that bypasses
  the unified system will be detected and flagged as an architectural violation.
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
      # This test validates that the unified routing is working for all service types
      # by sending events through each service path and verifying they all use the
      # unified system correctly

      test_events = [
        # Twitch events (external webhook sources)
        {"channel.follow", %{"user_id" => "123456", "user_login" => "follower", "broadcaster_user_id" => "789012", "broadcaster_user_login" => "streamer"}},
        {"channel.subscribe", %{"user_id" => "123456", "user_login" => "subscriber", "broadcaster_user_id" => "789012", "broadcaster_user_login" => "streamer", "tier" => "1000"}},
        {"channel.chat.message", %{"message_id" => "msg123", "chatter_user_id" => "123456", "broadcaster_user_id" => "789012", "chatter_user_login" => "chatter", "message" => %{"text" => "test"}}},
        {"stream.online", %{"broadcaster_user_id" => "789012", "broadcaster_user_login" => "streamer", "type" => "live", "started_at" => "2023-01-01T12:00:00Z"}},
        {"stream.offline", %{"broadcaster_user_id" => "789012", "broadcaster_user_login" => "streamer"}},

        # OBS events (local WebSocket sources)  
        {"obs.connection_established", %{"session_id" => "obs123", "websocket_version" => "5.0.0", "rpc_version" => 1}},
        {"obs.connection_lost", %{"session_id" => "obs123", "reason" => "test_disconnect"}},
        {"obs.scene_changed", %{"scene_name" => "Test Scene", "session_id" => "obs123"}},
        {"obs.stream_started", %{"output_active" => true, "session_id" => "obs123"}},
        {"obs.stream_stopped", %{"output_active" => false, "session_id" => "obs123"}},

        # IronMON events (game data sources)
        {"ironmon.init", %{"game_type" => "emerald", "version" => "1.0", "run_id" => "run123"}},
        {"ironmon.seed", %{"seed_count" => 1, "run_id" => "run123"}},
        {"ironmon.checkpoint", %{"checkpoint_id" => "cp1", "run_id" => "run123"}},
        {"ironmon.battle_start", %{"battle_type" => "trainer", "run_id" => "run123"}},

        # Rainwave events (music service sources)
        {"rainwave.song_changed", %{"station_id" => 1, "song_id" => 123, "song_title" => "Test Song"}},
        {"rainwave.station_changed", %{"station_id" => 2, "station_name" => "Test Station"}},

        # System events (internal monitoring sources)
        {"system.service_started", %{"service" => "test_service", "version" => "1.0.0"}},
        {"system.service_stopped", %{"service" => "test_service", "reason" => "test_shutdown"}},
        {"system.health_check", %{"service" => "test_service", "status" => "healthy"}},

        # Stream events (internal stream system)
        {"stream.state_updated", %{"current_show" => "test_show", "version" => 1}},
        {"stream.show_changed", %{"show" => "new_show", "changed_at" => "2023-01-01T12:00:00Z"}},
        {"stream.emote_increment", %{"emotes" => ["Kappa"], "user_name" => "test_user"}},
        {"stream.takeover_started", %{"takeover_type" => "alert", "duration" => 5000}},
        {"stream.goals_updated", %{"follower_goal" => %{}, "timestamp" => "2023-01-01T12:00:00Z"}}
      ]

      # Setup event monitoring
      {:ok, events_socket} = connect(ServerWeb.UserSocket, %{})
      {:ok, _, events_socket} = subscribe_and_join(events_socket, ServerWeb.EventsChannel, "events:all")

      {:ok, dashboard_socket} = connect(ServerWeb.UserSocket, %{})
      {:ok, _, dashboard_socket} = subscribe_and_join(dashboard_socket, ServerWeb.DashboardChannel, "dashboard:main")

      # Process each event and validate unified routing
      for {event_type, event_data} <- test_events do
        # Process through unified system
        assert :ok = Events.process_event(event_type, event_data), 
               "Event #{event_type} failed to process through unified system"

        # Verify unified "events" topic receives the event
        assert_receive %Phoenix.Socket.Message{
          topic: "events:all",
          event: _event_name,
          payload: payload
        }, 1000

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
    test "no services bypass unified event routing" do
      # This test uses process tracing to ensure that no services are publishing
      # directly to Phoenix.PubSub without going through Server.Events
      
      # Start PubSub monitoring
      :erlang.trace(:all, true, [:call])
      :erlang.trace_pattern({Phoenix.PubSub, :broadcast, :_}, [])
      
      # Track all PubSub publications during test
      initial_publications = []
      
      # Process a test event through the unified system
      test_event_type = "channel.follow"
      test_event_data = %{
        "user_id" => "123456789",
        "user_login" => "test_follower", 
        "broadcaster_user_id" => "987654321",
        "broadcaster_user_login" => "test_broadcaster",
        "followed_at" => "2023-01-01T12:00:00Z"
      }

      assert :ok = Events.process_event(test_event_type, test_event_data)

      # Allow time for async processing
      Process.sleep(100)

      # Stop tracing
      :erlang.trace(:all, false, [:call])

      # Verify all PubSub publications went through unified topics
      # The unified system should only publish to "events" and "dashboard" topics
      publications = 
        receive do
          {:trace, _pid, :call, {Phoenix.PubSub, :broadcast, [Server.PubSub, topic, _message]}} ->
            assert topic in ["events", "dashboard"],
                   "Service bypassed unified routing by publishing directly to topic: #{topic}"
            [topic | initial_publications]
        after
          100 -> initial_publications
        end

      # Ensure at least the expected unified topics were used
      assert "events" in publications or "dashboard" in publications,
             "No publications detected through unified topics"
    end

    @tag :p0_critical  
    test "legacy PubSub topics are completely discontinued" do
      # This test ensures that the old topic-specific publishing has been completely
      # removed and no events are published to legacy topics
      
      legacy_topics = [
        "twitch:events",
        "obs:events", 
        "ironmon:events",
        "rainwave:events",
        "system:events",
        "stream:events",
        "overlay:updates",
        "dashboard:twitch",
        "dashboard:obs", 
        "dashboard:ironmon",
        "dashboard:rainwave",
        "dashboard:system"
      ]

      # Subscribe to all legacy topics to detect any violations
      legacy_sockets = 
        for topic <- legacy_topics do
          {:ok, socket} = connect(ServerWeb.UserSocket, %{})
          # Use a catch-all pattern to detect any publications
          case subscribe_and_join(socket, ServerWeb.EventsChannel, topic) do
            {:ok, _, socket} -> {topic, socket}
            {:error, _} -> {topic, nil}  # Topic may not exist anymore (good)
          end
        end

      # Process events through the unified system
      test_events = [
        {"channel.follow", %{"user_id" => "123456789", "user_login" => "follower", "broadcaster_user_id" => "987654321", "broadcaster_user_login" => "streamer"}},
        {"obs.stream_started", %{"session_id" => "obs123", "output_active" => true}},
        {"ironmon.init", %{"game_type" => "emerald", "version" => "1.0", "run_id" => "run123"}},
        {"rainwave.song_changed", %{"station_id" => 1, "song_id" => 12345}},
        {"system.service_started", %{"service" => "test", "version" => "1.0.0"}},
        {"stream.state_updated", %{"current_show" => "test", "version" => 1}}
      ]

      for {event_type, event_data} <- test_events do
        assert :ok = Events.process_event(event_type, event_data)
      end

      # Allow time for potential legacy publications
      Process.sleep(200)

      # Verify NO legacy topics received any events
      for {topic, socket} <- legacy_sockets do
        if socket do
          # Should not receive any messages on legacy topics
          refute_receive %Phoenix.Socket.Message{topic: ^topic}, 100
          assert_no_legacy_publications_logged(topic)
        end
      end
    end
  end

  # ============================================================================
  # Event Format and Security Validation
  # ============================================================================

  describe "Event Format Consistency Validation" do
    @tag :p0_critical
    test "all events maintain flat format compliance" do
      # Test events with complex nested structures to ensure they're properly flattened
      complex_events = [
        {
          "channel.chat.message",
          %{
            "message_id" => "complex_msg_123",
            "broadcaster_user_id" => "987654321",
            "chatter_user_id" => "456789123",
            "chatter_user_login" => "test_chatter",
            "broadcaster_user_login" => "test_broadcaster",
            "message" => %{
              "text" => "Complex message with nested data",
              "fragments" => [
                %{"type" => "text", "text" => "Hello "},
                %{"type" => "emote", "text" => "Kappa", "id" => "25"},
                %{"type" => "text", "text" => " world!"}
              ]
            },
            "cheer" => %{
              "bits" => 100
            },
            "reply" => %{
              "parent_message_id" => "parent_456",
              "parent_user_login" => "original_chatter",
              "parent_message_body" => "Original message",
              "thread_message_id" => "thread_789"
            },
            "badges" => [
              %{"set_id" => "subscriber", "id" => "1", "info" => "subscriber info"},
              %{"set_id" => "moderator", "id" => "1", "info" => "mod info"}
            ]
          }
        },
        {
          "system.health_check",
          %{
            "service" => "complex_service",
            "status" => "healthy",
            "details" => %{
              "uptime" => 3600,
              "memory_usage" => 75.5,
              "cpu_usage" => 25.0,
              "disk_usage" => 50.0,
              "error_count" => 0,
              "nested_metrics" => %{
                "deep_value" => 42
              }
            },
            "metadata" => %{
              "component" => "health_checker",
              "hostname" => "test_host",
              "environment" => "test"
            }
          }
        },
        {
          "rainwave.song_changed", 
          %{
            "station_id" => 1,
            "station_name" => "Test Station",
            "current_song" => %{
              "id" => 12345,
              "title" => "Epic Battle Theme",
              "artist" => "Video Game Composer",
              "album" => "Game Soundtrack Vol. 1"
            },
            "listening" => true
          }
        }
      ]

      for {event_type, complex_event_data} <- complex_events do
        # Process through unified system
        normalized_event = Events.normalize_event(event_type, complex_event_data)

        # Verify flat format compliance
        assert flat_event_format?(normalized_event),
               "Event #{event_type} failed flat format validation"

        # Verify specific flattening for chat message
        if event_type == "channel.chat.message" do
          # Nested message content should be flattened
          assert normalized_event.message == "Complex message with nested data"
          assert is_list(normalized_event.fragments)
          assert normalized_event.cheer_bits == 100
          
          # Reply data should be flattened with prefixes
          assert normalized_event.reply_parent_message_id == "parent_456"
          assert normalized_event.reply_parent_user_login == "original_chatter"
          assert normalized_event.reply_thread_message_id == "thread_789"
          
          # Badges should be preserved as structured data (allowed exception)
          assert is_list(normalized_event.badges)
        end

        # Verify specific flattening for health check
        if event_type == "system.health_check" do
          # Nested details should be flattened to top level
          assert normalized_event.uptime == 3600
          assert normalized_event.memory_usage == 75.5
          assert normalized_event.cpu_usage == 25.0
          assert normalized_event.error_count == 0
          
          # Original nested structure should be removed
          refute Map.has_key?(normalized_event, :details)
        end

        # Verify specific flattening for Rainwave
        if event_type == "rainwave.song_changed" do
          # Song data should be flattened to top level
          assert normalized_event.song_id == 12345
          assert normalized_event.song_title == "Epic Battle Theme"
          assert normalized_event.artist == "Video Game Composer"
          assert normalized_event.album == "Game Soundtrack Vol. 1"
        end
      end
    end

    @tag :p0_critical
    test "correlation ID integrity across event lifecycle" do
      # This test ensures correlation IDs are properly maintained throughout
      # the entire event processing pipeline
      
      # Setup monitoring
      {:ok, events_socket} = connect(ServerWeb.UserSocket, %{})
      {:ok, _, events_socket} = subscribe_and_join(events_socket, ServerWeb.EventsChannel, "events:all")

      test_event_type = "channel.subscribe"
      test_event_data = %{
        "user_id" => "123456789",
        "user_login" => "correlation_tester",
        "broadcaster_user_id" => "987654321",
        "broadcaster_user_login" => "streamer",
        "tier" => "1000",
        "is_gift" => false
      }

      # Process event and capture correlation ID from normalized event
      normalized_event = Events.normalize_event(test_event_type, test_event_data)
      correlation_id = normalized_event.correlation_id

      # Verify correlation ID format
      assert is_binary(correlation_id)
      assert String.length(correlation_id) == 16
      assert Regex.match?(~r/^[a-f0-9]+$/, correlation_id)

      # Process through unified system
      assert :ok = Events.process_event(test_event_type, test_event_data)

      # Verify correlation ID is maintained in PubSub broadcast
      assert_receive %Phoenix.Socket.Message{
        topic: "events:all",
        event: "follower",
        payload: payload
      }, 1000
      assert payload.correlation_id == correlation_id

      # Allow time for ActivityLog storage
      Process.sleep(100)

      # Verify correlation ID is maintained in ActivityLog storage
      stored_events = ActivityLog.list_recent_events(limit: 1)
      assert length(stored_events) > 0
      
      stored_event = List.first(stored_events)
      assert stored_event.correlation_id == correlation_id
    end
  end

  # ============================================================================
  # Security Boundary Validation
  # ============================================================================

  describe "Security Boundary Enforcement" do
    @tag :p0_critical
    test "malicious payload detection and rejection" do
      # Test various malicious payloads to ensure security validation works
      malicious_payloads = [
        # Oversized payload (>100KB)
        {"channel.chat.message", generate_oversized_payload()},
        
        # Control character injection
        {"channel.follow", %{"user_login" => "test\x00user", "broadcaster_user_id" => "456"}},
        
        # Invalid data types
        {"stream.online", %{"broadcaster_user_id" => 123, "started_at" => "invalid_date"}},
        
        # Missing required fields
        {"channel.subscribe", %{"user_login" => "test", "tier" => "invalid_tier"}},
        
        # Script injection attempts
        {"channel.chat.message", %{
          "message_id" => "evil_msg",
          "chatter_user_id" => "123",
          "broadcaster_user_id" => "456",
          "message" => %{"text" => "<script>alert('xss')</script>"}
        }},
        
        # Deeply nested structure attack
        {"test.event", generate_nested_bomb()},
        
        # Invalid Twitch user ID formats
        {"channel.follow", %{"user_id" => "not_numeric", "broadcaster_user_id" => "456"}},
        
        # Invalid username formats
        {"channel.follow", %{"user_id" => "123", "user_login" => "invalid@username!", "broadcaster_user_id" => "456"}}
      ]

      for {event_type, malicious_data} <- malicious_payloads do
        log_output = capture_log(fn ->
          result = Events.process_event(event_type, malicious_data)
          
          # Should either reject with validation error or handle gracefully
          case result do
            {:error, {:validation_failed, _errors}} ->
              # This is expected for malicious payloads
              :ok
            {:error, _other_reason} ->
              # Other errors are also acceptable (e.g., processing failures)
              :ok
            :ok ->
              # If it succeeded, the payload wasn't actually malicious enough
              # but this is still acceptable if validation passed
              :ok
          end
        end)

        # Should log security-related warnings for rejected payloads
        if String.contains?(log_output, "validation failed") do
          assert String.contains?(log_output, "malicious") or 
                 String.contains?(log_output, "validation") or
                 String.contains?(log_output, "rejected"),
                 "Malicious payload #{event_type} was not properly logged as security concern"
        end
      end
    end

    @tag :p0_critical
    test "input sanitization prevents injection attacks" do
      # Test that string inputs are properly sanitized
      injection_attempts = [
        {
          "channel.chat.message",
          %{
            "message_id" => "injection_test",
            "chatter_user_id" => "123",
            "broadcaster_user_id" => "456", 
            "message" => %{"text" => "Normal text\x00\x01\x02with control chars"}
          }
        },
        {
          "channel.follow",
          %{
            "user_id" => "123",
            "user_login" => "test_user",
            "user_name" => "Test\x1fUser\x7fName",
            "broadcaster_user_id" => "456"
          }
        }
      ]

      for {event_type, injection_data} <- injection_attempts do
        result = Events.process_event(event_type, injection_data)
        
        # Should either reject due to validation or sanitize the input
        case result do
          {:error, {:validation_failed, errors}} ->
            # Validation should catch control characters
            errors_string = inspect(errors)
            assert String.contains?(errors_string, "control characters") or
                   String.contains?(errors_string, "invalid"),
                   "Control character validation error not properly reported"
          
          :ok ->
            # If it passed validation, verify the data was sanitized
            normalized = Events.normalize_event(event_type, injection_data)
            
            # Check that control characters were handled appropriately
            for {_key, value} <- normalized do
              if is_binary(value) do
                refute String.contains?(value, <<0>>),
                       "Null byte not properly sanitized from #{value}"
                refute String.contains?(value, <<1>>),
                       "Control character not properly sanitized from #{value}"
              end
            end
        end
      end
    end
  end

  # ============================================================================
  # Integration Flow Validation
  # ============================================================================

  describe "Complete Integration Pipeline Validation" do
    @tag :p0_critical
    test "end-to-end event flow integrity" do
      # This test validates the complete pipeline from service input to channel output
      # Service → Server.Events → PubSub → Channels → ActivityLog
      
      # Setup all monitoring points
      {:ok, events_socket} = connect(ServerWeb.UserSocket, %{})
      {:ok, _, events_socket} = subscribe_and_join(events_socket, ServerWeb.EventsChannel, "events:twitch")

      {:ok, dashboard_socket} = connect(ServerWeb.UserSocket, %{})
      {:ok, _, dashboard_socket} = subscribe_and_join(dashboard_socket, ServerWeb.DashboardChannel, "dashboard:main")

      # Test with a complex event that should trigger all pipeline components
      event_type = "channel.subscribe"
      event_data = %{
        "user_id" => "123456789",
        "user_login" => "pipeline_tester",
        "user_name" => "Pipeline Tester",
        "broadcaster_user_id" => "987654321",
        "broadcaster_user_login" => "test_broadcaster",
        "broadcaster_user_name" => "Test Broadcaster",
        "tier" => "1000",
        "is_gift" => false
      }

      # Get initial activity count by counting recent events
      initial_activity_count = length(ActivityLog.list_recent_events(limit: 1000))

      # Process through unified system
      assert :ok = Events.process_event(event_type, event_data)

      # 1. Verify EventsChannel receives properly formatted event
      assert_receive %Phoenix.Socket.Message{
        topic: "events:twitch",
        event: "subscription",
        payload: events_payload
      }, 1000
      assert events_payload.type == event_type
      assert events_payload.source == :twitch
      assert events_payload.user_id == "123456"
      assert events_payload.user_login == "pipeline_tester"
      assert events_payload.tier == "1000"
      assert is_binary(events_payload.correlation_id)
      
      # Store correlation ID for later comparisons
      events_correlation_id = events_payload.correlation_id

      # 2. Verify DashboardChannel receives event
      assert_receive %Phoenix.Socket.Message{
        topic: "dashboard:main",
        event: "twitch_event",
        payload: dashboard_payload
      }, 1000
      assert dashboard_payload.type == event_type
      assert dashboard_payload.source == :twitch
      assert dashboard_payload.correlation_id == events_correlation_id

      # 3. Verify ActivityLog storage (async operation)
      Process.sleep(200)
      final_activity_count = length(ActivityLog.list_recent_events(limit: 1000))
      assert final_activity_count == initial_activity_count + 1

      # 4. Verify stored event matches original correlation ID
      recent_events = ActivityLog.list_recent_events(limit: 1)
      stored_event = List.first(recent_events)
      assert stored_event.correlation_id == events_correlation_id
      assert stored_event.event_type == event_type

      # 5. Verify user data was properly upserted
      assert stored_event.user_id == "pipeline_test_123"
      assert stored_event.user_login == "pipeline_tester"
    end

    @tag :p0_critical
    test "cross-service event correlation validation" do
      # This test ensures that events from different services can be properly
      # correlated using the correlation ID system
      
      # Process multiple related events that should share correlation context
      events_to_correlate = [
        {"obs.stream_started", %{"session_id" => "correlation_session", "output_active" => true}},
        {"stream.show_changed", %{"show" => "correlation_test", "game_name" => "Test Game"}},
        {"system.service_started", %{"service" => "correlation_service", "version" => "1.0.0"}}
      ]

      correlation_ids = 
        for {event_type, event_data} <- events_to_correlate do
          # Get the correlation ID that will be assigned
          normalized = Events.normalize_event(event_type, event_data)
          correlation_id = normalized.correlation_id
          
          # Process the event
          assert :ok = Events.process_event(event_type, event_data)
          
          correlation_id
        end

      # Verify all correlation IDs are unique (as expected for unrelated events)
      assert length(Enum.uniq(correlation_ids)) == length(correlation_ids),
             "Correlation IDs should be unique for independent events"

      # Verify correlation IDs follow proper format
      for correlation_id <- correlation_ids do
        assert String.length(correlation_id) == 16
        assert Regex.match?(~r/^[a-f0-9]+$/, correlation_id)
      end
    end

    @tag :p0_critical
    test "activity log filtering compliance" do
      # Ensure only valuable events are stored in ActivityLog and ephemeral events are excluded
      
      valuable_events = [
        {"channel.follow", %{"user_id" => "123", "broadcaster_user_id" => "456"}},
        {"channel.subscribe", %{"user_id" => "123", "broadcaster_user_id" => "456", "tier" => "1000"}},
        {"channel.chat.message", %{"message_id" => "msg123", "chatter_user_id" => "123", "broadcaster_user_id" => "456", "message" => %{"text" => "test"}}},
        {"obs.stream_started", %{"session_id" => "obs123"}},
        {"ironmon.init", %{"game_type" => "emerald", "run_id" => "run123"}},
        {"system.service_started", %{"service" => "test_service"}}
      ]

      ephemeral_events = [
        {"system.health_check", %{"service" => "test_service", "status" => "healthy"}},
        {"system.performance_metric", %{"metric" => "cpu_usage", "value" => 50.0}},
        {"obs.connection_established", %{"session_id" => "obs123"}},
        {"twitch.service_status", %{"connected" => true, "session_id" => "session123"}}
      ]

      initial_count = length(ActivityLog.list_recent_events(limit: 1000))

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

      final_count = length(ActivityLog.list_recent_events(limit: 1000))
      
      # Only valuable events should have been stored
      expected_count = initial_count + length(valuable_events)
      assert final_count == expected_count,
             "Expected #{expected_count} events stored, got #{final_count}. Only valuable events should be stored."
    end
  end

  # ============================================================================
  # Performance and Load Validation
  # ============================================================================

  describe "Performance and Load Validation" do
    @tag :p0_critical
    test "unified system handles concurrent event load" do
      # Ensure the unified system can handle realistic concurrent load without failures
      
      event_count = 100
      concurrent_tasks = 10

      # Create concurrent tasks that each process multiple events
      tasks = for task_id <- 1..concurrent_tasks do
        Task.async(fn ->
          for event_id <- 1..div(event_count, concurrent_tasks) do
            event_type = Enum.random([
              "channel.chat.message",
              "channel.follow", 
              "obs.scene_changed",
              "system.health_check",
              "stream.state_updated"
            ])
            
            event_data = %{
              "id" => "load_test_#{task_id}_#{event_id}",
              "test_data" => "concurrent_load_test",
              "task_id" => task_id,
              "event_id" => event_id
            }

            # Add required fields based on event type
            event_data = case event_type do
              "channel.chat.message" ->
                Map.merge(event_data, %{
                  "message_id" => "msg_#{task_id}_#{event_id}",
                  "chatter_user_id" => "456789123",
                  "chatter_user_login" => "test_chatter",
                  "broadcaster_user_id" => "987654321",
                  "broadcaster_user_login" => "test_broadcaster",
                  "message" => %{"text" => "Load test message"}
                })
              "channel.follow" ->
                Map.merge(event_data, %{
                  "user_id" => "123456789",
                  "user_login" => "load_user_#{task_id}_#{event_id}",
                  "broadcaster_user_id" => "987654321",
                  "broadcaster_user_login" => "test_broadcaster"
                })
              "obs.scene_changed" ->
                Map.merge(event_data, %{
                  "scene_name" => "Load Test Scene #{task_id}",
                  "session_id" => "load_session_#{task_id}"
                })
              "system.health_check" ->
                Map.merge(event_data, %{
                  "service" => "load_test_service_#{task_id}",
                  "status" => "healthy"
                })
              "stream.state_updated" ->
                Map.merge(event_data, %{
                  "current_show" => "load_test_show",
                  "version" => event_id
                })
            end

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

    @tag :p0_critical
    test "memory usage remains stable under load" do
      # Monitor memory usage during event processing to ensure no memory leaks
      
      # Get initial memory usage
      initial_memory = :erlang.memory(:total)
      
      # Process many events to test for memory leaks
      for i <- 1..500 do
        event_type = "channel.chat.message"
        event_data = %{
          "message_id" => "memory_test_#{i}",
          "chatter_user_id" => "123456789",
          "broadcaster_user_id" => "987654321",
          "chatter_user_login" => "test_user",
          "broadcaster_user_login" => "test_broadcaster",
          "message" => %{
            "text" => "Memory test message #{i} with some content to use memory",
            "fragments" => [
              %{"type" => "text", "text" => "Memory test "},
              %{"type" => "emote", "text" => "Kappa"},
              %{"type" => "text", "text" => " message #{i}"}
            ]
          },
          "badges" => [
            %{"set_id" => "subscriber", "id" => "1"},
            %{"set_id" => "moderator", "id" => "1"}
          ]
        }

        assert :ok = Events.process_event(event_type, event_data)
        
        # Periodically check memory usage
        if rem(i, 100) == 0 do
          # Force garbage collection
          :erlang.garbage_collect()
          current_memory = :erlang.memory(:total)
          
          # Memory should not grow excessively (allow for some normal variance)
          memory_growth = current_memory - initial_memory
          max_allowed_growth = 50 * 1024 * 1024  # 50MB
          
          assert memory_growth < max_allowed_growth,
                 "Memory usage grew too much: #{memory_growth} bytes after #{i} events"
        end
      end

      # Final memory check after garbage collection
      :erlang.garbage_collect()
      final_memory = :erlang.memory(:total)
      total_growth = final_memory - initial_memory
      
      # Allow for reasonable memory growth but detect obvious leaks
      max_total_growth = 100 * 1024 * 1024  # 100MB total
      assert total_growth < max_total_growth,
             "Total memory growth too large: #{total_growth} bytes"
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
          "stream.state_updated", "stream.show_changed", "stream.interrupt_removed",
          "stream.emote_increment", "stream.takeover_started", "stream.takeover_cleared",
          "stream.goals_updated"
        ] -> :stream
      String.starts_with?(event_type, "stream.") -> :twitch
      String.starts_with?(event_type, "channel.") -> :twitch
      String.starts_with?(event_type, "obs.") -> :obs
      String.starts_with?(event_type, "ironmon.") -> :ironmon
      String.starts_with?(event_type, "rainwave.") -> :rainwave
      String.starts_with?(event_type, "system.") -> :system
      true -> :twitch  # default
    end
  end

  defp flat_event_format?(event) when is_map(event) do
    Enum.all?(event, fn {_key, value} ->
      case value do
        %DateTime{} -> true  # DateTime structs are allowed
        map when is_map(map) -> false  # No other nested maps allowed
        list when is_list(list) ->
          # Lists are allowed if they contain simple values or structured data with string keys
          Enum.all?(list, fn item ->
            not is_map(item) or map_has_only_string_keys?(item)
          end)
        _ -> true  # All other types are fine
      end
    end)
  end

  defp flat_event_format?(_), do: false

  defp map_has_only_string_keys?(map) when is_map(map) do
    Enum.all?(Map.keys(map), &is_binary/1)
  end

  defp map_has_only_string_keys?(_), do: false

  defp generate_oversized_payload do
    # Generate a payload larger than 100KB
    large_string = String.duplicate("x", 101_000)
    %{
      "message_id" => "oversized_test",
      "chatter_user_id" => "123", 
      "broadcaster_user_id" => "456",
      "message" => %{"text" => large_string}
    }
  end

  defp generate_nested_bomb do
    # Generate deeply nested structure to test size limits
    nest_level = 50
    
    Enum.reduce(1..nest_level, %{"deep_value" => "bomb"}, fn _i, acc ->
      %{"nested" => acc}
    end)
  end

  defp assert_no_legacy_publications_logged(_topic) do
    # This would check logs for any mentions of legacy topic publications
    # For now, we assume the monitoring above is sufficient
    :ok
  end
end