defmodule Server.ActivityLogTest do
  use Server.DataCase, async: true

  @moduletag :database

  alias Server.ActivityLog

  describe "store_event/1" do
    test "stores event with valid attributes" do
      attrs = valid_event_attrs()

      assert {:ok, event} = ActivityLog.store_event(attrs)
      assert event.event_type == "channel.chat.message"
      assert event.user_id == "123456"
      assert event.user_login == "testuser"
      assert event.data["message"] == "Hello world"
      assert event.correlation_id != nil
    end

    test "returns error with invalid attributes" do
      attrs = %{
        # Missing required fields
        event_type: "channel.chat.message"
      }

      assert {:error, %Ecto.Changeset{}} = ActivityLog.store_event(attrs)
    end

    test "validates event_type is supported" do
      attrs = valid_event_attrs(%{event_type: "unsupported.event"})

      assert {:error, changeset} = ActivityLog.store_event(attrs)
      assert "unsupported event type" in errors_on(changeset).event_type
    end

    test "validates data is not empty" do
      attrs = valid_event_attrs(%{data: %{}})

      assert {:error, changeset} = ActivityLog.store_event(attrs)
      assert "cannot be empty" in errors_on(changeset).data
    end

    test "validates data is a map" do
      attrs = valid_event_attrs(%{data: "not a map"})

      assert {:error, changeset} = ActivityLog.store_event(attrs)
      assert "must be a map" in errors_on(changeset).data
    end
  end

  describe "list_recent_events/1" do
    test "returns empty list when no events exist" do
      assert ActivityLog.list_recent_events() == []
    end

    test "returns events ordered by timestamp desc" do
      older = insert_event(%{timestamp: ~U[2024-01-01 12:00:00.000000Z]})
      newer = insert_event(%{timestamp: ~U[2024-01-01 13:00:00.000000Z]})

      result = ActivityLog.list_recent_events()

      assert length(result) == 2
      assert hd(result).id == newer.id
      assert List.last(result).id == older.id
    end

    test "respects limit option" do
      insert_event(%{data: %{"message" => "first"}})
      insert_event(%{data: %{"message" => "second"}})
      insert_event(%{data: %{"message" => "third"}})

      result = ActivityLog.list_recent_events(limit: 2)

      assert length(result) == 2
    end

    test "filters by event_type" do
      chat_event = insert_event(%{event_type: "channel.chat.message"})
      _follow_event = insert_event(%{event_type: "channel.follow"})

      result = ActivityLog.list_recent_events(event_type: "channel.chat.message")

      assert length(result) == 1
      assert hd(result).id == chat_event.id
    end

    test "filters by user_id" do
      user1_event = insert_event(%{user_id: "user_123"})
      _user2_event = insert_event(%{user_id: "user_456"})

      result = ActivityLog.list_recent_events(user_id: "user_123")

      assert length(result) == 1
      assert hd(result).id == user1_event.id
    end
  end

  describe "get_activity_stats/1" do
    test "returns zero stats when no events exist" do
      stats = ActivityLog.get_activity_stats(24)

      assert stats.total_events == 0
      assert stats.unique_users == 0
      assert stats.chat_messages == 0
      assert stats.follows == 0
      assert stats.subscriptions == 0
      assert stats.cheers == 0
    end

    test "counts events within time window" do
      recent_time = DateTime.utc_now() |> DateTime.add(-1, :hour)
      old_time = DateTime.utc_now() |> DateTime.add(-25, :hour)

      insert_event(%{timestamp: recent_time, event_type: "channel.chat.message"})
      insert_event(%{timestamp: recent_time, event_type: "channel.follow"})
      _old_event = insert_event(%{timestamp: old_time, event_type: "channel.chat.message"})

      stats = ActivityLog.get_activity_stats(24)

      assert stats.total_events == 2
      assert stats.chat_messages == 1
      assert stats.follows == 1
    end
  end

  describe "get_most_active_users/2" do
    test "returns empty list when no events exist" do
      assert ActivityLog.get_most_active_users(24, 10) == []
    end

    test "returns users ordered by message count" do
      recent_time = DateTime.utc_now() |> DateTime.add(-1, :hour)

      # User 1: 3 chat messages
      insert_event(%{timestamp: recent_time, user_login: "user1", event_type: "channel.chat.message"})
      insert_event(%{timestamp: recent_time, user_login: "user1", event_type: "channel.chat.message"})
      insert_event(%{timestamp: recent_time, user_login: "user1", event_type: "channel.chat.message"})

      # User 2: 1 chat message
      insert_event(%{timestamp: recent_time, user_login: "user2", event_type: "channel.chat.message"})

      result = ActivityLog.get_most_active_users(24, 10)

      assert length(result) == 2
      assert hd(result).user_login == "user1"
      assert hd(result).message_count == 3
      assert List.last(result).user_login == "user2"
      assert List.last(result).message_count == 1
    end

    test "respects limit parameter" do
      recent_time = DateTime.utc_now() |> DateTime.add(-1, :hour)

      insert_event(%{timestamp: recent_time, user_login: "user1", event_type: "channel.chat.message"})
      insert_event(%{timestamp: recent_time, user_login: "user2", event_type: "channel.chat.message"})
      insert_event(%{timestamp: recent_time, user_login: "user3", event_type: "channel.chat.message"})

      result = ActivityLog.get_most_active_users(24, 2)

      assert length(result) == 2
    end
  end

  describe "upsert_user/1" do
    test "creates new user with valid attributes" do
      attrs = %{
        twitch_id: "123456",
        login: "testuser",
        display_name: "TestUser"
      }

      assert {:ok, user} = ActivityLog.upsert_user(attrs)
      assert user.twitch_id == "123456"
      assert user.login == "testuser"
      assert user.display_name == "TestUser"
    end

    test "updates existing user" do
      attrs = %{
        twitch_id: "123456",
        login: "testuser",
        display_name: "TestUser"
      }

      {:ok, _user} = ActivityLog.upsert_user(attrs)

      updated_attrs = %{
        twitch_id: "123456",
        login: "testuser",
        display_name: "UpdatedUser",
        nickname: "Tester"
      }

      assert {:ok, updated_user} = ActivityLog.upsert_user(updated_attrs)
      assert updated_user.display_name == "UpdatedUser"
      assert updated_user.nickname == "Tester"
    end

    test "returns error with invalid attributes" do
      attrs = %{
        # Missing required twitch_id
        login: "testuser"
      }

      assert {:error, %Ecto.Changeset{}} = ActivityLog.upsert_user(attrs)
    end
  end

  # Helper functions

  defp valid_event_attrs(attrs \\ %{}) do
    %{
      timestamp: DateTime.utc_now(),
      event_type: "channel.chat.message",
      user_id: "123456",
      user_login: "testuser",
      user_name: "TestUser",
      data: %{
        "message" => "Hello world",
        "user_id" => "123456",
        "type" => "channel.chat.message"
      },
      correlation_id: "test-correlation-id"
    }
    |> Map.merge(attrs)
  end

  defp insert_event(attrs) do
    {:ok, event} =
      valid_event_attrs(attrs)
      |> ActivityLog.store_event()

    event
  end
end
