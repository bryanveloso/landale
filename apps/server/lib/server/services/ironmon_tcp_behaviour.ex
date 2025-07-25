defmodule Server.Services.IronmonTCPBehaviour do
  @moduledoc """
  Behaviour for IronmonTCP service to enable mocking in tests.

  This includes all public API methods for the IronmonTCP service,
  including those also defined in Server.ServiceBehaviour.
  """

  # Common service interface (duplicated from ServiceBehaviour)
  @callback start_link(opts :: keyword()) :: GenServer.on_start()
  @callback get_status() :: {:ok, map()} | {:error, term()}
  @callback get_health() :: {:ok, map()} | {:error, term()}
  @callback get_info() :: map()

  # IronmonTCP-specific methods
  @callback list_challenges() :: {:ok, list()} | {:error, term()}
  @callback list_checkpoints(integer()) :: {:ok, list()} | {:error, term()}
  @callback get_checkpoint_stats(integer()) :: {:ok, map()} | {:error, term()}
  @callback get_recent_results(integer()) :: {:ok, list()} | {:error, term()}
  @callback get_active_challenge(integer()) :: {:ok, map()} | {:error, term()}
end
