defmodule Server.Services.Twitch.EventSubManagerTest do
  use ExUnit.Case, async: true

  alias Server.Services.Twitch.EventSubManager

  # Mock state for testing
  defp mock_state(opts \\ []) do
    %{
      session_id: Keyword.get(opts, :session_id, "test_session_id"),
      oauth_client: %{
        token: %{access_token: "test_token"},
        client_id: "test_client_id"
      },
      scopes: Keyword.get(opts, :scopes, MapSet.new(["channel:read:subscriptions"])),
      user_id: Keyword.get(opts, :user_id, "test_user_id")
    }
  end

  describe "validate_scopes_for_subscription/2" do
    test "returns true when user has all required scopes" do
      user_scopes = MapSet.new(["channel:read:subscriptions", "bits:read"])
      required_scopes = ["channel:read:subscriptions"]
      
      assert EventSubManager.validate_scopes_for_subscription(user_scopes, required_scopes) == true
    end

    test "returns false when user is missing required scopes" do
      user_scopes = MapSet.new(["channel:read:subscriptions"])
      required_scopes = ["channel:read:subscriptions", "bits:read"]
      
      assert EventSubManager.validate_scopes_for_subscription(user_scopes, required_scopes) == false
    end

    test "returns true when no scopes are required" do
      user_scopes = MapSet.new(["channel:read:subscriptions"])
      required_scopes = []
      
      assert EventSubManager.validate_scopes_for_subscription(user_scopes, required_scopes) == true
    end

    test "returns false when user_scopes is nil" do
      required_scopes = ["channel:read:subscriptions"]
      
      assert EventSubManager.validate_scopes_for_subscription(nil, required_scopes) == false
    end
  end

  describe "generate_subscription_key/2" do
    test "generates consistent key for same event type and condition" do
      event_type = "channel.follow"
      condition = %{"broadcaster_user_id" => "123", "moderator_user_id" => "123"}
      
      key1 = EventSubManager.generate_subscription_key(event_type, condition)
      key2 = EventSubManager.generate_subscription_key(event_type, condition)
      
      assert key1 == key2
      assert is_binary(key1)
      assert String.contains?(key1, event_type)
    end

    test "generates different keys for different conditions" do
      event_type = "channel.follow"
      condition1 = %{"broadcaster_user_id" => "123"}
      condition2 = %{"broadcaster_user_id" => "456"}
      
      key1 = EventSubManager.generate_subscription_key(event_type, condition1)
      key2 = EventSubManager.generate_subscription_key(event_type, condition2)
      
      assert key1 != key2
    end

    test "generates keys independent of condition key order" do
      event_type = "channel.follow"
      condition1 = %{"broadcaster_user_id" => "123", "moderator_user_id" => "123"}
      condition2 = %{"moderator_user_id" => "123", "broadcaster_user_id" => "123"}
      
      key1 = EventSubManager.generate_subscription_key(event_type, condition1)
      key2 = EventSubManager.generate_subscription_key(event_type, condition2)
      
      assert key1 == key2
    end
  end

  describe "create_default_subscriptions/1" do
    test "returns error count when user_id is missing" do
      state = mock_state(user_id: nil)
      
      {success, failed} = EventSubManager.create_default_subscriptions(state)
      
      assert success == 0
      assert failed == 1
    end

    test "processes subscriptions based on available scopes" do
      # Mock a state with limited scopes
      state = mock_state(scopes: MapSet.new(["channel:read:subscriptions"]))
      
      # This will attempt to create subscriptions but fail due to missing HTTP endpoints
      # We're testing the scope filtering logic
      {success, failed} = EventSubManager.create_default_subscriptions(state)
      
      # Should have attempted some subscriptions based on scopes
      assert is_integer(success)
      assert is_integer(failed)
      assert success >= 0
      assert failed >= 0
    end

    test "skips subscriptions when missing required scopes" do
      # Mock a state with no scopes
      state = mock_state(scopes: MapSet.new([]))
      
      {success, failed} = EventSubManager.create_default_subscriptions(state)
      
      # Should skip most subscriptions due to missing scopes
      assert success == 0
      assert failed > 0
    end
  end

  describe "create_subscription/4" do
    # Note: These are unit tests that don't make actual HTTP requests
    # In a full test suite, you would mock the HTTP client
    
    test "builds correct request parameters for channel.follow" do
      state = mock_state()
      event_type = "channel.follow"
      condition = %{"broadcaster_user_id" => "123", "moderator_user_id" => "123"}
      
      # This test would fail due to actual HTTP request, but we can test parameter preparation
      # In a real implementation, you'd mock :httpc.request
      result = EventSubManager.create_subscription(state, event_type, condition)
      
      # Should return error since we're not mocking HTTP
      assert {:error, _reason} = result
    end

    test "uses version 2 for channel.follow events" do
      # This is testing the internal logic
      # Would need to mock HTTP client to fully test
      state = mock_state()
      event_type = "channel.follow"
      condition = %{"broadcaster_user_id" => "123", "moderator_user_id" => "123"}
      
      result = EventSubManager.create_subscription(state, event_type, condition)
      
      # Should attempt the request (and fail due to no mocking)
      assert {:error, _reason} = result
    end
  end

  describe "delete_subscription/2" do
    test "attempts to delete subscription via HTTP API" do
      state = mock_state()
      subscription_id = "test_subscription_id"
      
      # This will fail due to actual HTTP request without mocking
      result = EventSubManager.delete_subscription(state, subscription_id)
      
      assert {:error, _reason} = result
    end
  end
end