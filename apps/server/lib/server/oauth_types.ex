defmodule Server.OAuthTypes do
  @moduledoc """
  Standardized OAuth data structures to prevent type confusion.

  This module defines structs for all OAuth-related data to ensure
  consistent access patterns throughout the codebase.
  """

  defmodule TokenResponse do
    @moduledoc "OAuth token response from provider"
    defstruct [
      :access_token,
      :refresh_token,
      :expires_in,
      :scope,
      :token_type
    ]

    @type t :: %__MODULE__{
            access_token: String.t(),
            refresh_token: String.t() | nil,
            expires_in: integer() | nil,
            scope: [String.t()] | nil,
            token_type: String.t()
          }
  end

  defmodule ValidationResponse do
    @moduledoc "Token validation response from provider"
    defstruct [
      :user_id,
      :client_id,
      :scopes,
      :expires_in
    ]

    @type t :: %__MODULE__{
            user_id: String.t(),
            client_id: String.t(),
            scopes: [String.t()] | nil,
            expires_in: integer() | nil
          }
  end

  defmodule TokenInfo do
    @moduledoc "Internal token storage format"
    defstruct [
      :access_token,
      :refresh_token,
      :expires_at,
      :scopes,
      :user_id,
      :client_id
    ]

    @type t :: %__MODULE__{
            access_token: String.t(),
            refresh_token: String.t() | nil,
            expires_at: DateTime.t() | nil,
            scopes: MapSet.t() | nil,
            user_id: String.t() | nil,
            client_id: String.t() | nil
          }
  end
end
