defmodule Server.Services.Twitch.EventHandlerTest do
  use ExUnit.Case, async: true

  @moduletag :services

  alias Server.Services.Twitch.EventHandler

  setup do
    # Start TaskSupervisor for tests that use process_event/2
    case start_supervised({Task.Supervisor, name: Server.TaskSupervisor}) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end
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
      assert result.started_at == ~U[2023-01-01 12:00:00Z]
    end

    test "normalizes stream.offline event" do
      event_type = "stream.offline"

      event_data = %{
        "broadcaster_user_id" => "user_123",
        "broadcaster_user_login" => "testuser",
        "broadcaster_user_name" => "TestUser"
      }

      result = EventHandler.normalize_event(event_type, event_data)

      assert result.type == "stream.offline"
      assert result.broadcaster_user_id == "user_123"
      assert result.broadcaster_user_login == "testuser"
      assert result.broadcaster_user_name == "TestUser"
    end

    test "normalizes channel.follow event" do
      event_type = "channel.follow"

      event_data = %{
        "user_id" => "follower_123",
        "user_login" => "newfollower",
        "user_name" => "NewFollower",
        "broadcaster_user_id" => "user_123",
        "broadcaster_user_login" => "testuser",
        "broadcaster_user_name" => "TestUser",
        "followed_at" => "2023-01-01T12:00:00Z"
      }

      result = EventHandler.normalize_event(event_type, event_data)

      assert result.type == "channel.follow"
      assert result.user_id == "follower_123"
      assert result.user_login == "newfollower"
      assert result.user_name == "NewFollower"
      assert result.broadcaster_user_id == "user_123"
      assert result.followed_at == ~U[2023-01-01 12:00:00Z]
    end

    test "normalizes channel.subscribe event" do
      event_type = "channel.subscribe"

      event_data = %{
        "user_id" => "subscriber_123",
        "user_login" => "newsubscriber",
        "user_name" => "NewSubscriber",
        "broadcaster_user_id" => "user_123",
        "broadcaster_user_login" => "testuser",
        "broadcaster_user_name" => "TestUser",
        "tier" => "1000",
        "is_gift" => false
      }

      result = EventHandler.normalize_event(event_type, event_data)

      assert result.type == "channel.subscribe"
      assert result.user_id == "subscriber_123"
      assert result.user_name == "NewSubscriber"
      assert result.tier == "1000"
      assert result.is_gift == false
    end

    test "normalizes channel.subscription.gift event" do
      event_type = "channel.subscription.gift"

      event_data = %{
        "user_id" => "gifter_123",
        "user_login" => "generousgifter",
        "user_name" => "GenerousGifter",
        "broadcaster_user_id" => "user_123",
        "total" => 5,
        "tier" => "1000",
        "cumulative_total" => 50,
        "is_anonymous" => false
      }

      result = EventHandler.normalize_event(event_type, event_data)

      assert result.type == "channel.subscription.gift"
      assert result.user_name == "GenerousGifter"
      assert result.total == 5
      assert result.tier == "1000"
      assert result.cumulative_total == 50
      assert result.is_anonymous == false
    end

    test "normalizes channel.cheer event" do
      event_type = "channel.cheer"

      event_data = %{
        "user_id" => "cheerer_123",
        "user_login" => "generousviewer",
        "user_name" => "GenerousViewer",
        "broadcaster_user_id" => "user_123",
        "message" => "Great stream! cheer100",
        "bits" => 100,
        "is_anonymous" => false
      }

      result = EventHandler.normalize_event(event_type, event_data)

      assert result.type == "channel.cheer"
      assert result.user_name == "GenerousViewer"
      assert result.message == "Great stream! cheer100"
      assert result.bits == 100
      assert result.is_anonymous == false
    end

    test "normalizes channel.update event" do
      event_type = "channel.update"

      event_data = %{
        "broadcaster_user_id" => "user_123",
        "broadcaster_user_login" => "testuser",
        "broadcaster_user_name" => "TestUser",
        "title" => "New Stream Title",
        "language" => "en",
        "category_id" => "12345",
        "category_name" => "Just Chatting",
        "content_classification_labels" => []
      }

      result = EventHandler.normalize_event(event_type, event_data)

      assert result.type == "channel.update"
      assert result.broadcaster_user_id == "user_123"
      assert result.title == "New Stream Title"
      assert result.category_name == "Just Chatting"
      assert result.language == "en"
    end

    test "normalizes unknown event type with raw data" do
      event_type = "unknown.event"

      event_data = %{
        "id" => "unknown_123",
        "some_field" => "some_value",
        "nested" => %{"data" => "value"}
      }

      result = EventHandler.normalize_event(event_type, event_data)

      assert result.type == "unknown.event"
      assert result.id == "unknown_123"
      assert result.raw_data == event_data
    end
  end

  describe "process_event/2" do
    test "processes valid channel.chat.message event" do
      event_type = "channel.chat.message"

      event_data = %{
        "id" => "msg_123",
        "broadcaster_user_id" => "user_123",
        "broadcaster_user_login" => "testuser",
        "broadcaster_user_name" => "TestUser",
        "chatter_user_id" => "chatter_123",
        "chatter_user_login" => "chatter",
        "chatter_user_name" => "Chatter",
        "message_id" => "msg_123",
        "message" => %{
          "text" => "Hello world!",
          "fragments" => [%{"type" => "text", "text" => "Hello world!"}]
        },
        "color" => "#FF0000",
        "badges" => [],
        "message_type" => "text",
        "cheer" => nil,
        "reply" => nil,
        "channel_points_custom_reward_id" => nil
      }

      assert :ok = EventHandler.process_event(event_type, event_data)
    end

    test "normalized events have flat canonical structure" do
      event_type = "channel.chat.message"

      event_data = %{
        "message_id" => "msg_456",
        "broadcaster_user_id" => "user_789",
        "broadcaster_user_login" => "streamer",
        "broadcaster_user_name" => "Streamer",
        "chatter_user_id" => "chatter_456",
        "chatter_user_login" => "viewer",
        "chatter_user_name" => "Viewer",
        "message" => %{
          "text" => "Hello with emotes Kappa avalonARTSY",
          "fragments" => [
            %{"type" => "text", "text" => "Hello with emotes "},
            %{"type" => "emote", "text" => "Kappa"},
            %{"type" => "text", "text" => " "},
            %{"type" => "emote", "text" => "avalonARTSY"}
          ]
        },
        "color" => "#00B1CC",
        "badges" => [
          %{"set_id" => "subscriber", "id" => "12", "info" => "12 months"}
        ],
        "message_type" => "text"
      }

      result = EventHandler.normalize_event(event_type, event_data)

      # Verify flat structure - all fields should be directly accessible
      assert result.type == "channel.chat.message"
      assert result.source == :twitch
      assert result.correlation_id != nil
      assert result.timestamp != nil

      # User fields should be flat (not nested under data)
      assert result.user_id == "chatter_456"
      assert result.user_login == "viewer"
      assert result.user_name == "Viewer"

      # Message fields should be flat
      assert result.message == "Hello with emotes Kappa avalonARTSY"
      assert result.color == "#00B1CC"

      # Emotes should be flat arrays
      assert result.emotes == ["Kappa"]
      assert result.native_emotes == ["avalonARTSY"]

      # Badges should be flat
      assert is_list(result.badges)
      assert length(result.badges) == 1

      # No nested data field should exist
      refute Map.has_key?(result, :data)
    end

    test "processes valid channel.follow event" do
      event_type = "channel.follow"

      event_data = %{
        "id" => "follow_123",
        "user_id" => "follower_123",
        "user_login" => "newfollower",
        "user_name" => "NewFollower",
        "broadcaster_user_id" => "user_123",
        "broadcaster_user_login" => "testuser",
        "broadcaster_user_name" => "TestUser",
        "followed_at" => "2023-01-01T12:00:00Z"
      }

      assert :ok = EventHandler.process_event(event_type, event_data)
    end

    test "processes event with missing data gracefully" do
      event_type = "channel.chat.message"

      event_data = %{
        # Missing required broadcaster_user_id
        "id" => "msg_123"
      }

      assert :ok = EventHandler.process_event(event_type, event_data)
    end

    test "processes empty event type gracefully" do
      event_type = ""

      event_data = %{
        "id" => "msg_123",
        "broadcaster_user_id" => "user_123"
      }

      assert :ok = EventHandler.process_event(event_type, event_data)
    end
  end
end
