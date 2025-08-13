defmodule Server.Events.TransformerTest do
  use ExUnit.Case, async: true

  @moduletag :unit

  alias Server.Events.{Event, Transformer}

  describe "from_twitch/2" do
    test "transforms channel.follow event" do
      event_data = %{
        "user_id" => "12345",
        "user_name" => "follower123",
        "user_login" => "follower123",
        "broadcaster_user_id" => "67890",
        "broadcaster_user_name" => "streamer",
        "broadcaster_user_login" => "streamer",
        "followed_at" => "2025-08-13T12:00:00Z"
      }

      event = Transformer.from_twitch("channel.follow", event_data)

      assert event.type == "channel.follow"
      assert event.source == :twitch
      assert event.data.user_id == "12345"
      assert event.data.user_name == "follower123"
      assert event.data.user_login == "follower123"
      assert event.data.broadcaster_user_id == "67890"
      assert event.data.followed_at == "2025-08-13T12:00:00Z"
      assert event.timestamp == ~U[2025-08-13 12:00:00Z]
    end

    test "transforms channel.chat.message event" do
      event_data = %{
        "chatter_user_id" => "12345",
        "chatter_user_name" => "chatter123",
        "chatter_user_login" => "chatter123",
        "broadcaster_user_id" => "67890",
        "message_id" => "msg_abc123",
        "message" => %{
          "text" => "Hello world!",
          "color" => "#FF0000",
          "badges" => [%{"set_id" => "subscriber", "id" => "12"}],
          "emotes" => [
            %{"id" => "25", "name" => "Kappa", "format" => ["static"]}
          ],
          "fragments" => [
            %{"type" => "text", "text" => "Hello "},
            %{"type" => "emote", "text" => "Kappa"},
            %{"type" => "text", "text" => "!"}
          ]
        }
      }

      event = Transformer.from_twitch("channel.chat.message", event_data)

      assert event.type == "channel.chat.message"
      assert event.source == :twitch
      assert event.id == "msg_abc123"
      assert event.data.user_id == "12345"
      assert event.data.user_name == "chatter123"
      assert event.data.message_id == "msg_abc123"
      assert event.data.color == "#FF0000"
      assert length(event.data.badges) == 1
      assert length(event.data.emotes) == 1
      assert length(event.data.native_emotes) == 1
      assert List.first(event.data.native_emotes) == "Kappa"
    end

    test "transforms channel.subscribe event" do
      event_data = %{
        "user_id" => "12345",
        "user_name" => "subscriber123",
        "user_login" => "subscriber123",
        "broadcaster_user_id" => "67890",
        "tier" => "1000",
        "is_gift" => false,
        "cumulative_months" => 5,
        "streak_months" => 3,
        "duration_months" => 1
      }

      event = Transformer.from_twitch("channel.subscribe", event_data)

      assert event.type == "channel.subscribe"
      assert event.source == :twitch
      assert event.data.user_name == "subscriber123"
      assert event.data.tier == "1000"
      assert event.data.is_gift == false
      assert event.data.cumulative_months == 5
      assert event.data.streak_months == 3
    end

    test "transforms channel.subscription.gift event" do
      event_data = %{
        "user_id" => "12345",
        "user_name" => "gifter123",
        "broadcaster_user_id" => "67890",
        "total" => 5,
        "tier" => "1000",
        "cumulative_total" => 10,
        "is_anonymous" => false
      }

      event = Transformer.from_twitch("channel.subscription.gift", event_data)

      assert event.type == "channel.subscription.gift"
      assert event.data.total == 5
      assert event.data.tier == "1000"
      assert event.data.is_anonymous == false
    end

    test "transforms channel.cheer event" do
      event_data = %{
        "user_id" => "12345",
        "user_name" => "cheerer123",
        "broadcaster_user_id" => "67890",
        "is_anonymous" => false,
        "message" => "cheer100 Great stream!",
        "bits" => 100
      }

      event = Transformer.from_twitch("channel.cheer", event_data)

      assert event.type == "channel.cheer"
      assert event.data.user_name == "cheerer123"
      assert event.data.bits == 100
      assert event.data.message == "cheer100 Great stream!"
      assert event.data.is_anonymous == false
    end

    test "transforms stream.online event" do
      event_data = %{
        "id" => "stream_123",
        "broadcaster_user_id" => "67890",
        "broadcaster_user_name" => "streamer",
        "broadcaster_user_login" => "streamer",
        "type" => "live",
        "started_at" => "2025-08-13T12:00:00Z"
      }

      event = Transformer.from_twitch("stream.online", event_data)

      assert event.type == "stream.online"
      assert event.id == "stream_123"
      assert event.data.id == "stream_123"
      assert event.data.type == "live"
      assert event.timestamp == ~U[2025-08-13 12:00:00Z]
    end

    test "transforms channel.update event" do
      event_data = %{
        "broadcaster_user_id" => "67890",
        "broadcaster_user_name" => "streamer",
        "title" => "New Stream Title",
        "language" => "en",
        "category_id" => "509658",
        "category_name" => "Just Chatting",
        "content_classification_labels" => ["Gambling"]
      }

      event = Transformer.from_twitch("channel.update", event_data)

      assert event.type == "channel.update"
      assert event.data.title == "New Stream Title"
      assert event.data.category_name == "Just Chatting"
      assert event.data.content_classification_labels == ["Gambling"]
    end

    test "handles unknown event type gracefully" do
      event_data = %{
        "unknown_field" => "test_value",
        "another_field" => 123
      }

      event = Transformer.from_twitch("unknown.event.type", event_data)

      assert event.type == "unknown.event.type"
      assert event.source == :twitch
      assert event.data == event_data
    end

    test "extracts correct event IDs based on type" do
      # Chat message uses message_id
      chat_data = %{"message_id" => "msg_123"}
      chat_event = Transformer.from_twitch("channel.chat.message", chat_data)
      assert chat_event.id == "msg_123"

      # Stream online uses id
      stream_data = %{"id" => "stream_456"}
      stream_event = Transformer.from_twitch("stream.online", stream_data)
      assert stream_event.id == "stream_456"

      # Other events fall back to user_id
      follow_data = %{"user_id" => "user_789"}
      follow_event = Transformer.from_twitch("channel.follow", follow_data)
      assert follow_event.id == "user_789"
    end

    test "handles various timestamp formats" do
      # ISO8601 timestamp
      event1 = Transformer.from_twitch("stream.online", %{"started_at" => "2025-08-13T12:00:00Z"})
      assert event1.timestamp == ~U[2025-08-13 12:00:00Z]

      # Unix timestamp
      event2 = Transformer.from_twitch("channel.follow", %{"timestamp" => 1_691_932_800})
      assert DateTime.to_unix(event2.timestamp) == 1_691_932_800

      # No timestamp - should use current time
      before_time = DateTime.utc_now()
      event3 = Transformer.from_twitch("channel.follow", %{})
      after_time = DateTime.utc_now()
      assert DateTime.compare(event3.timestamp, before_time) in [:gt, :eq]
      assert DateTime.compare(event3.timestamp, after_time) in [:lt, :eq]
    end
  end

  describe "from_obs/2" do
    test "transforms OBS event with prefix" do
      event_data = %{
        "stream_state" => "started",
        "output_active" => true
      }

      event = Transformer.from_obs("StreamStarted", event_data)

      assert event.type == "obs.StreamStarted"
      assert event.source == :obs
      assert event.data == event_data
    end

    test "preserves OBS event data structure" do
      complex_data = %{
        "scene" => %{
          "name" => "Main Scene",
          "sources" => ["Camera", "Screen Capture"]
        },
        "timestamp" => 1_691_932_800
      }

      event = Transformer.from_obs("SceneChanged", complex_data)

      assert event.data == complex_data
    end
  end

  describe "from_system/3" do
    test "transforms system event with prefix" do
      event_data = %{version: "1.0.0", status: "starting"}

      event = Transformer.from_system("startup", event_data)

      assert event.type == "system.startup"
      assert event.source == :system
      assert event.data == event_data
      assert event.meta.priority == :normal
    end

    test "accepts custom priority" do
      event = Transformer.from_system("error", %{}, priority: :critical)

      assert event.meta.priority == :critical
    end

    test "accepts correlation_id" do
      correlation_id = "sys_corr_123"
      event = Transformer.from_system("startup", %{}, correlation_id: correlation_id)

      assert event.meta.correlation_id == correlation_id
    end
  end

  describe "from_ironmon/2" do
    test "transforms IronMON event with prefix" do
      event_data = %{
        challenge: "elite_four",
        pokemon: "Charizard",
        level: 50
      }

      event = Transformer.from_ironmon("checkpoint_reached", event_data)

      assert event.type == "ironmon.checkpoint_reached"
      assert event.source == :ironmon
      assert event.data == event_data
    end
  end

  describe "from_rainwave/2" do
    test "transforms Rainwave event with prefix" do
      event_data = %{
        station: 1,
        song: %{
          title: "Song Title",
          artist: "Artist Name"
        }
      }

      event = Transformer.from_rainwave("song_change", event_data)

      assert event.type == "rainwave.song_change"
      assert event.source == :rainwave
      assert event.data == event_data
    end
  end

  describe "for_websocket/1" do
    test "transforms unified event to WebSocket format" do
      timestamp = ~U[2025-08-13 12:00:00Z]

      unified_event =
        Event.new(
          "channel.follow",
          :twitch,
          %{user_name: "follower123"},
          id: "evt_123",
          timestamp: timestamp
        )

      ws_event = Transformer.for_websocket(unified_event)

      assert ws_event.id == "evt_123"
      assert ws_event.type == "channel.follow"
      assert ws_event.data == %{user_name: "follower123"}
      assert ws_event.timestamp == DateTime.to_unix(timestamp)
    end

    test "maintains data structure in WebSocket format" do
      complex_data = %{
        user: %{id: "123", name: "test"},
        metadata: %{source: "twitch", verified: true}
      }

      unified_event = Event.new("test.event", :twitch, complex_data)
      ws_event = Transformer.for_websocket(unified_event)

      assert ws_event.data == complex_data
    end
  end

  describe "for_database/1" do
    test "transforms unified event to database format" do
      timestamp = ~U[2025-08-13 12:00:00Z]

      unified_event =
        Event.new(
          "channel.follow",
          :twitch,
          %{user_name: "follower123"},
          id: "evt_123",
          timestamp: timestamp,
          correlation_id: "corr_456"
        )

      db_event = Transformer.for_database(unified_event)

      assert db_event.id == "evt_123"
      assert db_event.type == "channel.follow"
      assert db_event.source == "twitch"
      assert db_event.occurred_at == timestamp
      assert %DateTime{} = db_event.processed_at

      # Data should be JSON encoded
      assert is_binary(db_event.data)
      assert Jason.decode!(db_event.data) == %{"user_name" => "follower123"}

      # Metadata should be JSON encoded
      assert is_binary(db_event.metadata)
      metadata = Jason.decode!(db_event.metadata)
      assert metadata["correlation_id"] == "corr_456"
    end
  end

  describe "for_activity_log/1" do
    test "transforms unified event to ActivityLog.Event format" do
      timestamp = ~U[2025-08-13 12:00:00Z]

      unified_event =
        Event.new(
          "channel.chat.message",
          :twitch,
          %{user_id: "12345", user_login: "testuser", user_name: "TestUser", message: %{text: "Hello!"}},
          id: "evt_123",
          timestamp: timestamp,
          correlation_id: "corr_456"
        )

      activity_log_event = Transformer.for_activity_log(unified_event)

      assert activity_log_event.timestamp == timestamp
      assert activity_log_event.event_type == "channel.chat.message"
      assert activity_log_event.user_id == "12345"
      assert activity_log_event.user_login == "testuser"
      assert activity_log_event.user_name == "TestUser"
      assert activity_log_event.correlation_id == "corr_456"

      # Data should be passed as map (not JSON encoded)
      assert is_map(activity_log_event.data)
      assert activity_log_event.data.user_id == "12345"
      assert activity_log_event.data.message == %{text: "Hello!"}
    end

    test "handles events without user fields" do
      unified_event =
        Event.new(
          "system.startup",
          :system,
          %{version: "1.0.0"}
        )

      activity_log_event = Transformer.for_activity_log(unified_event)

      assert activity_log_event.event_type == "system.startup"
      assert activity_log_event.user_id == nil
      assert activity_log_event.user_login == nil
      assert activity_log_event.user_name == nil
      assert activity_log_event.data == %{version: "1.0.0"}
    end

    test "handles string keys in event data" do
      unified_event =
        Event.new(
          "channel.follow",
          :twitch,
          %{"user_id" => "67890", "user_name" => "StringKeyUser"}
        )

      activity_log_event = Transformer.for_activity_log(unified_event)

      assert activity_log_event.user_id == "67890"
      assert activity_log_event.user_name == "StringKeyUser"
      assert activity_log_event.user_login == nil
    end
  end

  describe "for_external_api/1" do
    test "transforms unified event to external API format" do
      timestamp = ~U[2025-08-13 12:00:00Z]

      unified_event =
        Event.new(
          "channel.follow",
          :twitch,
          %{user_name: "follower123"},
          id: "evt_123",
          timestamp: timestamp,
          correlation_id: "corr_456"
        )

      api_event = Transformer.for_external_api(unified_event)

      assert api_event.event_id == "evt_123"
      assert api_event.event_type == "channel.follow"
      assert api_event.source == :twitch
      assert api_event.payload == %{user_name: "follower123"}
      assert api_event.timestamp == DateTime.to_iso8601(timestamp)
      assert api_event.correlation_id == "corr_456"
    end
  end

  describe "emote extraction" do
    test "extracts emotes from chat message" do
      event_data = %{
        "message" => %{
          "emotes" => [
            %{"id" => "25", "name" => "Kappa", "format" => ["static"]},
            %{"id" => "354", "name" => "4Head", "format" => ["static", "animated"]}
          ],
          "fragments" => [
            %{"type" => "text", "text" => "Hello "},
            %{"type" => "emote", "text" => "Kappa"},
            %{"type" => "text", "text" => " world "},
            %{"type" => "emote", "text" => "4Head"}
          ]
        }
      }

      event = Transformer.from_twitch("channel.chat.message", event_data)

      assert length(event.data.emotes) == 2
      assert length(event.data.native_emotes) == 2

      # Check structured emotes
      kappa_emote = Enum.find(event.data.emotes, &(&1.name == "Kappa"))
      assert kappa_emote.id == "25"
      assert kappa_emote.format == ["static"]

      # Check native emotes (text from fragments)
      assert "Kappa" in event.data.native_emotes
      assert "4Head" in event.data.native_emotes
    end

    test "handles missing emote data gracefully" do
      event_data = %{"message" => %{"text" => "No emotes here"}}

      event = Transformer.from_twitch("channel.chat.message", event_data)

      assert event.data.emotes == []
      assert event.data.native_emotes == []
    end
  end

  describe "edge cases and error handling" do
    test "handles empty event data" do
      event = Transformer.from_twitch("channel.follow", %{})

      assert event.type == "channel.follow"
      assert event.source == :twitch
      # All normalized fields should be present but may be nil
      assert Map.has_key?(event.data, :user_id)
      assert Map.has_key?(event.data, :user_name)
    end

    test "handles malformed timestamp gracefully" do
      event = Transformer.from_twitch("channel.follow", %{"followed_at" => "invalid-timestamp"})

      # Should fall back to current time
      assert %DateTime{} = event.timestamp
    end

    test "preserves unknown fields in fallback normalization" do
      unknown_data = %{
        "custom_field" => "custom_value",
        "nested" => %{"data" => "structure"}
      }

      event = Transformer.from_twitch("unknown.event", unknown_data)

      assert event.data == unknown_data
    end
  end
end
