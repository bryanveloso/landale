defmodule Server.Services.RainwaveBehaviour do
  @moduledoc """
  Behaviour for Rainwave service to enable mocking in tests.

  This includes all public API methods for the Rainwave service,
  including those also defined in Server.ServiceBehaviour.
  """

  # Common service interface (duplicated from ServiceBehaviour)
  @callback start_link(opts :: keyword()) :: GenServer.on_start()
  @callback get_status() :: {:ok, map()} | {:error, term()}
  @callback get_health() :: {:ok, map()} | {:error, term()}
  @callback get_info() :: map()

  # Rainwave-specific methods
  @callback set_enabled(enabled :: boolean()) :: :ok | {:error, term()}
  @callback set_station(station :: String.t()) :: :ok | {:error, term()}
end
