defmodule Server.Test.OBSTestHelper do
  @moduledoc """
  Helper functions for OBS-related tests.

  Provides utilities for setting up the OBS SessionRegistry and other
  common test infrastructure needed by OBS components.
  """

  @doc """
  Ensures the OBS SessionRegistry is started for tests.

  Many OBS components depend on the SessionRegistry for process lookup.
  This function starts it if not already running, preventing the
  "unknown registry" errors in tests.

  Returns :ok if successful, or {:error, reason} if it fails.
  """
  def ensure_registry_started do
    case start_registry() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      error -> error
    end
  end

  @doc """
  Starts the OBS SessionRegistry with supervision.

  Use this in your test setup to ensure the registry is available:

      setup do
        Server.Test.OBSTestHelper.ensure_registry_started()
        :ok
      end
  """
  def start_registry do
    Registry.start_link(
      keys: :unique,
      name: Server.Services.OBS.SessionRegistry
    )
  end

  @doc """
  Generates a unique session ID for testing.

  Ensures no collision between concurrent test runs.
  """
  def test_session_id(prefix \\ "test") do
    "#{prefix}_#{System.unique_integer([:positive])}_#{:rand.uniform(100_000)}"
  end

  @doc """
  Cleans up OBS processes for a given session.

  Useful in test teardown to ensure no lingering processes.
  """
  def cleanup_session(session_id) do
    # Find and stop all processes for this session
    Server.Services.OBS.SessionRegistry
    |> Registry.select([{{:"$1", :"$2", :"$3"}, [{:==, {:element, 1, :"$1"}, session_id}], [:"$2"]}])
    |> Enum.each(&Process.exit(&1, :kill))

    :ok
  end
end
