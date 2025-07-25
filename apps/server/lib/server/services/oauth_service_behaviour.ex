defmodule Server.Services.OAuthServiceBehaviour do
  @moduledoc """
  Behaviour for the centralized OAuth service.
  """

  @callback get_health() :: {:ok, map()} | {:error, term()}
  @callback get_info() :: map()
  @callback get_status() :: {:ok, map()} | {:error, term()}
  @callback register_service(atom(), map()) :: :ok | {:error, term()}
  @callback get_valid_token(atom()) :: {:ok, map()} | {:error, term()}
  @callback store_tokens(atom(), map()) :: :ok | {:error, term()}
  @callback refresh_token(atom()) :: {:ok, map()} | {:error, term()}
  @callback get_token_info(atom()) :: {:ok, map()} | {:error, :not_found}
  @callback validate_token(atom()) :: {:ok, map()} | {:error, term()}
end
