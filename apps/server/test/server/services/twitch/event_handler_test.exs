defmodule Server.Services.Twitch.EventHandlerTest do
  use ExUnit.Case, async: true

  alias Server.Services.Twitch.EventHandler

  setup do
    # Ensure PubSub is available for testing
    start_supervised!({Phoenix.PubSub, name: Server.PubSub})
    :ok
  end

  describe "normalize_event/2" do
    test "normalizes stream.online event" do
      event_type = "stream.online"
      event_data = %{
        "id" => "stream_123",
        "broadcaster_user_id" => "user_123",
        "broadcaster_user_login" => "testuser",
        "broadcaster_user_name" => "TestUser",
        "type" => "live",
        "started_at" => "2023-01-01T12:00:00Z"
      }

      result = EventHandler.normalize_event(event_type, event_data)

      assert result.type == "stream.online"
      assert result.id == "stream_123"
      assert result.broadcaster_user_id == "user_123"
      assert result.broadcaster_user_login == "testuser"
      assert result.broadcaster_user_name == "TestUser"
      assert result.stream_type == "live"
      assert result.stream_id == "stream_123"
      assert %DateTime{} = result.timestamp
      assert %DateTime{} = result.started_at
    end

    test "normalizes stream.offline event" do
      event_type = "stream.offline"
      event_data = %{
        "id" => "event_123",
        "broadcaster_user_id" => "user_123",
        "broadcaster_user_login" => "testuser",
        "broadcaster_user_name" => "TestUser"
      }

      result = EventHandler.normalize_event(event_type, event_data)

      assert result.type == "stream.offline"
      assert result.id == "event_123"
      assert result.broadcaster_user_id == "user_123"
      assert %DateTime{} = result.timestamp
    end

    test "normalizes channel.follow event" do
      event_type = "channel.follow"
      event_data = %{
        "id" => "follow_123",
        "broadcaster_user_id" => "user_123",
        "broadcaster_user_login" => "testuser",
        "broadcaster_user_name" => "TestUser",
        "user_id" => "follower_456",
        "user_login" => "newfollower",
        "user_name" => "NewFollower",
        "followed_at" => "2023-01-01T12:00:00Z"
      }

      result = EventHandler.normalize_event(event_type, event_data)

      assert result.type == "channel.follow"
      assert result.user_id == "follower_456"
      assert result.user_login == "newfollower"
      assert result.user_name == "NewFollower"
      assert %DateTime{} = result.followed_at
    end

    test "normalizes channel.subscribe event" do
      event_type = "channel.subscribe"
      event_data = %{
        "id" => "sub_123",
        "broadcaster_user_id" => "user_123",
        "broadcaster_user_login" => "testuser",
        "broadcaster_user_name" => "TestUser",
        "user_id" => "subscriber_456",
        "user_login" => "newsubscriber",
        "user_name" => "NewSubscriber",
        "tier" => "1000",
        "is_gift" => false
      }

      result = EventHandler.normalize_event(event_type, event_data)

      assert result.type == "channel.subscribe"
      assert result.user_id == "subscriber_456"
      assert result.tier == "1000"
      assert result.is_gift == false
    end

    test "normalizes channel.subscription.gift event" do
      event_type = "channel.subscription.gift"
      event_data = %{
        "id" => "gift_123",
        "broadcaster_user_id" => "user_123",
        "broadcaster_user_login" => "testuser",
        "broadcaster_user_name" => "TestUser",
        "user_id" => "gifter_456",
        "user_login" => "gifter",
        "user_name" => "Gifter",
        "tier" => "1000",
        "total" => 5,
        "cumulative_total" => 25,
        "is_anonymous" => false
      }

      result = EventHandler.normalize_event(event_type, event_data)

      assert result.type == "channel.subscription.gift"
      assert result.user_id == "gifter_456"
      assert result.tier == "1000"
      assert result.total == 5
      assert result.cumulative_total == 25
      assert result.is_anonymous == false
    end

    test "normalizes channel.cheer event" do
      event_type = "channel.cheer"
      event_data = %{
        "id" => "cheer_123",
        "broadcaster_user_id" => "user_123",
        "broadcaster_user_login" => "testuser",
        "broadcaster_user_name" => "TestUser",
        "user_id" => "cheerer_456",
        "user_login" => "cheerer",
        "user_name" => "Cheerer",
        "bits" => 100,
        "message" => "Great stream!",
        "is_anonymous" => false
      }

      result = EventHandler.normalize_event(event_type, event_data)

      assert result.type == "channel.cheer"
      assert result.user_id == "cheerer_456"
      assert result.bits == 100
      assert result.message == "Great stream!"
      assert result.is_anonymous == false
    end

    test "normalizes channel.update event" do
      event_type = "channel.update"
      event_data = %{
        "id" => "update_123",
        "broadcaster_user_id" => "user_123",
        "broadcaster_user_login" => "testuser",
        "broadcaster_user_name" => "TestUser",
        "title" => "New Stream Title",
        "language" => "en",
        "category_id" => "509658",
        "category_name" => "Just Chatting"
      }

      result = EventHandler.normalize_event(event_type, event_data)

      assert result.type == "channel.update"
      assert result.title == "New Stream Title"
      assert result.language == "en"
      assert result.category_id == "509658"
      assert result.category_name == "Just Chatting"
    end

    test "normalizes unknown event type with raw data" do
      event_type = "unknown.event"
      event_data = %{
        "id" => "unknown_123",
        "broadcaster_user_id" => "user_123",
        "broadcaster_user_login" => "testuser",
        "broadcaster_user_name" => "TestUser",
        "custom_field" => "custom_value"
      }

      result = EventHandler.normalize_event(event_type, event_data)

      assert result.type == "unknown.event"
      assert result.id == "unknown_123"
      assert result.raw_data == event_data
    end
  end

  describe "process_event/3" do
    test "successfully processes a valid event" do
      event_type = "stream.online"
      event_data = %{
        "id" => "stream_123",
        "broadcaster_user_id" => "user_123",
        "broadcaster_user_login" => "testuser",
        "broadcaster_user_name" => "TestUser",
        "type" => "live",
        "started_at" => "2023-01-01T12:00:00Z"
      }

      # Subscribe to PubSub topics to verify events are published
      Phoenix.PubSub.subscribe(Server.PubSub, "dashboard")
      Phoenix.PubSub.subscribe(Server.PubSub, "twitch:stream.online")
      Phoenix.PubSub.subscribe(Server.PubSub, "stream_status")

      result = EventHandler.process_event(event_type, event_data)

      assert result == :ok

      # Verify events were published
      assert_receive {:twitch_event, normalized_event}
      assert normalized_event.type == "stream.online"

      assert_receive {:event, normalized_event}
      assert normalized_event.type == "stream.online"

      assert_receive {:stream_online, normalized_event}
      assert normalized_event.type == "stream.online"
    end

    test "handles processing errors gracefully" do
      # This would test error handling in process_event
      # For now, we test with invalid data that might cause JSON encoding issues
      event_type = "test.event"
      event_data = %{
        "id" => "test_123",
        "broadcaster_user_id" => "user_123",
        "broadcaster_user_login" => "testuser",
        "broadcaster_user_name" => "TestUser"
      }

      result = EventHandler.process_event(event_type, event_data)

      # Should still succeed for basic data
      assert result == :ok
    end
  end

  describe "publish_event/2" do
    test "publishes to general dashboard topic" do
      event_type = "channel.follow"
      normalized_event = %{
        type: "channel.follow",
        id: "follow_123",
        user_name: "NewFollower"
      }

      Phoenix.PubSub.subscribe(Server.PubSub, "dashboard")

      EventHandler.publish_event(event_type, normalized_event)

      assert_receive {:twitch_event, ^normalized_event}
    end

    test "publishes to event-specific topic" do
      event_type = "channel.subscribe"
      normalized_event = %{
        type: "channel.subscribe",
        id: "sub_123",
        user_name: "NewSubscriber"
      }

      Phoenix.PubSub.subscribe(Server.PubSub, "twitch:channel.subscribe")

      EventHandler.publish_event(event_type, normalized_event)

      assert_receive {:event, ^normalized_event}
    end

    test "publishes to legacy topic structure for backward compatibility" do
      event_type = "channel.follow"
      normalized_event = %{
        type: "channel.follow",
        id: "follow_123",
        user_name: "NewFollower"
      }

      Phoenix.PubSub.subscribe(Server.PubSub, "followers")

      EventHandler.publish_event(event_type, normalized_event)

      assert_receive {:new_follower, ^normalized_event}
    end
  end

  describe "emit_telemetry/2" do
    test "emits telemetry events" do
      event_type = "stream.online"
      normalized_event = %{
        type: "stream.online",
        broadcaster_user_id: "user_123",
        stream_type: "live"
      }

      # Attach a test telemetry handler
      test_pid = self()
      handler_id = :test_handler

      :telemetry.attach(handler_id, [:server, :twitch, :stream, :online], fn name, measurements, metadata, _config ->
        send(test_pid, {:telemetry_event, name, measurements, metadata})
      end, nil)

      EventHandler.emit_telemetry(event_type, normalized_event)

      assert_receive {:telemetry_event, [:server, :twitch, :stream, :online], %{count: 1}, metadata}
      assert metadata.broadcaster_id == "user_123"
      assert metadata.stream_type == "live"

      # Clean up
      :telemetry.detach(handler_id)
    end

    test "emits generic telemetry for unknown event types" do
      event_type = "unknown.event"
      normalized_event = %{
        type: "unknown.event",
        broadcaster_user_id: "user_123"
      }

      # Attach a test telemetry handler
      test_pid = self()
      handler_id = :test_handler_generic

      :telemetry.attach(handler_id, [:server, :twitch, :event, :other], fn name, measurements, metadata, _config ->
        send(test_pid, {:telemetry_event, name, measurements, metadata})
      end, nil)

      EventHandler.emit_telemetry(event_type, normalized_event)

      assert_receive {:telemetry_event, [:server, :twitch, :event, :other], %{count: 1}, metadata}
      assert metadata.event_type == "unknown.event"
      assert metadata.broadcaster_id == "user_123"

      # Clean up
      :telemetry.detach(handler_id)
    end
  end
end