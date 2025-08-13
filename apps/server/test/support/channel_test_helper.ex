defmodule Server.Test.ChannelTestHelper do
  @moduledoc """
  Helper functions for Phoenix channel tests.

  Provides utilities for setting up common test infrastructure
  needed by channel tests, including OverlayTracker and registries.
  """

  @doc """
  Ensures all necessary infrastructure for channel tests is started.

  This includes:
  - OBS SessionRegistry (for OBS-related channels)
  - OverlayTracker (for overlay tracking functionality)
  - PubSub (for Phoenix channel communication)

  Use this in your channel test setup:

      setup do
        Server.Test.ChannelTestHelper.ensure_infrastructure_started()
        # ... rest of your setup
      end
  """
  def ensure_infrastructure_started do
    # Start OBS SessionRegistry if needed
    ensure_obs_registry()

    # Start OverlayTracker if needed
    ensure_overlay_tracker()

    # Start PubSub if needed
    ensure_pubsub()

    :ok
  end

  defp ensure_obs_registry do
    unless Process.whereis(Server.Services.OBS.SessionRegistry) do
      case Registry.start_link(keys: :unique, name: Server.Services.OBS.SessionRegistry) do
        {:ok, _} -> :ok
        {:error, {:already_started, _}} -> :ok
      end
    end
  end

  defp ensure_overlay_tracker do
    unless Process.whereis(Server.OverlayTracker) do
      case Server.OverlayTracker.start_link([]) do
        {:ok, _} ->
          :ok

        {:error, {:already_started, _}} ->
          :ok

        error ->
          # Log but don't fail - some tests may not need it
          IO.puts("Warning: Could not start OverlayTracker: #{inspect(error)}")
          :ok
      end
    end
  end

  defp ensure_pubsub do
    unless Process.whereis(Server.PubSub) do
      case Phoenix.PubSub.Supervisor.start_link(name: Server.PubSub) do
        {:ok, _} -> :ok
        {:error, {:already_started, _}} -> :ok
      end
    end
  end
end
