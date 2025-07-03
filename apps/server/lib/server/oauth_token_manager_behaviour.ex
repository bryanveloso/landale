defmodule Server.OAuthTokenManagerBehaviour do
  @moduledoc """
  Behaviour for OAuth token management implementations.

  This behaviour defines the interface for OAuth token managers,
  allowing for proper dependency injection and testing with mocks.
  """

  @type token_info :: %{
          access_token: binary(),
          refresh_token: binary() | nil,
          expires_at: DateTime.t() | nil,
          scopes: MapSet.t() | nil,
          user_id: binary() | nil
        }

  @type manager_state :: %{
          storage_key: atom(),
          storage_path: binary(),
          dets_table: atom() | nil,
          oauth2_client: Server.OAuth2Client.client_config(),
          token_info: token_info() | nil,
          refresh_buffer_ms: integer(),
          telemetry_prefix: [atom()]
        }

  @doc """
  Gets a valid access token, refreshing if necessary.

  ## Parameters
  - `manager` - Token manager state

  ## Returns
  - `{:ok, token, updated_manager}` - Valid token retrieved
  - `{:error, reason}` - No valid token available
  """
  @callback get_valid_token(manager_state()) :: {:ok, binary(), manager_state()} | {:error, term()}
end
