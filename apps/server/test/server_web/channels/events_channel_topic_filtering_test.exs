defmodule ServerWeb.EventsChannelTopicFilteringTest do
  @moduledoc """
  Test suite specifically for EventsChannel topic filtering logic.
  Ensures that topic-specific subscriptions only receive relevant events.
  """

  use ServerWeb.ChannelCase, async: true

  describe "EventsChannel topic filtering" do
    test "events:chat only receives chat-related events" do
      {:ok, socket} = connect(ServerWeb.UserSocket, %{})
      {:ok, _, socket} = subscribe_and_join(socket, ServerWeb.EventsChannel, "events:chat")

      # Chat message should be received
      chat_event = %{
        type: "channel.chat.message",
        source: :twitch,
        user_name: "TestUser",
        message: "test message",
        timestamp: DateTime.utc_now()
      }

      send(socket.channel_pid, {:event, chat_event})
      assert_push "chat_message", %{type: "channel.chat.message"}

      # Chat clear should be received
      chat_clear_event = %{
        type: "channel.chat.clear",
        source: :twitch,
        broadcaster_user_name: "Streamer",
        timestamp: DateTime.utc_now()
      }

      send(socket.channel_pid, {:event, chat_clear_event})
      assert_push "chat_clear", %{type: "channel.chat.clear"}

      # Follow event should NOT be received
      follow_event = %{
        type: "channel.follow",
        source: :twitch,
        user_name: "NewFollower",
        timestamp: DateTime.utc_now()
      }

      send(socket.channel_pid, {:event, follow_event})
      refute_push "follower", %{type: "channel.follow"}, 100

      # OBS event should NOT be received
      obs_event = %{
        type: "obs.stream_started",
        source: :obs,
        timestamp: DateTime.utc_now()
      }

      send(socket.channel_pid, {:event, obs_event})
      refute_push "obs_event", %{type: "obs.stream_started"}, 100
    end

    test "events:interactions only receives interaction events" do
      {:ok, socket} = connect(ServerWeb.UserSocket, %{})
      {:ok, _, socket} = subscribe_and_join(socket, ServerWeb.EventsChannel, "events:interactions")

      # Follow event should be received
      follow_event = %{
        type: "channel.follow",
        source: :twitch,
        user_name: "NewFollower",
        timestamp: DateTime.utc_now()
      }

      send(socket.channel_pid, {:event, follow_event})
      assert_push "follower", %{type: "channel.follow"}

      # Subscribe event should be received
      sub_event = %{
        type: "channel.subscribe",
        source: :twitch,
        user_name: "NewSub",
        tier: "1000",
        timestamp: DateTime.utc_now()
      }

      send(socket.channel_pid, {:event, sub_event})
      assert_push "subscription", %{type: "channel.subscribe"}

      # Cheer event should be received
      cheer_event = %{
        type: "channel.cheer",
        source: :twitch,
        user_name: "Cheerleader",
        bits: 100,
        timestamp: DateTime.utc_now()
      }

      send(socket.channel_pid, {:event, cheer_event})
      assert_push "cheer", %{type: "channel.cheer"}

      # Chat message should NOT be received
      chat_event = %{
        type: "channel.chat.message",
        source: :twitch,
        user_name: "TestUser",
        message: "test message",
        timestamp: DateTime.utc_now()
      }

      send(socket.channel_pid, {:event, chat_event})
      refute_push "chat_message", %{type: "channel.chat.message"}, 100

      # Channel update should NOT be received
      update_event = %{
        type: "channel.update",
        source: :twitch,
        title: "New Title",
        timestamp: DateTime.utc_now()
      }

      send(socket.channel_pid, {:event, update_event})
      refute_push "channel_update", %{type: "channel.update"}, 100
    end

    test "events:goals only receives goal-related events" do
      {:ok, socket} = connect(ServerWeb.UserSocket, %{})
      {:ok, _, socket} = subscribe_and_join(socket, ServerWeb.EventsChannel, "events:goals")

      # Goal begin should be received
      goal_begin_event = %{
        type: "channel.goal.begin",
        source: :twitch,
        description: "New Goal",
        target_amount: 100,
        timestamp: DateTime.utc_now()
      }

      send(socket.channel_pid, {:event, goal_begin_event})
      assert_push "twitch_event", %{type: "channel.goal.begin"}

      # Goal progress should be received
      goal_progress_event = %{
        type: "channel.goal.progress",
        source: :twitch,
        current_amount: 50,
        target_amount: 100,
        timestamp: DateTime.utc_now()
      }

      send(socket.channel_pid, {:event, goal_progress_event})
      assert_push "twitch_event", %{type: "channel.goal.progress"}

      # Follow event should NOT be received
      follow_event = %{
        type: "channel.follow",
        source: :twitch,
        user_name: "NewFollower",
        timestamp: DateTime.utc_now()
      }

      send(socket.channel_pid, {:event, follow_event})
      refute_push "follower", %{type: "channel.follow"}, 100

      # Chat message should NOT be received
      chat_event = %{
        type: "channel.chat.message",
        source: :twitch,
        user_name: "TestUser",
        message: "test message",
        timestamp: DateTime.utc_now()
      }

      send(socket.channel_pid, {:event, chat_event})
      refute_push "chat_message", %{type: "channel.chat.message"}, 100
    end

    test "events:dashboard receives connection and system status events" do
      {:ok, socket} = connect(ServerWeb.UserSocket, %{})
      {:ok, _, socket} = subscribe_and_join(socket, ServerWeb.EventsChannel, "events:dashboard")

      # Stream online should be received
      stream_online_event = %{
        type: "stream.online",
        source: :twitch,
        broadcaster_user_name: "Streamer",
        timestamp: DateTime.utc_now()
      }

      send(socket.channel_pid, {:event, stream_online_event})
      assert_push "twitch_event", %{type: "stream.online"}

      # OBS connection events should be received
      obs_connection_event = %{
        type: "obs.connection_established",
        source: :obs,
        session_id: "test-session",
        timestamp: DateTime.utc_now()
      }

      send(socket.channel_pid, {:event, obs_connection_event})
      assert_push "obs_event", %{type: "obs.connection_established"}

      # System service events should be received
      system_event = %{
        type: "system.service_started",
        source: :system,
        service_name: "test-service",
        timestamp: DateTime.utc_now()
      }

      send(socket.channel_pid, {:event, system_event})
      assert_push "system_event", %{type: "system.service_started"}

      # Chat messages should NOT be received
      chat_event = %{
        type: "channel.chat.message",
        source: :twitch,
        user_name: "TestUser",
        message: "test message",
        timestamp: DateTime.utc_now()
      }

      send(socket.channel_pid, {:event, chat_event})
      refute_push "chat_message", %{type: "channel.chat.message"}, 100

      # Follows should NOT be received
      follow_event = %{
        type: "channel.follow",
        source: :twitch,
        user_name: "NewFollower",
        timestamp: DateTime.utc_now()
      }

      send(socket.channel_pid, {:event, follow_event})
      refute_push "follower", %{type: "channel.follow"}, 100
    end

    test "events:all still receives everything (backward compatibility)" do
      {:ok, socket} = connect(ServerWeb.UserSocket, %{})
      {:ok, _, socket} = subscribe_and_join(socket, ServerWeb.EventsChannel, "events:all")

      # Should receive chat events
      chat_event = %{
        type: "channel.chat.message",
        source: :twitch,
        user_name: "TestUser",
        message: "test message",
        timestamp: DateTime.utc_now()
      }

      send(socket.channel_pid, {:event, chat_event})
      assert_push "chat_message", %{type: "channel.chat.message"}

      # Should receive follow events
      follow_event = %{
        type: "channel.follow",
        source: :twitch,
        user_name: "NewFollower",
        timestamp: DateTime.utc_now()
      }

      send(socket.channel_pid, {:event, follow_event})
      assert_push "follower", %{type: "channel.follow"}

      # Should receive OBS events
      obs_event = %{
        type: "obs.stream_started",
        source: :obs,
        timestamp: DateTime.utc_now()
      }

      send(socket.channel_pid, {:event, obs_event})
      assert_push "obs_event", %{type: "obs.stream_started"}

      # Should receive system events
      system_event = %{
        type: "system.service_started",
        source: :system,
        service_name: "test-service",
        timestamp: DateTime.utc_now()
      }

      send(socket.channel_pid, {:event, system_event})
      assert_push "system_event", %{type: "system.service_started"}
    end

    test "events:twitch still receives all twitch events (backward compatibility)" do
      {:ok, socket} = connect(ServerWeb.UserSocket, %{})
      {:ok, _, socket} = subscribe_and_join(socket, ServerWeb.EventsChannel, "events:twitch")

      # Should receive all Twitch events
      events = [
        %{type: "channel.chat.message", source: :twitch, user_name: "TestUser", message: "test"},
        %{type: "channel.follow", source: :twitch, user_name: "NewFollower"},
        %{type: "channel.subscribe", source: :twitch, user_name: "NewSub"},
        %{type: "channel.cheer", source: :twitch, user_name: "Cheerleader", bits: 100},
        %{type: "channel.update", source: :twitch, title: "New Title"},
        %{type: "stream.online", source: :twitch, broadcaster_user_name: "Streamer"}
      ]

      for event <- events do
        event_with_timestamp = Map.put(event, :timestamp, DateTime.utc_now())
        send(socket.channel_pid, {:event, event_with_timestamp})

        event_type = event.type

        case event_type do
          "channel.chat.message" -> assert_push "chat_message", %{type: "channel.chat.message"}
          "channel.follow" -> assert_push "follower", %{type: "channel.follow"}
          "channel.subscribe" -> assert_push "subscription", %{type: "channel.subscribe"}
          "channel.cheer" -> assert_push "cheer", %{type: "channel.cheer"}
          "channel.update" -> assert_push "channel_update", %{type: "channel.update"}
          _ -> assert_push "twitch_event", %{type: ^event_type}
        end
      end

      # Should NOT receive non-Twitch events
      obs_event = %{
        type: "obs.stream_started",
        source: :obs,
        timestamp: DateTime.utc_now()
      }

      send(socket.channel_pid, {:event, obs_event})
      refute_push "obs_event", %{type: "obs.stream_started"}, 100
    end
  end
end
