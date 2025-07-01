defmodule Server.Services.IntegrationTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  setup_all do
    # Set required environment variables for testing
    System.put_env("TWITCH_CLIENT_ID", "test_client_id")
    System.put_env("TWITCH_CLIENT_SECRET", "test_client_secret")

    on_exit(fn ->
      # Clean up
      System.delete_env("TWITCH_CLIENT_ID")
      System.delete_env("TWITCH_CLIENT_SECRET")

      # Clean up any test files
      if File.exists?("./data/twitch_tokens.dets") do
        File.rm!("./data/twitch_tokens.dets")
      end
    end)
  end

  describe "refactored services integration" do
    test "OAuth token manager can be created and used" do
      # Test that OAuthTokenManager can be initialized
      {:ok, manager} =
        Server.OAuthTokenManager.new(
          storage_key: :test_tokens,
          client_id: "test_client_id",
          client_secret: "test_client_secret",
          auth_url: "https://id.twitch.tv/oauth2/authorize",
          token_url: "https://id.twitch.tv/oauth2/token",
          validate_url: "https://id.twitch.tv/oauth2/validate"
        )

      assert manager.storage_key == :test_tokens
      assert manager.oauth2_client.client_id == "test_client_id"

      # Test loading tokens (should succeed even with no existing tokens)
      updated_manager = Server.OAuthTokenManager.load_tokens(manager)
      assert updated_manager.dets_table != nil

      # Clean up
      Server.OAuthTokenManager.close(updated_manager)
    end

    test "WebSocket client can be created" do
      # Test that WebSocketClient can be initialized
      client =
        Server.WebSocketClient.new(
          "wss://eventsub.wss.twitch.tv/ws",
          self()
        )

      assert client.url == "wss://eventsub.wss.twitch.tv/ws"
      assert client.owner_pid == self()
      assert client.uri.host == "eventsub.wss.twitch.tv"
      assert client.uri.scheme == "wss"
    end

    test "EventSub manager scope validation works" do
      # Test core EventSubManager functionality
      user_scopes = MapSet.new(["channel:read:subscriptions", "bits:read"])
      required_scopes = ["channel:read:subscriptions"]

      result =
        Server.Services.Twitch.EventSubManager.validate_scopes_for_subscription(
          user_scopes,
          required_scopes
        )

      assert result == true
    end

    test "Event handler normalization works" do
      # Test core EventHandler functionality
      event_type = "stream.online"

      event_data = %{
        "id" => "stream_123",
        "broadcaster_user_id" => "user_123",
        "broadcaster_user_login" => "testuser",
        "broadcaster_user_name" => "TestUser",
        "type" => "live",
        "started_at" => "2023-01-01T12:00:00Z"
      }

      result = Server.Services.Twitch.EventHandler.normalize_event(event_type, event_data)

      assert result.type == "stream.online"
      assert result.id == "stream_123"
      assert result.broadcaster_user_id == "user_123"
      assert result.stream_type == "live"
      assert %DateTime{} = result.timestamp
    end

    test "all modules can be loaded without errors" do
      # Test that all our refactored modules can be loaded
      modules = [
        Server.Services.Twitch,
        Server.Services.Twitch.EventSubManager,
        Server.Services.Twitch.EventHandler,
        Server.OAuthTokenManager,
        Server.WebSocketClient
      ]

      for module <- modules do
        assert Code.ensure_loaded?(module), "Module #{module} failed to load"

        # Check that module has proper module doc
        {:docs_v1, _, _, _, module_doc, _, _} = Code.fetch_docs(module)
        assert module_doc != :none, "Module #{module} missing @moduledoc"
      end
    end
  end
end
