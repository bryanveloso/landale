defmodule Server.EventsTest do
  use Server.DataCase, async: true

  @moduletag :database

  alias Server.Events

  describe "process_event/3 with validation" do
    test "processes valid Twitch stream.online event" do
      valid_data = %{
        "id" => "stream123",
        "broadcaster_user_id" => "123456",
        "broadcaster_user_login" => "testuser",
        "broadcaster_user_name" => "TestUser",
        "type" => "live",
        "started_at" => "2024-01-01T12:00:00Z"
      }

      assert :ok = Events.process_event("stream.online", valid_data)
    end

    test "rejects invalid Twitch stream.online event" do
      invalid_data = %{
        # Non-numeric
        "broadcaster_user_id" => "invalid_user_id",
        "broadcaster_user_login" => "testuser"
      }

      assert {:error, {:validation_failed, errors}} =
               Events.process_event("stream.online", invalid_data)

      assert is_map(errors)
      assert Map.has_key?(errors, :broadcaster_user_id)
    end

    test "processes valid OBS connection event" do
      valid_data = %{
        "session_id" => "session123",
        "websocket_version" => "5.0.0",
        "rpc_version" => "1"
      }

      assert :ok = Events.process_event("obs.connection_established", valid_data)
    end

    test "processes valid system service event" do
      valid_data = %{
        "service" => "phononmaser",
        "version" => "1.0.0",
        "pid" => 12_345
      }

      assert :ok = Events.process_event("system.service_started", valid_data)
    end

    test "allows unknown event types with basic validation" do
      valid_data = %{
        "custom_field" => "custom_value",
        "another_field" => 42
      }

      assert :ok = Events.process_event("custom.unknown.event", valid_data)
    end

    test "rejects events with malicious payloads" do
      # Test SQL injection attempt
      malicious_data = %{
        "broadcaster_user_id" => "123456",
        # Invalid username format
        "broadcaster_user_login" => "'; DROP TABLE users; --"
      }

      assert {:error, {:validation_failed, _errors}} =
               Events.process_event("stream.online", malicious_data)

      # Test control character injection
      control_char_data = %{
        "broadcaster_user_id" => "123456",
        "broadcaster_user_login" => "test\x00user"
      }

      assert {:error, {:validation_failed, _errors}} =
               Events.process_event("stream.online", control_char_data)

      # Test oversized payload
      oversized_data = %{
        "broadcaster_user_id" => "123456",
        "broadcaster_user_login" => "testuser",
        # > 100KB
        "large_field" => String.duplicate("a", 200_000)
      }

      assert {:error, {:validation_failed, _errors}} =
               Events.process_event("stream.online", oversized_data)
    end

    test "validation errors are properly logged" do
      invalid_data = %{
        "broadcaster_user_id" => "invalid_id",
        "broadcaster_user_login" => "testuser"
      }

      log_output =
        capture_log(fn ->
          Events.process_event("stream.online", invalid_data)
        end)

      assert log_output =~ "Event validation failed - rejecting potentially malicious payload"
      assert log_output =~ "stream.online"
      assert log_output =~ "validation_errors"
    end

    test "valid events are processed normally after validation" do
      valid_data = %{
        "user_id" => "789012",
        "user_login" => "follower",
        "broadcaster_user_id" => "123456",
        "broadcaster_user_login" => "streamer",
        "followed_at" => "2024-01-01T12:00:00Z"
      }

      # Should process successfully and store in activity log
      assert :ok = Events.process_event("channel.follow", valid_data)

      # Verify event was stored (assuming this event type is in valuable_events)
      events = Server.ActivityLog.list_recent_events(limit: 10)
      follow_event = Enum.find(events, &(&1.event_type == "channel.follow"))

      assert follow_event != nil
      assert follow_event.user_id == "789012"
      assert follow_event.user_login == "follower"
    end

    test "should_store_event?/1 works for different event types" do
      # Should store valuable events
      assert Events.should_store_event?("channel.follow") == true
      assert Events.should_store_event?("channel.chat.message") == true
      assert Events.should_store_event?("obs.stream_started") == true
      assert Events.should_store_event?("system.service_started") == true

      # Should not store ephemeral events
      assert Events.should_store_event?("system.health_check") == false
      assert Events.should_store_event?("system.performance_metric") == false
      assert Events.should_store_event?("obs.connection_established") == false
    end

    test "processes chat messages with complex validation" do
      valid_chat_data = %{
        "message_id" => "msg123",
        "broadcaster_user_id" => "123456",
        "broadcaster_user_login" => "streamer",
        "chatter_user_id" => "789012",
        "chatter_user_login" => "chatter",
        "chatter_user_name" => "ChatterName",
        "message" => %{
          "text" => "Hello stream!",
          "fragments" => [
            %{"type" => "text", "text" => "Hello "},
            %{"type" => "emote", "text" => "Kappa"}
          ]
        },
        "color" => "#FF0000",
        "badges" => [
          %{"set_id" => "subscriber", "id" => "1", "info" => "Subscriber"}
        ]
      }

      assert :ok = Events.process_event("channel.chat.message", valid_chat_data)
    end

    test "rejects chat messages with invalid structure" do
      invalid_chat_data = %{
        "message_id" => "msg123",
        "broadcaster_user_id" => "123456",
        "chatter_user_id" => "789012",
        # Invalid - should be map with text field
        "message" => "this should be a map"
      }

      assert {:error, {:validation_failed, errors}} =
               Events.process_event("channel.chat.message", invalid_chat_data)

      assert Map.has_key?(errors, :message)
    end

    test "handles validation gracefully for edge cases" do
      # Empty data
      assert {:error, {:validation_failed, _}} = Events.process_event("stream.online", %{})

      # Nil data - should be handled by BoundaryConverter
      assert {:error, {:validation_failed, _}} = Events.process_event("stream.online", nil)

      # Data with unexpected types
      weird_data = %{
        "broadcaster_user_id" => ["not", "a", "string"],
        "broadcaster_user_login" => %{"nested" => "object"}
      }

      assert {:error, {:validation_failed, _}} = Events.process_event("stream.online", weird_data)
    end

    test "validates IronMON events correctly" do
      valid_ironmon_data = %{
        "game_type" => "emerald",
        "game_name" => "Pokemon Emerald",
        "version" => "1.0",
        "difficulty" => "normal",
        "run_id" => "run123"
      }

      assert :ok = Events.process_event("ironmon.init", valid_ironmon_data)

      # Test invalid data
      invalid_ironmon_data = %{
        # Should be non-negative
        "seed_count" => -1,
        "run_id" => "run123"
      }

      assert {:error, {:validation_failed, errors}} =
               Events.process_event("ironmon.seed", invalid_ironmon_data)

      assert Map.has_key?(errors, :seed_count)
    end

    test "validates Rainwave events correctly" do
      valid_rainwave_data = %{
        "song_id" => 123,
        "song_title" => "Test Song",
        "artist" => "Test Artist",
        "station_id" => 1,
        "station_name" => "Test Station",
        "listening" => true
      }

      assert :ok = Events.process_event("rainwave.song_changed", valid_rainwave_data)

      # Test invalid data
      invalid_rainwave_data = %{
        # Should be positive
        "song_id" => -1,
        "station_id" => 1
      }

      assert {:error, {:validation_failed, errors}} =
               Events.process_event("rainwave.song_changed", invalid_rainwave_data)

      assert Map.has_key?(errors, :song_id)
    end

    test "system events produce flat format without nested structures" do
      health_data = %{
        "service" => "test_service",
        "status" => "healthy",
        "checks_passed" => 5,
        "checks_failed" => 0,
        "details" => %{
          "uptime" => 3600,
          "memory_usage" => 50.5,
          "cpu_usage" => 25.0
        }
      }

      assert :ok = Events.process_event("system.health_check", health_data)

      # Verify the normalized event has flat structure
      normalized = Events.normalize_event("system.health_check", health_data)

      # Should have flattened detail fields
      assert normalized.uptime == 3600
      assert normalized.memory_usage == 50.5
      assert normalized.cpu_usage == 25.0

      # Should NOT have nested details field
      refute Map.has_key?(normalized, :details)
    end

    test "performance metric events produce flat format" do
      metric_data = %{
        "metric" => "cpu_usage",
        "value" => 75.5,
        "unit" => "percent",
        "metadata" => %{
          "component" => "web_server",
          "hostname" => "server1",
          "environment" => "production"
        }
      }

      assert :ok = Events.process_event("system.performance_metric", metric_data)

      # Verify the normalized event has flat structure
      normalized = Events.normalize_event("system.performance_metric", metric_data)

      # Should have flattened metadata fields
      assert normalized.component == "web_server"
      assert normalized.hostname == "server1"
      assert normalized.environment == "production"

      # Should NOT have nested metadata field
      refute Map.has_key?(normalized, :metadata)
    end
  end

  describe "normalize_event/2 with validated data" do
    test "normalizes validated stream.online data correctly" do
      validated_data = %{
        id: "stream123",
        broadcaster_user_id: "123456",
        broadcaster_user_login: "testuser",
        broadcaster_user_name: "TestUser",
        type: "live",
        started_at: "2024-01-01T12:00:00Z"
      }

      normalized = Events.normalize_event("stream.online", validated_data)

      assert normalized.type == "stream.online"
      assert normalized.source == :twitch
      assert normalized.stream_id == "stream123"
      assert normalized.broadcaster_user_id == "123456"
      assert normalized.broadcaster_user_login == "testuser"
      assert normalized.correlation_id != nil
      assert %DateTime{} = normalized.timestamp
    end

    test "normalizes validated OBS data correctly" do
      validated_data = %{
        session_id: "session123",
        websocket_version: "5.0.0"
      }

      normalized = Events.normalize_event("obs.connection_established", validated_data)

      assert normalized.type == "obs.connection_established"
      assert normalized.source == :obs
      assert normalized.connection_state == "connected"
      assert normalized.session_id == "session123"
      assert normalized.websocket_version == "5.0.0"
    end
  end

  # Helper to capture log output
  defp capture_log(fun) do
    ExUnit.CaptureLog.capture_log(fun)
  end
end
