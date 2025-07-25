defmodule Server.Services.TwitchClientBehaviour do
  @moduledoc """
  Behaviour definition for Twitch HTTP API client interface.

  This behaviour abstracts external HTTP calls to Twitch APIs, enabling
  proper mocking in tests while maintaining the same interface for production.
  """

  @doc """
  Validates an OAuth token with Twitch's validation endpoint.

  ## Parameters
  - `token` - The OAuth token to validate

  ## Returns
  - `{:ok, response}` with validation details on success
  - `{:error, reason}` on failure
  """
  @callback validate_token(token :: String.t()) :: {:ok, map()} | {:error, term()}

  @doc """
  Refreshes an OAuth token using a refresh token.

  ## Parameters
  - `refresh_token` - The refresh token to use
  - `client_id` - Twitch application client ID
  - `client_secret` - Twitch application client secret

  ## Returns
  - `{:ok, response}` with new token details on success
  - `{:error, reason}` on failure
  """
  @callback refresh_token(
              refresh_token :: String.t(),
              client_id :: String.t(),
              client_secret :: String.t()
            ) :: {:ok, map()} | {:error, term()}

  @doc """
  Creates a new EventSub subscription.

  ## Parameters
  - `subscription_data` - The subscription configuration
  - `token` - The OAuth token for authentication

  ## Returns
  - `{:ok, response}` with subscription details on success
  - `{:error, reason}` on failure
  """
  @callback create_subscription(subscription_data :: map(), token :: String.t()) ::
              {:ok, map()} | {:error, term()}

  @doc """
  Deletes an existing EventSub subscription.

  ## Parameters
  - `subscription_id` - The ID of the subscription to delete
  - `token` - The OAuth token for authentication

  ## Returns
  - `{:ok, response}` on success
  - `{:error, reason}` on failure
  """
  @callback delete_subscription(subscription_id :: String.t(), token :: String.t()) ::
              {:ok, map()} | {:error, term()}

  @doc """
  Lists all active EventSub subscriptions.

  ## Parameters
  - `token` - The OAuth token for authentication

  ## Returns
  - `{:ok, response}` with list of subscriptions on success
  - `{:error, reason}` on failure
  """
  @callback list_subscriptions(token :: String.t()) :: {:ok, map()} | {:error, term()}

  @doc """
  Gets user information from Twitch API.

  ## Parameters
  - `token` - The OAuth token for authentication

  ## Returns
  - `{:ok, response}` with user details on success
  - `{:error, reason}` on failure
  """
  @callback get_user_info(token :: String.t()) :: {:ok, map()} | {:error, term()}
end
