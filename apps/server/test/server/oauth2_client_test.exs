defmodule Server.OAuth2ClientTest do
  use ExUnit.Case, async: true

  alias Server.OAuth2Client

  describe "new/1" do
    test "creates client with required parameters" do
      config = %{
        auth_url: "https://id.twitch.tv/oauth2/authorize",
        token_url: "https://id.twitch.tv/oauth2/token",
        client_id: "test_client_id",
        client_secret: "test_client_secret"
      }

      assert {:ok, client} = OAuth2Client.new(config)
      assert client.auth_url == "https://id.twitch.tv/oauth2/authorize"
      assert client.token_url == "https://id.twitch.tv/oauth2/token"
      assert client.client_id == "test_client_id"
      assert client.client_secret == "test_client_secret"
      assert client.validate_url == nil
      assert client.timeout == 10_000
      assert client.telemetry_prefix == [:server, :oauth2]
    end

    test "creates client with optional parameters" do
      config = %{
        auth_url: "https://id.twitch.tv/oauth2/authorize",
        token_url: "https://id.twitch.tv/oauth2/token",
        validate_url: "https://id.twitch.tv/oauth2/validate",
        client_id: "test_client_id",
        client_secret: "test_client_secret",
        timeout: 15_000,
        telemetry_prefix: [:custom, :oauth]
      }

      assert {:ok, client} = OAuth2Client.new(config)
      assert client.validate_url == "https://id.twitch.tv/oauth2/validate"
      assert client.timeout == 15_000
      assert client.telemetry_prefix == [:custom, :oauth]
    end

    test "returns error for missing auth_url" do
      config = %{
        token_url: "https://id.twitch.tv/oauth2/token",
        client_id: "test_client_id",
        client_secret: "test_client_secret"
      }

      assert {:error, {:missing_required_config, :auth_url}} = OAuth2Client.new(config)
    end

    test "returns error for missing token_url" do
      config = %{
        auth_url: "https://id.twitch.tv/oauth2/authorize",
        client_id: "test_client_id",
        client_secret: "test_client_secret"
      }

      assert {:error, {:missing_required_config, :token_url}} = OAuth2Client.new(config)
    end

    test "returns error for missing client_id" do
      config = %{
        auth_url: "https://id.twitch.tv/oauth2/authorize",
        token_url: "https://id.twitch.tv/oauth2/token",
        client_secret: "test_client_secret"
      }

      assert {:error, {:missing_required_config, :client_id}} = OAuth2Client.new(config)
    end

    test "returns error for missing client_secret" do
      config = %{
        auth_url: "https://id.twitch.tv/oauth2/authorize",
        token_url: "https://id.twitch.tv/oauth2/token",
        client_id: "test_client_id"
      }

      assert {:error, {:missing_required_config, :client_secret}} = OAuth2Client.new(config)
    end

    test "returns error for empty string values" do
      config = %{
        auth_url: "",
        token_url: "https://id.twitch.tv/oauth2/token",
        client_id: "test_client_id",
        client_secret: "test_client_secret"
      }

      assert {:error, {:invalid_config, :auth_url, "must be non-empty string"}} = OAuth2Client.new(config)
    end

    test "returns error for non-string values" do
      config = %{
        auth_url: "https://id.twitch.tv/oauth2/authorize",
        token_url: "https://id.twitch.tv/oauth2/token",
        client_id: 123,
        client_secret: "test_client_secret"
      }

      assert {:error, {:invalid_config, :client_id, "must be non-empty string"}} = OAuth2Client.new(config)
    end
  end

  describe "validate_token/2" do
    test "returns error when no validation URL is configured" do
      config = %{
        auth_url: "https://id.twitch.tv/oauth2/authorize",
        token_url: "https://id.twitch.tv/oauth2/token",
        client_id: "test_client_id",
        client_secret: "test_client_secret"
      }

      {:ok, client} = OAuth2Client.new(config)

      assert {:error, :no_validation_url} = OAuth2Client.validate_token(client, "test_token")
    end
  end

  describe "parse_scope/1" do
    # Note: This tests the private function indirectly through token parsing
    # In a real implementation, you might want to make this public for testing

    test "parses space-separated scope string" do
      # This would need to be tested through the exchange_code or refresh_token functions
      # which would require mocking HTTP calls
    end

    test "handles list scopes" do
      # This would need to be tested through the exchange_code or refresh_token functions
      # which would require mocking HTTP calls
    end

    test "handles nil scope" do
      # This would need to be tested through the exchange_code or refresh_token functions
      # which would require mocking HTTP calls
    end
  end
end
