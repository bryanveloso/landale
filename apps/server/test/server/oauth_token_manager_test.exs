defmodule Server.OAuthTokenManagerTest do
  use ExUnit.Case, async: true

  alias Server.OAuthTokenManager

  @test_storage_path "./test_data/test_tokens.dets"

  setup do
    # Ensure test directory exists
    File.mkdir_p!("./test_data")

    on_exit(fn ->
      # Clean up test DETS files
      if File.exists?(@test_storage_path) do
        File.rm!(@test_storage_path)
      end
    end)

    :ok
  end

  describe "new/1" do
    test "creates a new token manager with required options" do
      opts = [
        storage_key: :test_tokens,
        client_id: "test_client_id",
        client_secret: "test_client_secret",
        token_url: "https://example.com/oauth/token",
        storage_path: @test_storage_path
      ]

      assert {:ok, manager} = OAuthTokenManager.new(opts)
      assert manager.storage_key == :test_tokens
      assert manager.storage_path == @test_storage_path
      assert manager.oauth_client.client_id == "test_client_id"
      assert manager.oauth_client.client_secret == "test_client_secret"
      assert manager.refresh_buffer_ms == 300_000  # default
    end

    test "accepts custom refresh buffer" do
      opts = [
        storage_key: :test_tokens,
        client_id: "test_client_id",
        client_secret: "test_client_secret",
        token_url: "https://example.com/oauth/token",
        refresh_buffer_ms: 600_000,
        storage_path: @test_storage_path
      ]

      assert {:ok, manager} = OAuthTokenManager.new(opts)
      assert manager.refresh_buffer_ms == 600_000
    end

    test "returns error for missing required options" do
      opts = [
        storage_key: :test_tokens,
        client_id: "test_client_id"
        # missing client_secret and token_url
      ]

      assert {:error, reason} = OAuthTokenManager.new(opts)
      assert reason =~ "Missing required option"
    end

    test "accepts custom telemetry prefix" do
      opts = [
        storage_key: :test_tokens,
        client_id: "test_client_id",
        client_secret: "test_client_secret",
        token_url: "https://example.com/oauth/token",
        telemetry_prefix: [:custom, :prefix],
        storage_path: @test_storage_path
      ]

      assert {:ok, manager} = OAuthTokenManager.new(opts)
      assert manager.telemetry_prefix == [:custom, :prefix]
    end
  end

  describe "load_tokens/1" do
    test "loads tokens when DETS file doesn't exist" do
      {:ok, manager} = OAuthTokenManager.new([
        storage_key: :test_tokens,
        client_id: "test_client_id",
        client_secret: "test_client_secret",
        token_url: "https://example.com/oauth/token",
        storage_path: @test_storage_path
      ])

      updated_manager = OAuthTokenManager.load_tokens(manager)

      # Should have opened DETS table
      assert updated_manager.dets_table != nil
      # Should have no token info initially
      assert updated_manager.token_info == nil
    end

    test "creates storage directory if it doesn't exist" do
      storage_path = "./test_data/nested/dir/test_tokens.dets"

      {:ok, manager} = OAuthTokenManager.new([
        storage_key: :test_tokens,
        client_id: "test_client_id",
        client_secret: "test_client_secret",
        token_url: "https://example.com/oauth/token",
        storage_path: storage_path
      ])

      updated_manager = OAuthTokenManager.load_tokens(manager)

      # Directory should have been created
      assert File.exists?("./test_data/nested/dir")
      assert updated_manager.dets_table != nil

      # Clean up
      File.rm_rf!("./test_data/nested")
    end
  end

  describe "set_token/2" do
    setup do
      {:ok, manager} = OAuthTokenManager.new([
        storage_key: :test_tokens,
        client_id: "test_client_id",
        client_secret: "test_client_secret",
        token_url: "https://example.com/oauth/token",
        storage_path: @test_storage_path
      ])

      manager = OAuthTokenManager.load_tokens(manager)
      %{manager: manager}
    end

    test "sets token info from map with string keys", %{manager: manager} do
      token_info = %{
        "access_token" => "test_access_token",
        "refresh_token" => "test_refresh_token",
        "expires_in" => 3600,
        "scopes" => ["read", "write"],
        "user_id" => "user123"
      }

      updated_manager = OAuthTokenManager.set_token(manager, token_info)

      assert updated_manager.token_info.access_token == "test_access_token"
      assert updated_manager.token_info.refresh_token == "test_refresh_token"
      assert updated_manager.token_info.user_id == "user123"
      assert updated_manager.token_info.scopes == MapSet.new(["read", "write"])
      assert %DateTime{} = updated_manager.token_info.expires_at
    end

    test "sets token info from map with atom keys", %{manager: manager} do
      token_info = %{
        access_token: "test_access_token",
        refresh_token: "test_refresh_token",
        expires_in: 3600,
        scope: "read write",  # space-separated string
        user_id: "user123"
      }

      updated_manager = OAuthTokenManager.set_token(manager, token_info)

      assert updated_manager.token_info.access_token == "test_access_token"
      assert updated_manager.token_info.scopes == MapSet.new(["read", "write"])
    end
  end

  describe "get_valid_token/1" do
    setup do
      {:ok, manager} = OAuthTokenManager.new([
        storage_key: :test_tokens,
        client_id: "test_client_id",
        client_secret: "test_client_secret",
        token_url: "https://example.com/oauth/token",
        storage_path: @test_storage_path
      ])

      manager = OAuthTokenManager.load_tokens(manager)
      %{manager: manager}
    end

    test "returns error when no token is available", %{manager: manager} do
      assert {:error, "No token available"} = OAuthTokenManager.get_valid_token(manager)
    end

    test "returns token when it's valid and not expired", %{manager: manager} do
      # Set a token that expires in the future
      expires_at = DateTime.add(DateTime.utc_now(), 3600, :second)
      
      token_info = %{
        access_token: "valid_token",
        refresh_token: "refresh_token",
        expires_at: expires_at,
        scopes: MapSet.new(["read"]),
        user_id: "user123"
      }

      manager = %{manager | token_info: token_info}

      assert {:ok, "valid_token", updated_manager} = OAuthTokenManager.get_valid_token(manager)
      assert updated_manager.token_info.access_token == "valid_token"
    end

    test "returns token when no expiry is set", %{manager: manager} do
      token_info = %{
        access_token: "valid_token",
        refresh_token: "refresh_token",
        expires_at: nil,
        scopes: MapSet.new(["read"]),
        user_id: "user123"
      }

      manager = %{manager | token_info: token_info}

      assert {:ok, "valid_token", updated_manager} = OAuthTokenManager.get_valid_token(manager)
      assert updated_manager.token_info.access_token == "valid_token"
    end
  end

  describe "close/1" do
    test "closes DETS table gracefully" do
      {:ok, manager} = OAuthTokenManager.new([
        storage_key: :test_tokens,
        client_id: "test_client_id",
        client_secret: "test_client_secret",
        token_url: "https://example.com/oauth/token",
        storage_path: @test_storage_path
      ])

      manager = OAuthTokenManager.load_tokens(manager)
      
      assert :ok = OAuthTokenManager.close(manager)
    end

    test "handles close when no DETS table is open" do
      {:ok, manager} = OAuthTokenManager.new([
        storage_key: :test_tokens,
        client_id: "test_client_id",
        client_secret: "test_client_secret",
        token_url: "https://example.com/oauth/token",
        storage_path: @test_storage_path
      ])

      assert :ok = OAuthTokenManager.close(manager)
    end
  end

  describe "refresh_token/1" do
    setup do
      {:ok, manager} = OAuthTokenManager.new([
        storage_key: :test_tokens,
        client_id: "test_client_id",
        client_secret: "test_client_secret",
        token_url: "https://example.com/oauth/token",
        storage_path: @test_storage_path
      ])

      manager = OAuthTokenManager.load_tokens(manager)
      %{manager: manager}
    end

    test "returns error when no token info is available", %{manager: manager} do
      assert {:error, "No token info available for refresh"} = OAuthTokenManager.refresh_token(manager)
    end

    test "returns error when no refresh token is available", %{manager: manager} do
      token_info = %{
        access_token: "token",
        refresh_token: nil,
        expires_at: DateTime.utc_now(),
        scopes: MapSet.new([]),
        user_id: "user123"
      }

      manager = %{manager | token_info: token_info}

      assert {:error, "No refresh token available"} = OAuthTokenManager.refresh_token(manager)
    end

    # Note: Testing actual refresh would require mocking the OAuth2 library
    # In a full test suite, you would mock OAuth2.Client.refresh_token/1
  end

  describe "validate_token/2" do
    setup do
      {:ok, manager} = OAuthTokenManager.new([
        storage_key: :test_tokens,
        client_id: "test_client_id",
        client_secret: "test_client_secret",
        token_url: "https://example.com/oauth/token",
        storage_path: @test_storage_path
      ])

      manager = OAuthTokenManager.load_tokens(manager)
      %{manager: manager}
    end

    test "returns error when no token is available", %{manager: manager} do
      validate_url = "https://example.com/oauth/validate"
      
      assert {:error, "No token available for validation"} = OAuthTokenManager.validate_token(manager, validate_url)
    end

    # Note: Testing actual validation would require mocking :httpc
    # In a full test suite, you would mock the HTTP client
  end
end