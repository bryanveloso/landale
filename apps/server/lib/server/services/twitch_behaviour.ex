defmodule Server.Services.TwitchBehaviour do
  @moduledoc """
  Behaviour for Twitch service to enable mocking in tests.
  """

  @callback get_status() :: {:ok, map()} | {:error, term()}
end
