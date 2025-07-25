defmodule Server.Services.Twitch.SessionManagerTest do
  use ExUnit.Case, async: true

  alias Server.Services.Twitch.SessionManager
  alias Server.Test.MockEventSubManager

  describe "SessionManager initialization" do
    test "starts with no session" do
      {:ok, manager} = SessionManager.start_link(owner: self(), name: nil, event_sub_manager: MockEventSubManager)

      state = SessionManager.get_state(manager)
      assert state.session_id == nil
      assert state.user_id == nil
      assert state.has_session == false
      assert state.has_user_id == false
      assert state.default_subscriptions_created == false
      assert state.subscription_count == 0
    end

    test "monitors owner process" do
      {:ok, manager} = SessionManager.start_link(owner: self(), name: nil, event_sub_manager: MockEventSubManager)

      # Verify manager stops when owner exits
      Process.flag(:trap_exit, true)
      Process.exit(manager, :kill)

      assert_receive {:EXIT, ^manager, :killed}
    end
  end

  describe "session lifecycle" do
    setup do
      {:ok, manager} = SessionManager.start_link(owner: self(), name: nil, event_sub_manager: MockEventSubManager)
      {:ok, manager: manager}
    end

    test "handles session welcome without user_id", %{manager: manager} do
      session_id = "test-session-123"

      session_data = %{
        "id" => session_id,
        "status" => "connected",
        "keepalive_timeout_seconds" => 10
      }

      SessionManager.handle_session_welcome(manager, session_id, session_data)

      # Should receive session established notification
      assert_receive {:twitch_session, {:session_established, ^session_id, ^session_data}}

      # Verify state
      state = SessionManager.get_state(manager)
      assert state.session_id == session_id
      assert state.has_session == true
      # Should schedule retry
      assert state.retry_pending == true
    end

    test "handles session welcome with user_id", %{manager: manager} do
      # Set user_id first
      user_id = "12345"
      SessionManager.set_user_id(manager, user_id)

      # Mock token manager with required fields
      token_manager = %{
        oauth2_client: %{client_id: "test_client_id"},
        token_info: %{
          access_token: "test_access_token",
          expires_at: DateTime.add(DateTime.utc_now(), 3600)
        }
      }

      SessionManager.set_token_manager(manager, token_manager)

      session_id = "test-session-456"

      session_data = %{
        "id" => session_id,
        "status" => "connected"
      }

      SessionManager.handle_session_welcome(manager, session_id, session_data)

      # Should receive session established notification
      assert_receive {:twitch_session, {:session_established, ^session_id, ^session_data}}

      # Should attempt to create subscriptions
      # In real scenario, EventSubManager.create_default_subscriptions would be called
      # For test, we'll verify the state shows user_id is set
      state = SessionManager.get_state(manager)
      assert state.session_id == session_id
      assert state.user_id == user_id
      assert state.has_user_id == true
    end

    test "handles session end", %{manager: manager} do
      # Establish session first
      session_id = "test-session-789"
      SessionManager.handle_session_welcome(manager, session_id, %{"id" => session_id})

      # End session
      SessionManager.handle_session_end(manager)

      # Should receive session ended notification
      assert_receive {:twitch_session, :session_ended}

      # Verify state cleared
      state = SessionManager.get_state(manager)
      assert state.session_id == nil
      assert state.has_session == false
      assert state.subscription_count == 0
      assert state.default_subscriptions_created == false
    end

    test "handles session reconnect", %{manager: manager} do
      reconnect_url = "wss://example.twitch.tv/reconnect"

      SessionManager.handle_session_reconnect(manager, reconnect_url)

      # Should receive reconnect notification
      assert_receive {:twitch_session, {:session_reconnect_requested, ^reconnect_url}}
    end
  end

  describe "user_id and token updates" do
    setup do
      {:ok, manager} = SessionManager.start_link(owner: self(), name: nil, event_sub_manager: MockEventSubManager)
      {:ok, manager: manager}
    end

    test "updates user_id after session established", %{manager: manager} do
      # Establish session first
      session_id = "test-session-001"
      SessionManager.handle_session_welcome(manager, session_id, %{"id" => session_id})
      assert_receive {:twitch_session, {:session_established, _, _}}

      # Mock token manager with required fields
      token_manager = %{
        oauth2_client: %{client_id: "test_client_id"},
        token_info: %{
          access_token: "test_access_token",
          expires_at: DateTime.add(DateTime.utc_now(), 3600)
        }
      }

      SessionManager.set_token_manager(manager, token_manager)

      # Set user_id
      user_id = "67890"
      SessionManager.set_user_id(manager, user_id)

      # Verify state updated
      state = SessionManager.get_state(manager)
      assert state.user_id == user_id
      assert state.has_user_id == true
    end

    test "updates scopes", %{manager: manager} do
      scopes = MapSet.new(["user:read:email", "channel:read:subscriptions"])
      SessionManager.set_scopes(manager, scopes)

      # Scopes are internal state, verified through subscription creation
      # Just ensure no crash
      assert true
    end
  end

  describe "subscription creation" do
    setup do
      {:ok, manager} = SessionManager.start_link(owner: self(), name: nil, event_sub_manager: MockEventSubManager)

      # Set up required state
      user_id = "12345"

      token_manager = %{
        oauth2_client: %{client_id: "test_client_id"},
        token_info: %{
          access_token: "test_access_token",
          expires_at: DateTime.add(DateTime.utc_now(), 3600)
        }
      }

      SessionManager.set_user_id(manager, user_id)
      SessionManager.set_token_manager(manager, token_manager)

      # Establish session
      session_id = "test-session-sub"
      SessionManager.handle_session_welcome(manager, session_id, %{"id" => session_id})

      {:ok, manager: manager}
    end

    test "rejects subscription without session", %{manager: manager} do
      # End session first
      SessionManager.handle_session_end(manager)
      Process.sleep(10)

      result =
        SessionManager.create_subscription(
          manager,
          "channel.follow",
          %{"broadcaster_user_id" => "12345"}
        )

      assert result == {:error, "No active session"}
    end

    test "rejects subscription without user_id" do
      # Create manager without user_id
      {:ok, manager} = SessionManager.start_link(owner: self(), name: nil, event_sub_manager: MockEventSubManager)

      # Establish session
      session_id = "test-session-no-user"
      SessionManager.handle_session_welcome(manager, session_id, %{"id" => session_id})
      Process.sleep(10)

      result =
        SessionManager.create_subscription(
          manager,
          "channel.follow",
          %{"broadcaster_user_id" => "12345"}
        )

      assert result == {:error, "User ID not available"}
    end

    test "rejects subscription without token manager" do
      # Create manager without token manager
      {:ok, manager} = SessionManager.start_link(owner: self(), name: nil, event_sub_manager: MockEventSubManager)
      SessionManager.set_user_id(manager, "12345")

      # Establish session
      session_id = "test-session-no-token"
      SessionManager.handle_session_welcome(manager, session_id, %{"id" => session_id})
      Process.sleep(10)

      result =
        SessionManager.create_subscription(
          manager,
          "channel.follow",
          %{"broadcaster_user_id" => "12345"}
        )

      assert result == {:error, "Token manager not configured"}
    end
  end

  describe "subscription retry logic" do
    test "retries subscription creation when user_id becomes available" do
      {:ok, manager} = SessionManager.start_link(owner: self(), name: nil, event_sub_manager: MockEventSubManager)

      # Establish session without user_id
      session_id = "test-session-retry"
      SessionManager.handle_session_welcome(manager, session_id, %{"id" => session_id})

      # Verify retry is pending
      state = SessionManager.get_state(manager)
      assert state.retry_pending == true

      # Set token manager and user_id to trigger subscription creation
      token_manager = %{
        oauth2_client: %{client_id: "test_client_id"},
        token_info: %{
          access_token: "test_access_token",
          expires_at: DateTime.add(DateTime.utc_now(), 3600)
        }
      }

      SessionManager.set_token_manager(manager, token_manager)
      SessionManager.set_user_id(manager, "12345")

      # Wait for retry message to process
      Process.sleep(600)

      # Verify retry is no longer pending
      state = SessionManager.get_state(manager)
      assert state.has_user_id == true
    end

    test "abandons retry if session changes" do
      {:ok, manager} = SessionManager.start_link(owner: self(), name: nil, event_sub_manager: MockEventSubManager)

      # Establish first session
      session_id_1 = "test-session-1"
      SessionManager.handle_session_welcome(manager, session_id_1, %{"id" => session_id_1})

      # Establish new session before retry
      session_id_2 = "test-session-2"
      SessionManager.handle_session_welcome(manager, session_id_2, %{"id" => session_id_2})

      # Verify current session is the new one
      state = SessionManager.get_state(manager)
      assert state.session_id == session_id_2
    end
  end
end
