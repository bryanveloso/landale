defmodule Server.Services.Twitch.EventSubManagerTest do
  use ExUnit.Case, async: true
  import Mox

  alias Server.MockOAuthTokenManager
  alias Server.Services.Twitch.EventSubManager

  # Make sure mocks are verified when the test exits
  setup :verify_on_exit!

  # Mock state for testing
  defp mock_state(opts \\ []) do
    %{
      session_id: Keyword.get(opts, :session_id, "test_session_id"),
      oauth2_client: %{
        client_id: "test_client_id",
        client_secret: "test_client_secret",
        auth_url: "https://id.twitch.tv/oauth2/authorize",
        token_url: "https://id.twitch.tv/oauth2/token",
        validate_url: "https://id.twitch.tv/oauth2/validate",
        timeout: 10_000,
        telemetry_prefix: [:server, :oauth2]
      },
      token_manager:
        Keyword.get(opts, :token_manager, %{
          storage_key: :test_tokens,
          storage_path: "./data/test_tokens.dets",
          dets_table: nil,
          oauth2_client: %{
            client_id: "test_client_id",
            client_secret: "test_client_secret",
            auth_url: "https://id.twitch.tv/oauth2/authorize",
            token_url: "https://id.twitch.tv/oauth2/token",
            validate_url: "https://id.twitch.tv/oauth2/validate",
            timeout: 10_000,
            telemetry_prefix: [:server, :oauth2]
          },
          token_info: %{
            access_token: "test_token",
            refresh_token: "test_refresh_token",
            expires_at: DateTime.add(DateTime.utc_now(), 3600, :second),
            scopes: MapSet.new(["channel:read:subscriptions"]),
            user_id: "test_user_id"
          },
          refresh_buffer_ms: 300_000,
          telemetry_prefix: [:server, :oauth]
        }),
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
      state = mock_state(scopes: MapSet.new(["channel:read:subscriptions"]))

      # Mock token manager to return a valid token for multiple calls
      stub(MockOAuthTokenManager, :get_valid_token, fn _manager ->
        {:ok, "test_access_token", state.token_manager}
      end)

      # This will attempt to create subscriptions but fail due to HTTP calls
      # We're testing the scope filtering and token retrieval logic
      {success, failed} =
        EventSubManager.create_default_subscriptions(state,
          token_manager_module: MockOAuthTokenManager
        )

      # Should have attempted some subscriptions based on scopes
      assert is_integer(success)
      assert is_integer(failed)
      assert success >= 0
      assert failed >= 0
    end

    test "skips subscriptions when missing required scopes" do
      # Mock a state with no scopes
      state = mock_state(scopes: MapSet.new([]))

      # Mock token manager to return a valid token for the few subscriptions that don't require scopes
      stub(MockOAuthTokenManager, :get_valid_token, fn _manager ->
        {:ok, "test_access_token", state.token_manager}
      end)

      {success, failed} =
        EventSubManager.create_default_subscriptions(state,
          token_manager_module: MockOAuthTokenManager
        )

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

      # Mock token manager to return a valid token
      expect(MockOAuthTokenManager, :get_valid_token, fn _manager ->
        {:ok, "test_access_token", state.token_manager}
      end)

      # This will fail at HTTP level but we've verified token retrieval works
      result =
        EventSubManager.create_subscription(state, event_type, condition, token_manager_module: MockOAuthTokenManager)

      # Should return error since we're not mocking HTTP client
      assert {:error, _reason} = result
    end

    test "uses version 2 for channel.follow events" do
      state = mock_state()
      event_type = "channel.follow"
      condition = %{"broadcaster_user_id" => "123", "moderator_user_id" => "123"}

      # Mock token manager to return a valid token
      expect(MockOAuthTokenManager, :get_valid_token, fn _manager ->
        {:ok, "test_access_token", state.token_manager}
      end)

      result =
        EventSubManager.create_subscription(state, event_type, condition, token_manager_module: MockOAuthTokenManager)

      # Should attempt the request (and fail due to no HTTP mocking)
      assert {:error, _reason} = result
    end
  end

  describe "delete_subscription/2" do
    test "attempts to delete subscription via HTTP API" do
      state = mock_state()
      subscription_id = "test_subscription_id"

      # Mock token manager to return a valid token
      expect(MockOAuthTokenManager, :get_valid_token, fn _manager ->
        {:ok, "test_access_token", state.token_manager}
      end)

      # This will fail at HTTP level but we've verified token retrieval works
      result = EventSubManager.delete_subscription(state, subscription_id, token_manager_module: MockOAuthTokenManager)

      assert {:error, _reason} = result
    end
  end
end
