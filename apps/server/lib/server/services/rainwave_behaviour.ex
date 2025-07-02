defmodule Server.Services.RainwaveBehaviour do
  @moduledoc """
  Behaviour for Rainwave service to enable mocking in tests.
  """

  @callback get_status() :: {:ok, map()} | {:error, term()}
end
