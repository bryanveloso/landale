defmodule Server.OverlayTracker do
  @moduledoc """
  Centralized overlay tracking for all channels.

  Manages a single ETS table for tracking overlay channel connections,
  preventing race conditions when multiple channels try to create the same table.

  This GenServer owns the ETS table and ensures it's created only once
  during application startup.
  """

  use GenServer
  require Logger

  @table_name :overlay_channel_tracker

  # Client API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Track an overlay channel join.
  """
  def track_overlay(socket_id, info) do
    :ets.insert(@table_name, {socket_id, info})
    :ok
  end

  @doc """
  Remove an overlay channel tracking.
  """
  def untrack_overlay(socket_id) do
    :ets.delete(@table_name, socket_id)
    :ok
  end

  @doc """
  Get all tracked overlays.
  """
  def list_overlays do
    :ets.tab2list(@table_name)
  end

  @doc """
  Check if the tracking table exists.
  """
  def table_exists? do
    :ets.whereis(@table_name) != :undefined
  end

  # Server callbacks

  @impl true
  def init([]) do
    # Create the ETS table owned by this process
    # Using :public so channels can read/write directly for performance
    # The GenServer ensures the table is created only once
    :ets.new(@table_name, [:set, :public, :named_table])

    Logger.info("OverlayTracker started with ETS table #{@table_name}")

    {:ok, %{table: @table_name}}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.warning("OverlayTracker received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end
end
