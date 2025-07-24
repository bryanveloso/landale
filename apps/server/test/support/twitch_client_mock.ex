defmodule Server.Services.TwitchClientMock do
  @moduledoc """
  Mock implementation of TwitchClientBehaviour for testing.

  This mock provides predictable responses for all Twitch API calls,
  enabling reliable unit and property testing without external dependencies.
  """

  @behaviour Server.Services.TwitchClientBehaviour

  @impl true
  def validate_token(token) when is_binary(token) do
    case token do
      "valid_token" ->
        {:ok,
         %{
           "client_id" => "test_client_id",
           "login" => "test_user",
           "scopes" => ["channel:read:subscriptions"],
           "user_id" => "123456789",
           "expires_in" => 3600
         }}

      "expired_token" ->
        {:error, %{"status" => 401, "message" => "invalid access token"}}

      "invalid_token" ->
        {:error, %{"status" => 401, "message" => "invalid access token"}}

      _ ->
        {:ok,
         %{
           "client_id" => "test_client_id",
           "login" => "test_user",
           "scopes" => ["channel:read:subscriptions"],
           "user_id" => "123456789",
           "expires_in" => 3600
         }}
    end
  end

  @impl true
  def refresh_token(refresh_token, client_id, client_secret)
      when is_binary(refresh_token) and is_binary(client_id) and is_binary(client_secret) do
    case refresh_token do
      "valid_refresh_token" ->
        {:ok,
         %{
           "access_token" => "new_access_token",
           "refresh_token" => "new_refresh_token",
           "expires_in" => 3600,
           "scope" => ["channel:read:subscriptions"],
           "token_type" => "bearer"
         }}

      "invalid_refresh_token" ->
        {:error, %{"status" => 400, "message" => "Invalid refresh token"}}

      _ ->
        {:ok,
         %{
           "access_token" => "new_access_token",
           "refresh_token" => "new_refresh_token",
           "expires_in" => 3600,
           "scope" => ["channel:read:subscriptions"],
           "token_type" => "bearer"
         }}
    end
  end

  @impl true
  def create_subscription(subscription_data, token)
      when is_map(subscription_data) and is_binary(token) do
    case token do
      "valid_token" ->
        {:ok,
         %{
           "data" => [
             %{
               "id" => "subscription_id_#{:rand.uniform(999_999)}",
               "status" => "enabled",
               "type" => Map.get(subscription_data, "type", "channel.update"),
               "version" => "1",
               "condition" => Map.get(subscription_data, "condition", %{}),
               "transport" => Map.get(subscription_data, "transport", %{}),
               "created_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
               "cost" => 1
             }
           ],
           "total" => 1,
           "total_cost" => 1,
           "max_total_cost" => 10
         }}

      "invalid_token" ->
        {:error, %{"status" => 401, "message" => "invalid access token"}}

      _ ->
        {:ok,
         %{
           "data" => [
             %{
               "id" => "subscription_id_#{:rand.uniform(999_999)}",
               "status" => "enabled",
               "type" => Map.get(subscription_data, "type", "channel.update"),
               "version" => "1",
               "condition" => Map.get(subscription_data, "condition", %{}),
               "transport" => Map.get(subscription_data, "transport", %{}),
               "created_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
               "cost" => 1
             }
           ],
           "total" => 1,
           "total_cost" => 1,
           "max_total_cost" => 10
         }}
    end
  end

  @impl true
  def delete_subscription(subscription_id, token)
      when is_binary(subscription_id) and is_binary(token) do
    case token do
      "valid_token" ->
        {:ok, %{"data" => []}}

      "invalid_token" ->
        {:error, %{"status" => 401, "message" => "invalid access token"}}

      _ ->
        case subscription_id do
          "nonexistent_subscription" ->
            {:error, %{"status" => 404, "message" => "subscription not found"}}

          _ ->
            {:ok, %{"data" => []}}
        end
    end
  end

  @impl true
  def list_subscriptions(token) when is_binary(token) do
    case token do
      "valid_token" ->
        {:ok,
         %{
           "data" => [
             %{
               "id" => "subscription_1",
               "status" => "enabled",
               "type" => "channel.update",
               "version" => "1",
               "condition" => %{"broadcaster_user_id" => "123456789"},
               "transport" => %{"method" => "websocket", "session_id" => "test_session"},
               "created_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
               "cost" => 1
             },
             %{
               "id" => "subscription_2",
               "status" => "enabled",
               "type" => "stream.online",
               "version" => "1",
               "condition" => %{"broadcaster_user_id" => "123456789"},
               "transport" => %{"method" => "websocket", "session_id" => "test_session"},
               "created_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
               "cost" => 1
             }
           ],
           "total" => 2,
           "total_cost" => 2,
           "max_total_cost" => 10
         }}

      "invalid_token" ->
        {:error, %{"status" => 401, "message" => "invalid access token"}}

      _ ->
        {:ok,
         %{
           "data" => [],
           "total" => 0,
           "total_cost" => 0,
           "max_total_cost" => 10
         }}
    end
  end

  @impl true
  def get_user_info(token) when is_binary(token) do
    case token do
      "valid_token" ->
        {:ok,
         %{
           "data" => [
             %{
               "id" => "123456789",
               "login" => "test_user",
               "display_name" => "TestUser",
               "type" => "",
               "broadcaster_type" => "affiliate",
               "description" => "Test user for mock responses",
               "profile_image_url" => "https://example.com/profile.jpg",
               "offline_image_url" => "https://example.com/offline.jpg",
               "view_count" => 1000,
               "email" => "test@example.com",
               "created_at" => "2020-01-01T00:00:00Z"
             }
           ]
         }}

      "invalid_token" ->
        {:error, %{"status" => 401, "message" => "invalid access token"}}

      _ ->
        {:ok,
         %{
           "data" => [
             %{
               "id" => "123456789",
               "login" => "test_user",
               "display_name" => "TestUser",
               "type" => "",
               "broadcaster_type" => "affiliate",
               "description" => "Test user for mock responses",
               "profile_image_url" => "https://example.com/profile.jpg",
               "offline_image_url" => "https://example.com/offline.jpg",
               "view_count" => 1000,
               "email" => "test@example.com",
               "created_at" => "2020-01-01T00:00:00Z"
             }
           ]
         }}
    end
  end
end
