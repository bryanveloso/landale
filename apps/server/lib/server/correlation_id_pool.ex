defmodule Server.CorrelationIdPool do
  @moduledoc """
  Pre-generated correlation ID pool for high-frequency event publishing.

  Maintains a pool of pre-generated correlation IDs to reduce UUID generation
  overhead during high-frequency operations like event publishing and telemetry.
  Falls back to on-demand generation when pool is empty.

  Optimized for single-user streaming system with moderate event throughput.

  ## Implementation Note

  This module uses a `:public` ETS table instead of the standard `:protected` access.
  This is an intentional design decision to enable atomic `take` operations from any
  process without going through the GenServer, preventing it from becoming a bottleneck.
  The table is only used for ID storage with no sensitive data, making public access
  safe in this specific use case.
  """

  use GenServer
  require Logger

  @pool_size 100
  @refill_threshold 20
  @pool_table_name :correlation_id_pool

  ## Client API

  @doc """
  Starts the correlation ID pool.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets a correlation ID from the pool.

  Returns a pre-generated ID from the pool if available, otherwise
  generates one on-demand.

  ## Returns
  - Correlation ID string (8 characters)
  """
  @spec get() :: binary()
  def get do
    # Use :ets.first to get any available key, then atomically take it
    case :ets.first(@pool_table_name) do
      :"$end_of_table" ->
        # Pool empty, generate on demand
        Server.CorrelationId.generate()

      key ->
        # Atomically take the entry with this key
        case :ets.take(@pool_table_name, key) do
          [{^key, id}] ->
            # Successfully took an ID, trigger async refill if needed
            maybe_refill_pool()
            id

          [] ->
            # Race condition: another process took it first
            # Fall back to generation to avoid unbounded recursion
            Server.CorrelationId.generate()
        end
    end
  end

  @doc """
  Gets pool statistics for monitoring.

  ## Returns
  - Map with pool size and refill information
  """
  @spec stats() :: map()
  def stats do
    case :ets.info(@pool_table_name, :size) do
      :undefined -> %{pool_size: 0, status: :not_started}
      size -> %{pool_size: size, refill_threshold: @refill_threshold}
    end
  end

  ## GenServer Callbacks

  @impl true
  def init(_opts) do
    # Create ETS table for the pool
    # Using :public to allow atomic take operations from any process
    # Using :set table type for unique keys per ID
    :ets.new(@pool_table_name, [:named_table, :public, :set])

    # Pre-fill the pool
    fill_pool()

    Logger.info("Correlation ID pool started with #{@pool_size} IDs")

    {:ok, %{}}
  end

  @impl true
  def handle_info(:refill_pool, state) do
    current_size = :ets.info(@pool_table_name, :size)

    if current_size < @refill_threshold do
      refill_count = @pool_size - current_size
      add_ids_to_pool(refill_count)

      Logger.debug("Correlation ID pool refilled",
        added: refill_count,
        new_size: current_size + refill_count
      )
    end

    {:noreply, state}
  end

  ## Private Functions

  defp fill_pool do
    add_ids_to_pool(@pool_size)
  end

  defp add_ids_to_pool(count) when count > 0 do
    # Generate unique key-value pairs where key is the ID itself
    ids =
      for _ <- 1..count//1 do
        id = Server.CorrelationId.generate()
        {id, id}
      end

    :ets.insert(@pool_table_name, ids)
  end

  defp add_ids_to_pool(_), do: :ok

  defp maybe_refill_pool do
    # Check if refill needed without blocking
    current_size = :ets.info(@pool_table_name, :size)

    if current_size <= @refill_threshold do
      send(__MODULE__, :refill_pool)
    end
  end
end
