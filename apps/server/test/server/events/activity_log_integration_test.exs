defmodule Server.Events.ActivityLogIntegrationTest do
  use Server.DataCase, async: false

  alias Server.ActivityLog
  alias Server.Events.{Event, Router, Transformer}
  alias Server.Repo

  setup do
    # Start the router for this test
    start_supervised!({Router, batch_types: []})

    # Clear any existing events
    Repo.delete_all(Server.ActivityLog.Event)

    :ok
  end

  describe "Event storage integration" do
    test "events are stored in database via Router" do
      # Create a test event with user data
      event =
        Event.new(
          "channel.chat.message",
          :twitch,
          %{
            user_id: "12345",
            user_login: "testuser",
            user_name: "TestUser",
            message: %{text: "Hello world!"}
          },
          correlation_id: "test-correlation"
        )

      # Route the event (this should store it in ActivityLog)
      Router.route(event)

      # Wait longer for the async task to complete
      Process.sleep(500)

      # Verify the event was stored in the database
      stored_events = ActivityLog.list_recent_events(limit: 10)
      assert length(stored_events) == 1

      stored_event = List.first(stored_events)
      assert stored_event.event_type == "channel.chat.message"
      assert stored_event.user_id == "12345"
      assert stored_event.user_login == "testuser"
      assert stored_event.user_name == "TestUser"
      assert stored_event.correlation_id == "test-correlation"
      # Data is stored as a map with string keys due to Ecto JSON field handling
      assert stored_event.data["user_id"] == "12345"
      assert stored_event.data["message"] == %{"text" => "Hello world!"}
    end

    test "events without user data are stored correctly" do
      event =
        Event.new(
          "system.startup",
          :system,
          %{version: "1.0.0", component: "test"}
        )

      Router.route(event)
      Process.sleep(500)

      stored_events = ActivityLog.list_recent_events(limit: 10)
      assert length(stored_events) == 1

      stored_event = List.first(stored_events)
      assert stored_event.event_type == "system.startup"
      assert stored_event.user_id == nil
      assert stored_event.user_login == nil
      assert stored_event.user_name == nil
      # Data is stored with string keys due to Ecto JSON field handling
      assert stored_event.data["version"] == "1.0.0"
      assert stored_event.data["component"] == "test"
    end

    test "Transformer.for_activity_log produces valid ActivityLog.Event data" do
      event =
        Event.new(
          "channel.follow",
          :twitch,
          %{user_id: "54321", user_name: "Follower"},
          correlation_id: "follow-test"
        )

      # Transform the event
      activity_log_data = Transformer.for_activity_log(event)

      # Store directly using ActivityLog.store_event
      {:ok, stored_event} = ActivityLog.store_event(activity_log_data)

      assert stored_event.event_type == "channel.follow"
      assert stored_event.user_id == "54321"
      assert stored_event.user_name == "Follower"
      assert stored_event.correlation_id == "follow-test"
    end

    test "handles multiple events correctly" do
      events = [
        Event.new("channel.follow", :twitch, %{user_id: "1", user_name: "User1"}),
        Event.new("channel.follow", :twitch, %{user_id: "2", user_name: "User2"}),
        Event.new("system.test", :system, %{test_id: "123"})
      ]

      Enum.each(events, &Router.route/1)
      # Wait longer for all async tasks
      Process.sleep(1000)

      stored_events = ActivityLog.list_recent_events(limit: 10)
      assert length(stored_events) == 3

      # Verify we have the right event types
      event_types = Enum.map(stored_events, & &1.event_type)
      assert "channel.follow" in event_types
      assert "system.test" in event_types

      # Verify user data is preserved for follow events
      follow_events = Enum.filter(stored_events, &(&1.event_type == "channel.follow"))
      user_names = Enum.map(follow_events, & &1.user_name)
      assert "User1" in user_names
      assert "User2" in user_names
    end
  end
end
