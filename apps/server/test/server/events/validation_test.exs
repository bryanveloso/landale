defmodule Server.Events.ValidationTest do
  use Server.DataCase, async: true

  alias Server.Events.Validation

  describe "validate_event_data/2 for Twitch events" do
    test "validates stream.online event with valid data" do
      valid_data = %{
        "id" => "stream123",
        "broadcaster_user_id" => "123456",
        "broadcaster_user_login" => "testuser",
        "broadcaster_user_name" => "TestUser",
        "type" => "live",
        "started_at" => "2024-01-01T12:00:00Z"
      }

      assert {:ok, validated} = Validation.validate_event_data("stream.online", valid_data)
      assert validated.broadcaster_user_id == "123456"
      assert validated.broadcaster_user_login == "testuser"
    end

    test "rejects stream.online with invalid broadcaster_user_id" do
      invalid_data = %{
        # Non-numeric
        "broadcaster_user_id" => "invalid_user_id",
        "broadcaster_user_login" => "testuser"
      }

      assert {:error, errors} = Validation.validate_event_data("stream.online", invalid_data)
      assert "must be a numeric string (Twitch user ID)" in (errors[:broadcaster_user_id] || [])
    end

    test "rejects stream.online with invalid username format" do
      invalid_data = %{
        "broadcaster_user_id" => "123456",
        # Invalid characters
        "broadcaster_user_login" => "test-user!"
      }

      assert {:error, errors} = Validation.validate_event_data("stream.online", invalid_data)

      assert "must be a valid Twitch username (alphanumeric + underscore, 1-25 chars)" in (errors[
                                                                                             :broadcaster_user_login
                                                                                           ] || [])
    end

    test "validates channel.follow event with valid data" do
      valid_data = %{
        "user_id" => "789012",
        "user_login" => "follower",
        "user_name" => "Follower",
        "broadcaster_user_id" => "123456",
        "broadcaster_user_login" => "streamer",
        "broadcaster_user_name" => "Streamer",
        "followed_at" => "2024-01-01T12:00:00Z"
      }

      assert {:ok, validated} = Validation.validate_event_data("channel.follow", valid_data)
      assert validated.user_id == "789012"
      assert validated.broadcaster_user_id == "123456"
    end

    test "rejects channel.follow with missing required fields" do
      invalid_data = %{
        # Missing user_id, broadcaster fields
        "user_login" => "follower"
      }

      assert {:error, errors} = Validation.validate_event_data("channel.follow", invalid_data)
      assert "can't be blank" in (errors[:user_id] || [])
      assert "can't be blank" in (errors[:broadcaster_user_id] || [])
    end

    test "validates channel.cheer with valid data" do
      valid_data = %{
        "user_id" => "789012",
        "user_login" => "cheeruser",
        "broadcaster_user_id" => "123456",
        "broadcaster_user_login" => "streamer",
        "bits" => 100,
        "message" => "Great stream!"
      }

      assert {:ok, validated} = Validation.validate_event_data("channel.cheer", valid_data)
      assert validated.bits == 100
      assert validated.message == "Great stream!"
    end

    test "rejects channel.cheer with negative bits" do
      invalid_data = %{
        "broadcaster_user_id" => "123456",
        "broadcaster_user_login" => "streamer",
        # Invalid negative value
        "bits" => -50
      }

      assert {:error, errors} = Validation.validate_event_data("channel.cheer", invalid_data)
      assert "must be a positive integer" in (errors[:bits] || [])
    end

    test "validates channel.subscribe with valid tier" do
      valid_data = %{
        "user_id" => "789012",
        "user_login" => "subscriber",
        "broadcaster_user_id" => "123456",
        "broadcaster_user_login" => "streamer",
        "tier" => "1000"
      }

      assert {:ok, validated} = Validation.validate_event_data("channel.subscribe", valid_data)
      assert validated.tier == "1000"
    end

    test "rejects channel.subscribe with invalid tier" do
      invalid_data = %{
        "user_id" => "789012",
        "user_login" => "subscriber",
        "broadcaster_user_id" => "123456",
        "broadcaster_user_login" => "streamer",
        # Invalid tier value
        "tier" => "500"
      }

      assert {:error, errors} = Validation.validate_event_data("channel.subscribe", invalid_data)
      assert "must be a valid Twitch subscription tier (1000, 2000, or 3000)" in (errors[:tier] || [])
    end

    test "validates channel.chat.message with complex structure" do
      valid_data = %{
        "message_id" => "msg123",
        "broadcaster_user_id" => "123456",
        "chatter_user_id" => "789012",
        "message" => %{"text" => "Hello world!"},
        "color" => "#FF0000",
        "badges" => [],
        "message_type" => "text"
      }

      assert {:ok, validated} = Validation.validate_event_data("channel.chat.message", valid_data)
      assert validated.message_id == "msg123"
      assert validated.chatter_user_id == "789012"
    end

    test "rejects chat message with oversized content" do
      invalid_data = %{
        "message_id" => "msg123",
        "broadcaster_user_id" => "123456",
        "chatter_user_id" => "789012",
        # Too long
        "message" => %{"text" => String.duplicate("a", 600)}
      }

      assert {:error, errors} = Validation.validate_event_data("channel.chat.message", invalid_data)
      assert "message text too long (max 500 bytes)" in (errors[:message] || [])
    end

    test "validates channel.update with content classification labels" do
      valid_data = %{
        "broadcaster_user_id" => "123456",
        "broadcaster_user_login" => "streamer",
        "title" => "Playing games!",
        "language" => "en",
        "category_id" => "509658",
        "category_name" => "Just Chatting",
        "content_classification_labels" => ["MatureGame"]
      }

      assert {:ok, validated} = Validation.validate_event_data("channel.update", valid_data)
      assert validated.title == "Playing games!"
      assert validated.content_classification_labels == ["MatureGame"]
    end

    test "rejects channel.update with oversized label list" do
      invalid_data = %{
        "broadcaster_user_id" => "123456",
        "broadcaster_user_login" => "streamer",
        # Too many items
        "content_classification_labels" => Enum.map(1..150, &"Label#{&1}")
      }

      assert {:error, errors} = Validation.validate_event_data("channel.update", invalid_data)
      assert "list too long (max 100 items)" in (errors[:content_classification_labels] || [])
    end

    test "handles complex type validation errors without crashing error formatter" do
      invalid_data = %{
        "broadcaster_user_id" => "123456",
        "broadcaster_user_login" => "streamer",
        # String instead of array - triggers Ecto type validation error with {:array, :string} in opts
        "content_classification_labels" => "MatureGame"
      }

      # Should return error without crashing (previously crashed with Protocol.UndefinedError)
      assert {:error, errors} = Validation.validate_event_data("channel.update", invalid_data)

      # Verify error message contains properly formatted type info
      assert Map.has_key?(errors, :content_classification_labels)
      error_msg = List.first(errors.content_classification_labels)
      assert is_binary(error_msg)
      # Should contain the formatted type spec using inspect() instead of to_string()
      assert error_msg =~ "{:array, :string}" or error_msg =~ "invalid"
    end
  end

  describe "validate_event_data/2 for OBS events" do
    test "validates obs.connection_established with valid data" do
      valid_data = %{
        "session_id" => "session123",
        "websocket_version" => "5.0.0",
        "rpc_version" => "1",
        "authentication" => false
      }

      assert {:ok, validated} = Validation.validate_event_data("obs.connection_established", valid_data)
      assert validated.session_id == "session123"
      assert validated.websocket_version == "5.0.0"
    end

    test "validates obs.scene_changed with scene names" do
      valid_data = %{
        "scene_name" => "Game Scene",
        "previous_scene" => "BRB Scene",
        "session_id" => "session123"
      }

      assert {:ok, validated} = Validation.validate_event_data("obs.scene_changed", valid_data)
      assert validated.scene_name == "Game Scene"
      assert validated.previous_scene == "BRB Scene"
    end

    test "validates obs.stream_started with output state" do
      valid_data = %{
        "output_active" => true,
        "output_state" => "STARTED",
        "session_id" => "session123"
      }

      assert {:ok, validated} = Validation.validate_event_data("obs.stream_started", valid_data)
      assert validated.output_state == "STARTED"
    end
  end

  describe "validate_event_data/2 for System events" do
    test "validates system.service_started with valid data" do
      valid_data = %{
        "service" => "phononmaser",
        "version" => "1.0.0",
        "pid" => 12_345
      }

      assert {:ok, validated} = Validation.validate_event_data("system.service_started", valid_data)
      assert validated.service == "phononmaser"
      assert validated.pid == 12_345
    end

    test "rejects system.service_started with invalid PID" do
      invalid_data = %{
        "service" => "phononmaser",
        # Invalid negative PID
        "pid" => -1
      }

      assert {:error, errors} = Validation.validate_event_data("system.service_started", invalid_data)
      assert "must be a positive integer" in (errors[:pid] || [])
    end

    test "validates system.health_check with check counts" do
      valid_data = %{
        "service" => "seed",
        "status" => "healthy",
        "checks_passed" => 5,
        "checks_failed" => 0,
        "details" => %{"cpu" => "low", "memory" => "normal"}
      }

      assert {:ok, validated} = Validation.validate_event_data("system.health_check", valid_data)
      assert validated.service == "seed"
      assert validated.checks_passed == 5
      assert validated.checks_failed == 0
    end

    test "rejects system.health_check with negative check counts" do
      invalid_data = %{
        "service" => "seed",
        # Invalid negative count
        "checks_passed" => -1
      }

      assert {:error, errors} = Validation.validate_event_data("system.health_check", invalid_data)
      assert "must be a non-negative integer" in (errors[:checks_passed] || [])
    end
  end

  describe "validate_event_data/2 for unknown event types" do
    test "allows unknown event types with basic validation" do
      valid_data = %{
        "some_field" => "some_value",
        "another_field" => 42
      }

      assert {:ok, validated} = Validation.validate_event_data("unknown.event.type", valid_data)
      assert validated.raw_data == valid_data
    end

    test "rejects unknown events with too many keys" do
      # Create a map with too many keys
      invalid_data = Enum.into(1..60, %{}, fn i -> {"key#{i}", "value#{i}"} end)

      assert {:error, errors} = Validation.validate_event_data("unknown.event.type", invalid_data)
      assert "too many keys (max 50)" in (errors[:data] || [])
    end
  end

  describe "validate_event_data/2 security validations" do
    test "rejects events with control characters in strings" do
      invalid_data = %{
        "broadcaster_user_id" => "123456",
        # Null byte injection attempt
        "broadcaster_user_login" => "test\x00user"
      }

      assert {:error, errors} = Validation.validate_event_data("stream.online", invalid_data)

      assert "must be a valid Twitch username (alphanumeric + underscore, 1-25 chars)" in (errors[
                                                                                             :broadcaster_user_login
                                                                                           ] || [])
    end

    test "rejects events with oversized string fields" do
      invalid_data = %{
        "broadcaster_user_id" => "123456",
        "broadcaster_user_login" => "streamer",
        # Too long
        "broadcaster_user_name" => String.duplicate("a", 2500)
      }

      assert {:error, errors} = Validation.validate_event_data("stream.online", invalid_data)
      assert "too long (max 2000 bytes)" in (errors[:broadcaster_user_name] || [])
    end

    test "rejects events with oversized overall data" do
      # Create data that exceeds the 100KB limit
      large_string = String.duplicate("a", 50_000)

      invalid_data = %{
        "broadcaster_user_id" => "123456",
        "broadcaster_user_login" => "streamer",
        "field1" => large_string,
        "field2" => large_string,
        # Combined > 100KB
        "field3" => large_string
      }

      assert {:error, errors} = Validation.validate_event_data("stream.online", invalid_data)
      assert "event data too large (max 100KB)" in (errors[:data] || [])
    end

    test "rejects events with non-string values in string fields" do
      invalid_data = %{
        "broadcaster_user_id" => "123456",
        # Should be string
        "broadcaster_user_login" => 12_345
      }

      assert {:error, errors} = Validation.validate_event_data("stream.online", invalid_data)
      assert "is invalid" in (errors[:broadcaster_user_login] || [])
    end

    test "validates datetime strings properly" do
      valid_data = %{
        "broadcaster_user_id" => "123456",
        "broadcaster_user_login" => "streamer",
        "started_at" => "2024-01-01T12:00:00Z"
      }

      assert {:ok, _validated} = Validation.validate_event_data("stream.online", valid_data)

      invalid_data = %{
        "broadcaster_user_id" => "123456",
        "broadcaster_user_login" => "streamer",
        "started_at" => "not-a-datetime"
      }

      assert {:error, errors} = Validation.validate_event_data("stream.online", invalid_data)
      assert "must be a valid ISO8601 datetime" in (errors[:started_at] || [])
    end
  end

  describe "integration with main processing" do
    test "Server.Events.process_event/3 uses validation" do
      # Valid event should process successfully
      valid_event_data = %{
        "broadcaster_user_id" => "123456",
        "broadcaster_user_login" => "testuser"
      }

      assert :ok = Server.Events.process_event("stream.offline", valid_event_data)

      # Invalid event should be rejected
      invalid_event_data = %{
        # Non-numeric
        "broadcaster_user_id" => "invalid_id",
        "broadcaster_user_login" => "testuser"
      }

      assert {:error, {:validation_failed, _errors}} =
               Server.Events.process_event("stream.offline", invalid_event_data)
    end

    test "validation failure is properly logged" do
      invalid_event_data = %{
        # Control character injection
        "broadcaster_user_login" => "test\x00user"
      }

      # Capture log output
      log_output =
        capture_log(fn ->
          Server.Events.process_event("stream.online", invalid_event_data)
        end)

      assert log_output =~ "Event validation failed - rejecting potentially malicious payload"
      assert log_output =~ "validation_errors"
      assert log_output =~ "stream.online"
    end
  end

  # Helper to capture log output
  defp capture_log(fun) do
    ExUnit.CaptureLog.capture_log(fun)
  end
end
