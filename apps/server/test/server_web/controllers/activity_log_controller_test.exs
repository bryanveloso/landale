defmodule ServerWeb.ActivityLogControllerTest do
  use ServerWeb.ConnCase, async: true

  @moduletag :web

  alias Server.ActivityLog

  describe "GET /api/activity/events" do
    test "returns empty list when no events exist", %{conn: conn} do
      response =
        conn
        |> get("/api/activity/events")
        |> json_response(200)

      assert response["success"] == true
      assert response["data"]["events"] == []
      assert response["data"]["count"] == 0
    end

    test "returns list of events", %{conn: conn} do
      # Insert test events
      insert_event(%{
        event_type: "channel.chat.message",
        user_login: "testuser",
        data: %{"message" => "Hello world"}
      })

      insert_event(%{
        event_type: "channel.follow",
        user_login: "newfollower",
        data: %{"user_id" => "123456"}
      })

      response =
        conn
        |> get("/api/activity/events")
        |> json_response(200)

      assert response["success"] == true
      assert length(response["data"]["events"]) == 2
      assert response["data"]["count"] == 2

      # Verify event structure
      event = hd(response["data"]["events"])
      assert Map.has_key?(event, "id")
      assert Map.has_key?(event, "timestamp")
      assert Map.has_key?(event, "event_type")
      assert Map.has_key?(event, "data")
    end

    test "filters events by event_type", %{conn: conn} do
      insert_event(%{event_type: "channel.chat.message"})
      insert_event(%{event_type: "channel.follow"})

      response =
        conn
        |> get("/api/activity/events?event_type=channel.chat.message")
        |> json_response(200)

      assert response["success"] == true
      assert length(response["data"]["events"]) == 1
      assert hd(response["data"]["events"])["event_type"] == "channel.chat.message"
    end

    test "filters events by user_id", %{conn: conn} do
      insert_event(%{user_id: "user_123"})
      insert_event(%{user_id: "user_456"})

      response =
        conn
        |> get("/api/activity/events?user_id=user_123")
        |> json_response(200)

      assert response["success"] == true
      assert length(response["data"]["events"]) == 1
      assert hd(response["data"]["events"])["user_id"] == "user_123"
    end

    test "respects limit parameter", %{conn: conn} do
      # Insert 3 events
      for i <- 1..3 do
        insert_event(%{data: %{"message" => "Test #{i}"}})
      end

      response =
        conn
        |> get("/api/activity/events?limit=2")
        |> json_response(200)

      assert response["success"] == true
      assert length(response["data"]["events"]) == 2
      assert response["data"]["count"] == 2
    end

    test "returns error for invalid limit parameter", %{conn: conn} do
      response =
        conn
        |> get("/api/activity/events?limit=invalid")
        |> json_response(400)

      assert response["success"] == false
      assert response["error"]["code"] == "invalid_parameters"
    end
  end

  describe "GET /api/activity/stats" do
    test "returns zero stats when no events exist", %{conn: conn} do
      response =
        conn
        |> get("/api/activity/stats")
        |> json_response(200)

      assert response["success"] == true
      assert response["data"]["stats"]["total_events"] == 0
      assert response["data"]["stats"]["unique_users"] == 0
      assert response["data"]["most_active_users"] == []
      assert response["data"]["time_window_hours"] == 24
    end

    test "returns activity statistics", %{conn: conn} do
      recent_time = DateTime.utc_now() |> DateTime.add(-1, :hour)

      # Insert test events
      insert_event(%{
        timestamp: recent_time,
        event_type: "channel.chat.message",
        user_login: "user1"
      })

      insert_event(%{
        timestamp: recent_time,
        event_type: "channel.follow",
        user_login: "user2"
      })

      response =
        conn
        |> get("/api/activity/stats")
        |> json_response(200)

      assert response["success"] == true
      assert response["data"]["stats"]["total_events"] == 2
      assert response["data"]["stats"]["chat_messages"] == 1
      assert response["data"]["stats"]["follows"] == 1
      assert response["data"]["time_window_hours"] == 24
    end

    test "returns most active users", %{conn: conn} do
      recent_time = DateTime.utc_now() |> DateTime.add(-1, :hour)

      # User 1: 2 chat messages
      insert_event(%{
        timestamp: recent_time,
        event_type: "channel.chat.message",
        user_login: "user1"
      })

      insert_event(%{
        timestamp: recent_time,
        event_type: "channel.chat.message",
        user_login: "user1"
      })

      # User 2: 1 chat message
      insert_event(%{
        timestamp: recent_time,
        event_type: "channel.chat.message",
        user_login: "user2"
      })

      response =
        conn
        |> get("/api/activity/stats")
        |> json_response(200)

      assert response["success"] == true
      active_users = response["data"]["most_active_users"]
      assert length(active_users) == 2
      assert hd(active_users)["user_login"] == "user1"
      assert hd(active_users)["message_count"] == 2
    end

    test "respects custom time window", %{conn: conn} do
      response =
        conn
        |> get("/api/activity/stats?hours=12")
        |> json_response(200)

      assert response["success"] == true
      assert response["data"]["time_window_hours"] == 12
    end

    test "returns error for invalid hours parameter", %{conn: conn} do
      response =
        conn
        |> get("/api/activity/stats?hours=invalid")
        |> json_response(400)

      assert response["success"] == false
      assert response["error"]["code"] == "invalid_parameters"
    end
  end

  # Helper functions
  defp insert_event(attrs) do
    default_attrs = %{
      timestamp: DateTime.utc_now(),
      event_type: "channel.chat.message",
      user_id: "123456",
      user_login: "testuser",
      user_name: "TestUser",
      data: %{
        "message" => "Test message",
        "type" => "channel.chat.message"
      },
      correlation_id: "test-correlation-id"
    }

    {:ok, event} =
      default_attrs
      |> Map.merge(attrs)
      |> ActivityLog.store_event()

    event
  end
end
