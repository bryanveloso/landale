defmodule Server.Services.IronmonTCPBehaviour do
  @moduledoc """
  Behaviour for IronmonTCP service to enable mocking in tests.
  """

  @callback get_status() :: {:ok, map()} | {:error, term()}
  @callback list_challenges() :: {:ok, list()} | {:error, term()}
  @callback list_checkpoints(integer()) :: {:ok, list()} | {:error, term()}
  @callback get_checkpoint_stats(integer()) :: {:ok, map()} | {:error, term()}
  @callback get_recent_results(integer()) :: {:ok, list()} | {:error, term()}
  @callback get_active_challenge(integer()) :: {:ok, map()} | {:error, term()}
end
