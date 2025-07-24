defmodule Server.Cache do
  @moduledoc """
  High-performance ETS-based caching system for hot data patterns.

  Provides TTL-based caching with automatic cleanup, performance monitoring,
  and configurable cache policies optimized for the streaming system's
  access patterns.

  ## Features

  - TTL-based expiration with automatic cleanup
  - Configurable cache policies per service
  - Performance metrics and telemetry integration
  - Bulk operations for efficient cache updates
  - Proactive cache refresh capabilities

  ## Usage

      # Get or compute cached value
      Server.Cache.get_or_compute(:obs_status, "connection_state", fn ->
        expensive_computation()
      end, ttl_seconds: 30)

      # Set cache value with TTL
      Server.Cache.set(:twitch_auth, "token_valid", true, ttl_seconds: 300)

      # Invalidate specific cache entry
      Server.Cache.invalidate(:obs_status, "connection_state")

      # Bulk set for efficient updates
      Server.Cache.bulk_set(:obs_metrics, [
        {"streaming_active", true},
        {"recording_active", false}
      ], ttl_seconds: 10)
  """

  use GenServer
  require Logger

  @cache_table_name :server_cache
  # Clean expired entries every 30 seconds
  @cleanup_interval_ms 30_000
  # 5 minutes default TTL
  @default_ttl_seconds 300

  @type cache_key :: {atom(), term()}
  @type cache_value :: term()
  @type ttl_seconds :: pos_integer()
  @type cache_options :: [ttl_seconds: ttl_seconds()]

  defstruct [
    :cleanup_timer,
    :stats
  ]

  ## Client API

  @doc """
  Starts the cache server.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets a cached value or computes and caches it if not present or expired.

  ## Parameters
  - `namespace` - Cache namespace (e.g. :obs_status, :twitch_auth)
  - `key` - Cache key within the namespace
  - `compute_fn` - Function to compute value if cache miss
  - `opts` - Options including :ttl_seconds

  ## Returns
  - Cached or computed value
  """
  @spec get_or_compute(atom(), term(), (-> cache_value()), cache_options()) :: cache_value()
  def get_or_compute(namespace, key, compute_fn, opts \\ []) do
    cache_key = {namespace, key}

    case get_if_valid(cache_key) do
      {:hit, value} ->
        # Update stats
        GenServer.cast(__MODULE__, {:cache_hit, namespace})
        value

      :miss ->
        # Compute value and cache it
        value = compute_fn.()
        ttl_seconds = Keyword.get(opts, :ttl_seconds, @default_ttl_seconds)
        set(namespace, key, value, ttl_seconds: ttl_seconds)

        # Update stats
        GenServer.cast(__MODULE__, {:cache_miss, namespace})
        value
    end
  end

  @doc """
  Sets a cache value with TTL.

  ## Parameters
  - `namespace` - Cache namespace
  - `key` - Cache key within the namespace
  - `value` - Value to cache
  - `opts` - Options including :ttl_seconds
  """
  @spec set(atom(), term(), cache_value(), cache_options()) :: :ok
  def set(namespace, key, value, opts \\ []) do
    ttl_seconds = Keyword.get(opts, :ttl_seconds, @default_ttl_seconds)
    expires_at = System.system_time(:second) + ttl_seconds

    cache_key = {namespace, key}
    cache_entry = {cache_key, value, expires_at}

    :ets.insert(@cache_table_name, cache_entry)

    Logger.debug("Cache set",
      namespace: namespace,
      key: inspect(key),
      ttl_seconds: ttl_seconds
    )

    :ok
  end

  @doc """
  Gets a cached value if present and not expired.

  ## Returns
  - `{:ok, value}` if cached and valid
  - `:error` if not cached or expired
  """
  @spec get(atom(), term()) :: {:ok, cache_value()} | :error
  def get(namespace, key) do
    cache_key = {namespace, key}

    case get_if_valid(cache_key) do
      {:hit, value} -> {:ok, value}
      :miss -> :error
    end
  end

  @doc """
  Invalidates a specific cache entry.

  ## Parameters
  - `namespace` - Cache namespace
  - `key` - Cache key to invalidate
  """
  @spec invalidate(atom(), term()) :: :ok
  def invalidate(namespace, key) do
    GenServer.cast(__MODULE__, {:invalidate, namespace, key})
    :ok
  end

  @doc """
  Invalidates all cache entries in a namespace.

  ## Parameters
  - `namespace` - Cache namespace to clear
  """
  @spec invalidate_namespace(atom()) :: :ok
  def invalidate_namespace(namespace) do
    GenServer.cast(__MODULE__, {:invalidate_namespace, namespace})
    :ok
  end

  @doc """
  Bulk sets multiple cache entries efficiently.

  ## Parameters
  - `namespace` - Cache namespace
  - `entries` - List of {key, value} tuples
  - `opts` - Options including :ttl_seconds
  """
  @spec bulk_set(atom(), [{term(), cache_value()}], cache_options()) :: :ok
  def bulk_set(namespace, entries, opts \\ []) do
    ttl_seconds = Keyword.get(opts, :ttl_seconds, @default_ttl_seconds)
    expires_at = System.system_time(:second) + ttl_seconds

    cache_entries =
      Enum.map(entries, fn {key, value} ->
        cache_key = {namespace, key}
        {cache_key, value, expires_at}
      end)

    :ets.insert(@cache_table_name, cache_entries)

    Logger.debug("Cache bulk set",
      namespace: namespace,
      count: length(entries),
      ttl_seconds: ttl_seconds
    )

    :ok
  end

  @doc """
  Refreshes a cache entry by recomputing its value.

  ## Parameters
  - `namespace` - Cache namespace
  - `key` - Cache key to refresh
  - `compute_fn` - Function to compute new value
  - `opts` - Options including :ttl_seconds
  """
  @spec refresh(atom(), term(), (-> cache_value()), cache_options()) :: :ok
  def refresh(namespace, key, compute_fn, opts \\ []) do
    value = compute_fn.()
    set(namespace, key, value, opts)
    :ok
  end

  @doc """
  Gets cache statistics for monitoring.

  ## Returns
  - Map with cache statistics
  """
  @spec stats() :: map()
  def stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @doc """
  Forces immediate cleanup of expired entries.
  """
  @spec cleanup() :: :ok
  def cleanup do
    GenServer.cast(__MODULE__, :force_cleanup)
  end

  ## GenServer Callbacks

  @impl true
  def init(_opts) do
    # Create ETS table for cache storage
    :ets.new(@cache_table_name, [:named_table, :protected, :set])

    # Schedule periodic cleanup
    cleanup_timer = schedule_cleanup()

    Logger.info("Server cache started",
      cleanup_interval_ms: @cleanup_interval_ms,
      default_ttl_seconds: @default_ttl_seconds
    )

    {:ok,
     %__MODULE__{
       cleanup_timer: cleanup_timer,
       stats: %{
         hits: %{},
         misses: %{},
         entries_cleaned: 0,
         last_cleanup: System.system_time(:second)
       }
     }}
  end

  @impl true
  def handle_cast({:cache_hit, namespace}, state) do
    new_stats = %{
      state.stats
      | hits: Map.update(state.stats.hits, namespace, 1, &(&1 + 1))
    }

    {:noreply, %{state | stats: new_stats}}
  end

  @impl true
  def handle_cast({:cache_miss, namespace}, state) do
    new_stats = %{
      state.stats
      | misses: Map.update(state.stats.misses, namespace, 1, &(&1 + 1))
    }

    {:noreply, %{state | stats: new_stats}}
  end

  @impl true
  def handle_cast(:force_cleanup, state) do
    new_state = perform_cleanup(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:invalidate, namespace, key}, state) do
    cache_key = {namespace, key}
    :ets.delete(@cache_table_name, cache_key)
    Logger.debug("Cache invalidated", namespace: namespace, key: inspect(key))
    {:noreply, state}
  end

  @impl true
  def handle_cast({:invalidate_namespace, namespace}, state) do
    # Use match pattern to delete all entries with the namespace
    pattern = {{namespace, :_}, :_, :_}
    :ets.match_delete(@cache_table_name, pattern)
    Logger.debug("Cache namespace invalidated", namespace: namespace)
    {:noreply, state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    # Include current cache size in stats
    current_size = :ets.info(@cache_table_name, :size)
    stats_with_size = Map.put(state.stats, :current_size, current_size)

    {:reply, stats_with_size, state}
  end

  @impl true
  def handle_info(:cleanup_expired, state) do
    # Perform cleanup and schedule next one
    new_state = perform_cleanup(state)
    cleanup_timer = schedule_cleanup()

    {:noreply, %{new_state | cleanup_timer: cleanup_timer}}
  end

  ## Private Functions

  defp get_if_valid(cache_key) do
    current_time = System.system_time(:second)

    case :ets.lookup(@cache_table_name, cache_key) do
      [{^cache_key, value, expires_at}] ->
        if current_time < expires_at do
          {:hit, value}
        else
          # Entry expired, remove it atomically
          # Use delete_object to ensure we only delete if it hasn't changed
          :ets.delete_object(@cache_table_name, {cache_key, value, expires_at})
          :miss
        end

      [] ->
        :miss
    end
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup_expired, @cleanup_interval_ms)
  end

  defp perform_cleanup(state) do
    current_time = System.system_time(:second)

    # Find and delete expired entries
    expired_pattern = {:_, :_, :"$1"}
    guard = [{:<, :"$1", current_time}]

    entries_cleaned = :ets.select_delete(@cache_table_name, [{expired_pattern, guard, [true]}])

    if entries_cleaned > 0 do
      Logger.debug("Cache cleanup completed", entries_cleaned: entries_cleaned)
    end

    # Update stats
    new_stats =
      state.stats
      |> Map.put(:entries_cleaned, state.stats.entries_cleaned + entries_cleaned)
      |> Map.put(:last_cleanup, current_time)

    %{state | stats: new_stats}
  end
end
