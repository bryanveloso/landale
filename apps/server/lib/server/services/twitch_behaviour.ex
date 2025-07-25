defmodule Server.Services.TwitchBehaviour do
  @moduledoc """
  Behaviour for Twitch service to enable mocking in tests.

  This includes all public API methods for the Twitch service,
  including those also defined in Server.ServiceBehaviour.
  """

  # Common service interface (duplicated from ServiceBehaviour)
  @callback start_link(opts :: keyword()) :: GenServer.on_start()
  @callback get_status() :: {:ok, map()} | {:error, term()}
  @callback get_health() :: {:ok, map()} | {:error, term()}
  @callback get_info() :: map()

  # Twitch-specific methods
  @callback get_state() :: map()
  @callback get_connection_state() :: {:ok, map()} | {:error, term()}
  @callback get_subscription_metrics() :: {:ok, map()} | {:error, term()}
  @callback create_subscription(event_type :: String.t(), condition :: map(), opts :: keyword()) ::
              {:ok, map()} | {:error, term()}
  @callback delete_subscription(subscription_id :: String.t()) :: {:ok, map()} | {:error, term()}
  @callback list_subscriptions() :: {:ok, list()} | {:error, term()}
end
