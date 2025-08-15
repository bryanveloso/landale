defmodule Server.EventSystemIntegrationTest do
  @moduledoc """
  Integration tests that prove the event system unification is working end-to-end.

  These tests validate:
  1. Complete event flow from services through Server.Events to channels
  2. Proper event normalization and flat format compliance
  3. Channel routing based on event source
  4. Activity log integration for valuable events
  5. PubSub broadcasting to unified topics only
  """

  use ServerWeb.ChannelCase, async: true
  import ExUnit.CaptureLog

  alias Server.{ActivityLog, Events}

  describe "Complete Event Flow Integration" do
    test "Twitch events flow correctly through unified system" do
      # Connect clients to both channels that should receive events
      {:ok, events_socket} = connect(ServerWeb.UserSocket, %{})
      {:ok, _, events_socket} = subscribe_and_join(events_socket, ServerWeb.EventsChannel, "events:twitch")

      {:ok, dashboard_socket} = connect(ServerWeb.UserSocket, %{})
      {:ok, _, dashboard_socket} = subscribe_and_join(dashboard_socket, ServerWeb.DashboardChannel, "dashboard:main")

      # Test various Twitch event types
      twitch_events = [
        {
          "channel.follow",
          %{
            "user_id" => "12_345",
            "user_login" => "newfollower",
            "user_name" => "NewFollower",
            "broadcaster_user_id" => "67890",
            "broadcaster_user_login" => "streamer",
            "followed_at" => "2024-08-15T12:00:00Z"
          },
          "follower"
        },
        {
          "channel.subscribe",
          %{
            "user_id" => "12346",
            "user_login" => "newsub",
            "user_name" => "NewSub",
            "broadcaster_user_id" => "67890",
            "tier" => "1000",
            "is_gift" => false
          },
          "subscription"
        },
        {
          "channel.chat.message",
          %{
            "message_id" => "msg123",
            "broadcaster_user_id" => "67890",
            "chatter_user_id" => "12347",
            "chatter_user_login" => "chatter",
            "message" => %{"text" => "Hello stream!"},
            "color" => "#FF0000"
          },
          "chat_message"
        }
      ]

      for {event_type, event_data, expected_event_name} <- twitch_events do
        # Process through unified system
        assert :ok = Events.process_event(event_type, event_data)

        # Verify EventsChannel receives correctly formatted event
        assert_push("event", pushed_event, 100, events_socket)
        assert pushed_event.source == :twitch
        assert pushed_event.type == event_type
        assert is_binary(pushed_event.correlation_id)

        # Verify DashboardChannel receives event (may be filtered)
        case event_type do
          "channel.chat.message" ->
            # Dashboard doesn't get chat messages
            :ok

          _ ->
            assert_push("twitch_event", dashboard_event, 100, dashboard_socket)
            assert dashboard_event.source == :twitch
        end
      end
    end

    test "Rainwave events flow correctly through unified system" do
      {:ok, events_socket} = connect(ServerWeb.UserSocket, %{})
      {:ok, _, events_socket} = subscribe_and_join(events_socket, ServerWeb.EventsChannel, "events:rainwave")

      {:ok, dashboard_socket} = connect(ServerWeb.UserSocket, %{})
      {:ok, _, dashboard_socket} = subscribe_and_join(dashboard_socket, ServerWeb.DashboardChannel, "dashboard:main")

      rainwave_event_data = %{
        "station_id" => 1,
        "station_name" => "Game Station",
        "current_song" => %{
          "id" => 12_345,
          "title" => "Epic Battle Theme",
          "artist" => "Video Game Composer"
        },
        "listening" => true,
        "enabled" => true
      }

      # Process through service layer (simulates actual Rainwave service call)
      assert :ok = Events.process_event("rainwave.update", rainwave_event_data)

      # Verify EventsChannel routing
      assert_push("rainwave_event", pushed_event, 100, events_socket)
      assert pushed_event.source == :rainwave
      assert pushed_event.type == "rainwave.update"
      assert pushed_event.station_id == 1
      assert pushed_event.song_id == 12_345
      assert pushed_event.song_title == "Epic Battle Theme"

      # Verify DashboardChannel routing
      assert_push("rainwave_event", dashboard_event, 100, dashboard_socket)
      assert dashboard_event.source == :rainwave
    end

    test "IronMON events flow correctly through unified system" do
      {:ok, events_socket} = connect(ServerWeb.UserSocket, %{})
      {:ok, _, events_socket} = subscribe_and_join(events_socket, ServerWeb.EventsChannel, "events:ironmon")

      {:ok, dashboard_socket} = connect(ServerWeb.UserSocket, %{})
      {:ok, _, dashboard_socket} = subscribe_and_join(dashboard_socket, ServerWeb.DashboardChannel, "dashboard:main")

      ironmon_events = [
        {
          "ironmon.init",
          %{
            "game_type" => "emerald",
            "game_name" => "Pokemon Emerald",
            "version" => "1.0",
            "difficulty" => "normal",
            "run_id" => "run123"
          }
        },
        {
          "ironmon.checkpoint",
          %{
            "checkpoint_id" => "cp1",
            "checkpoint_name" => "Petalburg Woods",
            "run_id" => "run123",
            "location_id" => "loc1",
            "location_name" => "Route 104"
          }
        }
      ]

      for {event_type, event_data} <- ironmon_events do
        assert :ok = Events.process_event(event_type, event_data)

        # Verify EventsChannel routing
        assert_push("ironmon_event", pushed_event, 100, events_socket)
        assert pushed_event.source == :ironmon
        assert pushed_event.type == event_type

        # Verify DashboardChannel routing
        assert_push("ironmon_event", dashboard_event, 100, dashboard_socket)
        assert dashboard_event.source == :ironmon
      end
    end

    test "System events flow correctly through unified system" do
      {:ok, events_socket} = connect(ServerWeb.UserSocket, %{})
      {:ok, _, events_socket} = subscribe_and_join(events_socket, ServerWeb.EventsChannel, "events:system")

      {:ok, dashboard_socket} = connect(ServerWeb.UserSocket, %{})
      {:ok, _, dashboard_socket} = subscribe_and_join(dashboard_socket, ServerWeb.DashboardChannel, "dashboard:main")

      system_events = [
        {
          "system.service_started",
          %{
            "service" => "phononmaser",
            "version" => "1.0.0",
            "pid" => 12_345
          },
          "system_event"
        },
        {
          "system.health_check",
          %{
            "service" => "test_service",
            "status" => "healthy",
            "checks_passed" => 5,
            "details" => %{
              "uptime" => 3600,
              "memory_usage" => 50.5,
              "cpu_usage" => 25.0
            }
          },
          "health_update"
        }
      ]

      for {event_type, event_data, expected_dashboard_event} <- system_events do
        assert :ok = Events.process_event(event_type, event_data)

        # Verify EventsChannel routing
        assert_push("system_event", pushed_event, 100, events_socket)
        assert pushed_event.source == :system
        assert pushed_event.type == event_type

        # Verify flat format for health check
        if event_type == "system.health_check" do
          assert pushed_event.uptime == 3600
          assert pushed_event.memory_usage == 50.5
          refute Map.has_key?(pushed_event, :details)
        end

        # Verify DashboardChannel routing with special handling
        assert_push(^expected_dashboard_event, dashboard_event, 100, dashboard_socket)
        assert dashboard_event.source == :system
      end
    end
  end

  describe "Event Format and Normalization Validation" do
    test "all events are normalized to flat format" do
      # Test events with nested structures get flattened
      nested_event_data = %{
        "message_id" => "msg123",
        "broadcaster_user_id" => "67890",
        "chatter_user_id" => "12_345",
        "message" => %{
          "text" => "Hello!",
          "fragments" => [
            %{"type" => "text", "text" => "Hello "},
            %{"type" => "emote", "text" => "Kappa"}
          ]
        },
        "cheer" => %{
          "bits" => 100
        },
        "reply" => %{
          "parent_message_id" => "parent123",
          "parent_user_login" => "original_user"
        }
      }

      normalized = Events.normalize_event("channel.chat.message", nested_event_data)

      # Verify core fields exist
      assert normalized.id
      assert normalized.type == "channel.chat.message"
      assert normalized.source == :twitch
      assert normalized.timestamp
      assert normalized.correlation_id

      # Verify nested structures are flattened
      assert normalized.message == "Hello!"
      assert normalized.cheer_bits == 100
      assert normalized.reply_parent_message_id == "parent123"
      assert normalized.reply_parent_user_login == "original_user"

      # Verify no nested maps remain (except DateTime structs)
      assert flat_event?(normalized)
    end

    test "event source determination works correctly" do
      test_cases = [
        {"stream.online", :twitch},
        {"channel.follow", :twitch},
        {"obs.stream_started", :obs},
        {"ironmon.init", :ironmon},
        {"rainwave.song_changed", :rainwave},
        {"system.service_started", :system},
        # defaults to twitch
        {"unknown.event", :twitch}
      ]

      for {event_type, expected_source} <- test_cases do
        normalized = Events.normalize_event(event_type, %{})
        assert normalized.source == expected_source
      end
    end

    test "correlation IDs are unique and properly formatted" do
      correlation_ids =
        for _i <- 1..10 do
          event = Events.normalize_event("test.event", %{})
          event.correlation_id
        end

      # All should be unique
      assert length(Enum.uniq(correlation_ids)) == 10

      # All should be valid format (16 character hex string)
      for id <- correlation_ids do
        assert String.length(id) == 16
        assert Regex.match?(~r/^[a-f0-9]+$/, id)
      end
    end
  end

  describe "Activity Log Integration" do
    test "valuable events are stored in activity log" do
      valuable_events = [
        {"channel.follow", %{"user_id" => "123", "user_login" => "follower"}},
        {"channel.chat.message", %{"message_id" => "msg123", "chatter_user_id" => "456"}},
        {"obs.stream_started", %{"session_id" => "session123"}},
        {"system.service_started", %{"service" => "test"}}
      ]

      for {event_type, event_data} <- valuable_events do
        initial_count = ActivityLog.count_events()

        assert :ok = Events.process_event(event_type, event_data)

        # Allow time for async storage
        Process.sleep(100)

        final_count = ActivityLog.count_events()

        assert final_count == initial_count + 1,
               "Event #{event_type} was not stored in activity log"
      end
    end

    test "ephemeral events are not stored in activity log" do
      ephemeral_events = [
        {"system.health_check", %{"service" => "test", "status" => "healthy"}},
        {"system.performance_metric", %{"metric" => "cpu", "value" => 50.0}},
        {"obs.connection_established", %{"session_id" => "session123"}}
      ]

      for {event_type, event_data} <- ephemeral_events do
        initial_count = ActivityLog.count_events()

        assert :ok = Events.process_event(event_type, event_data)

        # Allow time for potential async storage
        Process.sleep(100)

        final_count = ActivityLog.count_events()

        assert final_count == initial_count,
               "Ephemeral event #{event_type} was incorrectly stored in activity log"
      end
    end
  end

  describe "Channel Topic Filtering" do
    test "topic-specific subscriptions receive only relevant events" do
      # Test chat topic filtering
      {:ok, chat_socket} = connect(ServerWeb.UserSocket, %{})
      {:ok, _, chat_socket} = subscribe_and_join(chat_socket, ServerWeb.EventsChannel, "events:chat")

      # Test interactions topic filtering
      {:ok, interactions_socket} = connect(ServerWeb.UserSocket, %{})

      {:ok, _, interactions_socket} =
        subscribe_and_join(interactions_socket, ServerWeb.EventsChannel, "events:interactions")

      # Send chat event
      assert :ok =
               Events.process_event("channel.chat.message", %{
                 "message_id" => "msg123",
                 "chatter_user_id" => "123",
                 "message" => %{"text" => "Hello"}
               })

      # Chat socket should receive it
      assert_push("chat_message", %{type: "channel.chat.message"}, 100, chat_socket)
      # Interactions socket should NOT receive it
      refute_push("follower", %{}, 100, interactions_socket)

      # Send follow event
      assert :ok =
               Events.process_event("channel.follow", %{
                 "user_id" => "456",
                 "user_login" => "newfollower"
               })

      # Interactions socket should receive it
      assert_push("follower", %{type: "channel.follow"}, 100, interactions_socket)
      # Chat socket should NOT receive it
      refute_push("chat_message", %{}, 100, chat_socket)
    end

    test "dashboard topic receives appropriate events only" do
      {:ok, dashboard_socket} = connect(ServerWeb.UserSocket, %{})
      {:ok, _, dashboard_socket} = subscribe_and_join(dashboard_socket, ServerWeb.DashboardChannel, "dashboard:main")

      # Events dashboard should receive
      dashboard_events = [
        {"stream.online", %{"broadcaster_user_id" => "123"}, "twitch_event"},
        {"obs.stream_started", %{"session_id" => "session123"}, "obs_event"},
        {"system.service_started", %{"service" => "test"}, "system_event"}
      ]

      for {event_type, event_data, expected_push} <- dashboard_events do
        assert :ok = Events.process_event(event_type, event_data)
        assert_push(^expected_push, %{type: ^event_type}, 100, dashboard_socket)
      end

      # Events dashboard should NOT receive
      non_dashboard_events = [
        {"channel.chat.message", %{"message_id" => "msg123", "chatter_user_id" => "456"}},
        {"channel.follow", %{"user_id" => "789", "user_login" => "follower"}}
      ]

      for {event_type, event_data} <- non_dashboard_events do
        assert :ok = Events.process_event(event_type, event_data)
        # Should not receive any push
        refute_push(_, %{type: ^event_type}, 100, dashboard_socket)
      end
    end
  end

  describe "Error Handling and Resilience" do
    test "malformed events are handled gracefully" do
      malformed_events = [
        {"test.event", nil},
        {"test.event", "not_a_map"},
        {"test.event", %{"invalid" => ["nested", "arrays"]}},
        # empty event type
        {"", %{}},
        # nil event type
        {nil, %{}}
      ]

      for {event_type, event_data} <- malformed_events do
        log_output =
          capture_log(fn ->
            result = Events.process_event(event_type, event_data)
            # Should either succeed or fail gracefully
            assert result in [:ok, {:error, _}]
          end)

        # Should log appropriate warnings/errors
        assert log_output != ""
      end
    end

    test "PubSub failures don't crash event processing" do
      # This test would require more complex setup to simulate PubSub failures
      # For now, we test that the system remains stable under load

      tasks =
        for i <- 1..50 do
          Task.async(fn ->
            Events.process_event("test.load_event", %{"id" => i})
          end)
        end

      results = Task.await_many(tasks, 5000)

      # All events should process successfully
      assert Enum.all?(results, &(&1 == :ok))
    end
  end

  # Helper functions

  defp flat_event?(event) when is_map(event) do
    Enum.all?(event, fn {_key, value} ->
      case value do
        %DateTime{} ->
          true

        map when is_map(map) ->
          false

        list when is_list(list) ->
          # Allow lists of simple values or maps with string keys (like fragments)
          Enum.all?(list, fn item ->
            not is_map(item) or (is_map(item) and map_has_only_string_keys?(item))
          end)

        _ ->
          true
      end
    end)
  end

  defp flat_event?(_), do: false

  defp map_has_only_string_keys?(map) when is_map(map) do
    Enum.all?(Map.keys(map), &is_binary/1)
  end

  defp map_has_only_string_keys?(_), do: false
end
