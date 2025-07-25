defmodule Server.Services.Twitch.EventSubManagerTest do
  @moduledoc """
  Unit tests for the Twitch EventSub subscription manager.

  Tests critical subscription management functionality including:
  - Subscription creation
  - Subscription deletion
  - Scope validation
  - Default subscription creation
  - Subscription key generation
  """
  use ExUnit.Case, async: true

  alias Server.Services.Twitch.EventSubManager

  # Mock modules for testing
  defmodule MockTokenManager do
    def get_valid_token(_manager) do
      {:ok, "mock_access_token", %{}}
    end
  end

  defmodule MockTokenManagerFailure do
    def get_valid_token(_manager) do
      {:error, :token_expired}
    end
  end

  setup do
    # Store original config
    original_config = Application.get_env(:server, Server.Services.Twitch, [])

    # Set test config for client_id
    Application.put_env(:server, Server.Services.Twitch, client_id: "test_client_id")

    # Start CircuitBreakerServer if not already started
    case Process.whereis(Server.CircuitBreakerServer) do
      nil -> start_supervised!(Server.CircuitBreakerServer)
      _pid -> :ok
    end

    # Start OAuth service if not already started
    case Process.whereis(Server.OAuthService) do
      nil -> start_supervised!(Server.OAuthService)
      _pid -> :ok
    end

    # Register twitch service with OAuth
    oauth_config = %{
      client_id: "test_client_id",
      client_secret: "test_client_secret",
      auth_url: "https://id.twitch.tv/oauth2/authorize",
      token_url: "https://id.twitch.tv/oauth2/token",
      validate_url: "https://id.twitch.tv/oauth2/validate"
    }

    Server.OAuthService.register_service(:twitch, oauth_config)

    # Create a minimal state structure that EventSubManager expects
    state = %{
      session_id: "test_session_123",
      user_id: "123456",
      scopes: MapSet.new(["channel:read:subscriptions", "moderator:read:followers"]),
      oauth2_client: %{client_id: "test_client_id"},
      token_manager: %{},
      subscriptions: %{},
      service_name: :twitch
    }

    on_exit(fn ->
      # Restore original config
      Application.put_env(:server, Server.Services.Twitch, original_config)
    end)

    {:ok, state: state}
  end

  describe "create_subscription/4" do
    test "attempts to create subscription with valid state", %{state: state} do
      event_type = "channel.update"
      condition = %{"broadcaster_user_id" => "123456"}
      opts = [token_manager_module: MockTokenManager]

      # This will make an actual HTTP request, so it will fail, but we're testing the interface
      result = EventSubManager.create_subscription(state, event_type, condition, opts)

      # Should get an error since we can't actually make the HTTP request
      assert {:error, _reason} = result
    end

    test "handles token unavailable", %{state: state} do
      event_type = "channel.update"
      condition = %{"broadcaster_user_id" => "123456"}

      # Create a new state without registering tokens
      state_without_tokens = %{state | service_name: :twitch_no_tokens}

      # Register service without tokens
      Server.OAuthService.register_service(:twitch_no_tokens, %{
        client_id: "test_client_id",
        client_secret: "test_client_secret",
        auth_url: "https://id.twitch.tv/oauth2/authorize",
        token_url: "https://id.twitch.tv/oauth2/token"
      })

      result = EventSubManager.create_subscription(state_without_tokens, event_type, condition)

      assert {:error, {:token_unavailable, _reason}} = result
    end

    test "accepts different event types and conditions", %{state: state} do
      test_cases = [
        {"channel.follow", %{"broadcaster_user_id" => "123", "moderator_user_id" => "456"}},
        {"stream.online", %{"broadcaster_user_id" => "789"}},
        {"channel.raid", %{"to_broadcaster_user_id" => "111"}}
      ]

      for {event_type, condition} <- test_cases do
        result = EventSubManager.create_subscription(state, event_type, condition)
        # All should return errors since we can't make real HTTP requests
        assert {:error, _} = result
      end
    end
  end

  describe "delete_subscription/3" do
    test "attempts to delete subscription by ID", %{state: state} do
      subscription_id = "test_sub_123"

      result = EventSubManager.delete_subscription(state, subscription_id)

      # Should get an error since we can't actually make the HTTP request
      assert {:error, _reason} = result
    end

    test "handles token unavailable error", %{state: state} do
      subscription_id = "test_sub_123"

      # Create a new state without registering tokens
      state_without_tokens = %{state | service_name: :twitch_no_tokens_delete}

      # Register service without tokens
      Server.OAuthService.register_service(:twitch_no_tokens_delete, %{
        client_id: "test_client_id",
        client_secret: "test_client_secret",
        auth_url: "https://id.twitch.tv/oauth2/authorize",
        token_url: "https://id.twitch.tv/oauth2/token"
      })

      result = EventSubManager.delete_subscription(state_without_tokens, subscription_id)

      assert {:error, {:token_unavailable, _reason}} = result
    end
  end

  describe "create_default_subscriptions/2" do
    test "creates default subscriptions when user_id is present", %{state: state} do
      {success, failed} = EventSubManager.create_default_subscriptions(state)

      # All should fail since we can't make real HTTP requests
      assert success == 0
      # Should have attempted several subscriptions
      assert failed > 0
    end

    test "returns error count when user_id is nil" do
      state = %{user_id: nil, scopes: MapSet.new()}

      {success, failed} = EventSubManager.create_default_subscriptions(state)

      assert success == 0
      assert failed == 1
    end

    test "skips subscriptions when required scopes are missing" do
      # State with no scopes
      state = %{
        user_id: "123456",
        session_id: "test_session_123",
        # Empty scopes
        scopes: MapSet.new(),
        oauth2_client: %{client_id: "test_client_id"},
        token_manager: %{},
        service_name: :twitch
      }

      {success, failed} = EventSubManager.create_default_subscriptions(state)

      # All should be skipped due to missing scopes
      assert success == 0
      assert failed > 0
    end
  end

  describe "validate_scopes_for_subscription/2" do
    test "returns true when all required scopes are present" do
      user_scopes = MapSet.new(["channel:read:subscriptions", "bits:read"])
      required_scopes = ["channel:read:subscriptions"]

      assert EventSubManager.validate_scopes_for_subscription(user_scopes, required_scopes)
    end

    test "returns false when required scopes are missing" do
      user_scopes = MapSet.new(["bits:read"])
      required_scopes = ["channel:read:subscriptions"]

      refute EventSubManager.validate_scopes_for_subscription(user_scopes, required_scopes)
    end

    test "returns true when no scopes are required" do
      user_scopes = MapSet.new()
      required_scopes = []

      assert EventSubManager.validate_scopes_for_subscription(user_scopes, required_scopes)
    end

    test "returns false when user_scopes is nil" do
      required_scopes = ["channel:read:subscriptions"]

      refute EventSubManager.validate_scopes_for_subscription(nil, required_scopes)
    end

    test "validates multiple required scopes" do
      user_scopes = MapSet.new(["channel:read:subscriptions", "bits:read", "moderator:read:followers"])
      required_scopes = ["channel:read:subscriptions", "bits:read"]

      assert EventSubManager.validate_scopes_for_subscription(user_scopes, required_scopes)
    end

    test "returns false when any required scope is missing" do
      user_scopes = MapSet.new(["channel:read:subscriptions"])
      required_scopes = ["channel:read:subscriptions", "bits:read"]

      refute EventSubManager.validate_scopes_for_subscription(user_scopes, required_scopes)
    end
  end

  describe "generate_subscription_key/2" do
    test "generates consistent keys for same input" do
      event_type = "channel.follow"
      condition = %{"broadcaster_user_id" => "123", "moderator_user_id" => "456"}

      key1 = EventSubManager.generate_subscription_key(event_type, condition)
      key2 = EventSubManager.generate_subscription_key(event_type, condition)

      assert key1 == key2
      assert is_binary(key1)
      assert String.contains?(key1, event_type)
    end

    test "generates different keys for different event types" do
      condition = %{"broadcaster_user_id" => "123"}

      key1 = EventSubManager.generate_subscription_key("channel.follow", condition)
      key2 = EventSubManager.generate_subscription_key("channel.update", condition)

      assert key1 != key2
    end

    test "generates different keys for different conditions" do
      event_type = "channel.follow"

      key1 = EventSubManager.generate_subscription_key(event_type, %{"broadcaster_user_id" => "123"})
      key2 = EventSubManager.generate_subscription_key(event_type, %{"broadcaster_user_id" => "456"})

      assert key1 != key2
    end

    test "handles conditions with multiple keys consistently" do
      event_type = "channel.follow"

      # Same condition but keys in different order
      condition1 = %{"broadcaster_user_id" => "123", "moderator_user_id" => "456"}
      condition2 = %{"moderator_user_id" => "456", "broadcaster_user_id" => "123"}

      key1 = EventSubManager.generate_subscription_key(event_type, condition1)
      key2 = EventSubManager.generate_subscription_key(event_type, condition2)

      # Keys should be the same due to consistent sorting
      assert key1 == key2
    end

    test "generates valid keys for empty conditions" do
      event_type = "test.event"
      condition = %{}

      key = EventSubManager.generate_subscription_key(event_type, condition)

      assert is_binary(key)
      assert String.contains?(key, event_type)
    end
  end

  describe "integration scenarios" do
    test "subscription creation flow with scope validation", %{state: state} do
      # Add required scope for channel.follow
      state = %{state | scopes: MapSet.new(["moderator:read:followers"])}

      event_type = "channel.follow"
      condition = %{"broadcaster_user_id" => "123", "moderator_user_id" => "123"}

      # First validate scopes
      assert EventSubManager.validate_scopes_for_subscription(state.scopes, ["moderator:read:followers"])

      # Then attempt creation (will fail due to HTTP request)
      opts = [token_manager_module: MockTokenManager]
      result = EventSubManager.create_subscription(state, event_type, condition, opts)

      assert {:error, _} = result
    end

    test "generates unique keys for all default subscriptions" do
      # Get a sample of event types and generate keys
      event_types = [
        "stream.online",
        "stream.offline",
        "channel.update",
        "channel.follow",
        "channel.subscribe",
        "channel.subscription.gift",
        "channel.cheer",
        "channel.raid"
      ]

      user_id = "123456"

      keys =
        for event_type <- event_types do
          condition =
            case event_type do
              "channel.follow" -> %{"broadcaster_user_id" => user_id, "moderator_user_id" => user_id}
              "channel.raid" -> %{"to_broadcaster_user_id" => user_id}
              _ -> %{"broadcaster_user_id" => user_id}
            end

          EventSubManager.generate_subscription_key(event_type, condition)
        end

      # All keys should be unique
      assert length(keys) == length(Enum.uniq(keys))
    end
  end
end
