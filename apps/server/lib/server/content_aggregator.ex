defmodule Server.ContentAggregator do
  @moduledoc """
  Content aggregation service for the omnibar system.

  Aggregates real-time data for different content types:
  - Emote statistics and usage tracking
  - Recent follower lists
  - Sub train metrics
  - Stream goals and daily stats
  - IronMON-specific statistics
  """

  use GenServer
  require Logger

  # ETS table names
  @emote_stats_table :emote_stats
  @followers_table :recent_followers
  @daily_stats_table :daily_stats

  # Memory management limits
  @max_followers 100
  @max_emote_entries 1000

  defstruct [
    :daily_reset_timer
  ]

  ## Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Get current emote statistics"
  def get_emote_stats do
    GenServer.call(__MODULE__, :get_emote_stats)
  end

  @doc "Get recent followers list"
  def get_recent_followers(limit \\ 10) do
    GenServer.call(__MODULE__, {:get_recent_followers, limit})
  end

  @doc "Get daily stream statistics"
  def get_daily_stats do
    GenServer.call(__MODULE__, :get_daily_stats)
  end

  @doc "Record emote usage from chat event"
  def record_emote_usage(emotes, native_emotes, username) do
    GenServer.cast(__MODULE__, {:record_emote_usage, emotes, native_emotes, username})
  end

  @doc "Record new follower"
  def record_follower(username, timestamp) do
    GenServer.cast(__MODULE__, {:record_follower, username, timestamp})
  end

  ## GenServer Implementation

  @impl true
  def init(_opts) do
    Logger.info("ContentAggregator starting")

    # Create ETS tables for fast data access
    :ets.new(@emote_stats_table, [:named_table, :protected, :set])
    :ets.new(@followers_table, [:named_table, :protected, :ordered_set])
    :ets.new(@daily_stats_table, [:named_table, :protected, :set])

    # Subscribe to relevant events
    Phoenix.PubSub.subscribe(Server.PubSub, "chat")
    Phoenix.PubSub.subscribe(Server.PubSub, "followers")

    # Initialize daily stats
    reset_daily_stats()

    # Schedule daily reset at midnight
    daily_reset_timer = schedule_daily_reset()

    # Schedule periodic memory cleanup (every hour)
    Process.send_after(self(), :cleanup_memory, 3_600_000)

    state = %__MODULE__{
      daily_reset_timer: daily_reset_timer
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:get_emote_stats, _from, state) do
    emote_stats = get_all_emote_stats()
    {:reply, emote_stats, state}
  end

  @impl true
  def handle_call({:get_recent_followers, limit}, _from, state) do
    followers = get_recent_followers_list(limit)
    {:reply, followers, state}
  end

  @impl true
  def handle_call(:get_daily_stats, _from, state) do
    stats = get_current_daily_stats()
    {:reply, stats, state}
  end

  @impl true
  def handle_cast({:record_emote_usage, emotes, native_emotes, _username}, state) do
    # Record regular emotes
    Enum.each(emotes, fn emote ->
      increment_emote_count(emote, :regular)
    end)

    # Record native (avalon-prefixed) emotes
    Enum.each(native_emotes, fn emote ->
      increment_emote_count(emote, :native)
    end)

    # Update daily stats
    increment_daily_stat(:total_messages)

    {:noreply, state}
  end

  @impl true
  def handle_cast({:record_follower, username, timestamp}, state) do
    # Store follower with timestamp for ordering
    :ets.insert(@followers_table, {timestamp, username})

    # Update daily stats
    increment_daily_stat(:total_follows)

    # Cleanup old followers (keep last 100)
    cleanup_old_followers()

    {:noreply, state}
  end

  # Handle chat messages for emote extraction
  @impl true
  def handle_info({:chat_message, event}, state) do
    try do
      record_emote_usage(event.emotes, event.native_emotes, event.user_name)
    rescue
      error ->
        Logger.error("Failed to record emote usage", error: inspect(error), event: inspect(event))
    end

    {:noreply, state}
  end

  # Handle new followers
  @impl true
  def handle_info({:new_follower, event}, state) do
    try do
      record_follower(event.username, event.timestamp)
    rescue
      error ->
        Logger.error("Failed to record follower", error: inspect(error), event: inspect(event))
    end

    {:noreply, state}
  end

  # Handle daily reset
  @impl true
  def handle_info(:daily_reset, state) do
    Logger.info("Performing daily stats reset")
    reset_daily_stats()

    # Schedule next reset
    daily_reset_timer = schedule_daily_reset()

    new_state = %{state | daily_reset_timer: daily_reset_timer}
    {:noreply, new_state}
  end

  # Handle periodic cleanup
  @impl true
  def handle_info(:cleanup_memory, state) do
    Logger.debug("Performing memory cleanup")
    cleanup_old_followers()
    cleanup_excess_emotes()

    # Schedule next cleanup (every hour)
    Process.send_after(self(), :cleanup_memory, 3_600_000)
    {:noreply, state}
  end

  ## Private Functions

  defp get_all_emote_stats do
    regular_emotes =
      :ets.foldl(
        fn
          {{emote, :regular}, count_today, count_alltime}, acc ->
            Map.put(acc, emote, %{today: count_today, alltime: count_alltime, type: :regular})

          _, acc ->
            acc
        end,
        %{},
        @emote_stats_table
      )

    native_emotes =
      :ets.foldl(
        fn
          {{emote, :native}, count_today, count_alltime}, acc ->
            Map.put(acc, emote, %{today: count_today, alltime: count_alltime, type: :native})

          _, acc ->
            acc
        end,
        %{},
        @emote_stats_table
      )

    %{
      regular_emotes: regular_emotes,
      native_emotes: native_emotes,
      top_today: get_top_emotes_today(10),
      top_alltime: get_top_emotes_alltime(10)
    }
  end

  defp get_top_emotes_today(limit) do
    :ets.foldl(
      fn
        {{emote, type}, {count_today, _count_alltime}}, acc ->
          [{count_today, emote, type} | acc]

        _, acc ->
          acc
      end,
      [],
      @emote_stats_table
    )
    |> Enum.sort(:desc)
    |> Enum.take(limit)
    |> Enum.map(fn {count, emote, type} ->
      %{emote: emote, count: count, type: type}
    end)
  end

  defp get_top_emotes_alltime(limit) do
    :ets.foldl(
      fn
        {{emote, type}, {_count_today, count_alltime}}, acc ->
          [{count_alltime, emote, type} | acc]

        _, acc ->
          acc
      end,
      [],
      @emote_stats_table
    )
    |> Enum.sort(:desc)
    |> Enum.take(limit)
    |> Enum.map(fn {count, emote, type} ->
      %{emote: emote, count: count, type: type}
    end)
  end

  defp increment_emote_count(emote, type) do
    key = {emote, type}

    # Use atomic update_counter with default value fallback
    try do
      :ets.update_counter(@emote_stats_table, key, [{2, 1}, {3, 1}])
    catch
      :error, :badarg ->
        # Key doesn't exist, insert initial value and try again
        :ets.insert(@emote_stats_table, {key, 0, 0})
        :ets.update_counter(@emote_stats_table, key, [{2, 1}, {3, 1}])
    end
  end

  defp get_recent_followers_list(limit) do
    :ets.foldl(
      fn {timestamp, username}, acc ->
        [{timestamp, username} | acc]
      end,
      [],
      @followers_table
    )
    |> Enum.sort(:desc)
    |> Enum.take(limit)
    |> Enum.map(fn {_timestamp, username} -> username end)
  end

  defp cleanup_old_followers do
    all_followers = :ets.tab2list(@followers_table)

    if length(all_followers) > @max_followers do
      # Keep only the most recent followers
      sorted_followers = Enum.sort(all_followers, :desc)
      {_keep, remove} = Enum.split(sorted_followers, @max_followers)

      Enum.each(remove, fn {timestamp, _username} ->
        :ets.delete(@followers_table, timestamp)
      end)
    end
  end

  defp get_current_daily_stats do
    # Get individual counters
    total_messages =
      case :ets.lookup(@daily_stats_table, {:daily_counter, :total_messages}) do
        [{_, count}] -> count
        [] -> 0
      end

    total_follows =
      case :ets.lookup(@daily_stats_table, {:daily_counter, :total_follows}) do
        [{_, count}] -> count
        [] -> 0
      end

    # Get or create started_at timestamp
    started_at =
      case :ets.lookup(@daily_stats_table, :started_at) do
        [{:started_at, timestamp}] ->
          timestamp

        [] ->
          timestamp = DateTime.utc_now()
          :ets.insert(@daily_stats_table, {:started_at, timestamp})
          timestamp
      end

    %{
      total_messages: total_messages,
      total_follows: total_follows,
      started_at: started_at
    }
  end

  defp increment_daily_stat(stat_key) do
    # Atomic increment using update_counter pattern
    # For map-based stats, we need to use a different key for each stat
    stat_counter_key = {:daily_counter, stat_key}

    try do
      :ets.update_counter(@daily_stats_table, stat_counter_key, 1)
    catch
      :error, :badarg ->
        # Key doesn't exist, insert initial value and try again
        :ets.insert(@daily_stats_table, {stat_counter_key, 0})
        :ets.update_counter(@daily_stats_table, stat_counter_key, 1)
    end
  end

  defp reset_daily_stats do
    # Reset daily emote counts but keep all-time counts
    :ets.foldl(
      fn
        {{emote, type}, _count_today, count_alltime}, _acc ->
          :ets.insert(@emote_stats_table, {{emote, type}, 0, count_alltime})
          :ok

        _, acc ->
          acc
      end,
      :ok,
      @emote_stats_table
    )

    # Reset daily counters
    :ets.insert(@daily_stats_table, {{:daily_counter, :total_messages}, 0})
    :ets.insert(@daily_stats_table, {{:daily_counter, :total_follows}, 0})
    :ets.insert(@daily_stats_table, {:started_at, DateTime.utc_now()})

    Logger.info("Daily stats reset completed")
  end

  defp cleanup_excess_emotes do
    emote_count = :ets.info(@emote_stats_table, :size)

    if emote_count > @max_emote_entries do
      # Get all emotes sorted by all-time count (descending)
      all_emotes = :ets.tab2list(@emote_stats_table)
      sorted_emotes = Enum.sort_by(all_emotes, fn {_key, {_today, alltime}} -> alltime end, :desc)

      # Keep only the top emotes
      {keep, remove} = Enum.split(sorted_emotes, @max_emote_entries)

      # Remove the least popular emotes
      Enum.each(remove, fn {key, _counts} ->
        :ets.delete(@emote_stats_table, key)
      end)

      Logger.info("Emote cleanup completed",
        emotes_before: emote_count,
        emotes_after: length(keep),
        emotes_removed: length(remove)
      )
    end
  end

  defp schedule_daily_reset do
    # Calculate milliseconds until next midnight
    now = DateTime.utc_now()
    tomorrow = DateTime.add(now, 1, :day)
    midnight_tomorrow = %{tomorrow | hour: 0, minute: 0, second: 0, microsecond: {0, 0}}

    milliseconds_until_midnight = DateTime.diff(midnight_tomorrow, now, :millisecond)

    Process.send_after(self(), :daily_reset, milliseconds_until_midnight)
  end
end
