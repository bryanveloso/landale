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
    :ets.new(@emote_stats_table, [:named_table, :public, :set])
    :ets.new(@followers_table, [:named_table, :public, :ordered_set])
    :ets.new(@daily_stats_table, [:named_table, :public, :set])

    # Subscribe to relevant events
    Phoenix.PubSub.subscribe(Server.PubSub, "chat")
    Phoenix.PubSub.subscribe(Server.PubSub, "followers")

    # Initialize daily stats
    reset_daily_stats()

    # Schedule daily reset at midnight
    daily_reset_timer = schedule_daily_reset()

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
  def handle_cast({:record_emote_usage, emotes, native_emotes, username}, state) do
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
    record_emote_usage(event.emotes, event.native_emotes, event.username)
    {:noreply, state}
  end

  # Handle new followers
  @impl true
  def handle_info({:new_follower, event}, state) do
    record_follower(event.username, event.timestamp)
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

  ## Private Functions

  defp get_all_emote_stats do
    regular_emotes = :ets.foldl(fn
      {{emote, :regular}, {count_today, count_alltime}}, acc ->
        Map.put(acc, emote, %{today: count_today, alltime: count_alltime, type: :regular})
      _, acc -> acc
    end, %{}, @emote_stats_table)

    native_emotes = :ets.foldl(fn
      {{emote, :native}, {count_today, count_alltime}}, acc ->
        Map.put(acc, emote, %{today: count_today, alltime: count_alltime, type: :native})
      _, acc -> acc
    end, %{}, @emote_stats_table)

    %{
      regular_emotes: regular_emotes,
      native_emotes: native_emotes,
      top_today: get_top_emotes_today(10),
      top_alltime: get_top_emotes_alltime(10)
    }
  end

  defp get_top_emotes_today(limit) do
    :ets.foldl(fn
      {{emote, type}, {count_today, _count_alltime}}, acc ->
        [{count_today, emote, type} | acc]
      _, acc -> acc
    end, [], @emote_stats_table)
    |> Enum.sort(:desc)
    |> Enum.take(limit)
    |> Enum.map(fn {count, emote, type} -> 
      %{emote: emote, count: count, type: type}
    end)
  end

  defp get_top_emotes_alltime(limit) do
    :ets.foldl(fn
      {{emote, type}, {_count_today, count_alltime}}, acc ->
        [{count_alltime, emote, type} | acc]
      _, acc -> acc
    end, [], @emote_stats_table)
    |> Enum.sort(:desc)
    |> Enum.take(limit)
    |> Enum.map(fn {count, emote, type} -> 
      %{emote: emote, count: count, type: type}
    end)
  end

  defp increment_emote_count(emote, type) do
    key = {emote, type}
    
    case :ets.lookup(@emote_stats_table, key) do
      [{^key, {count_today, count_alltime}}] ->
        :ets.insert(@emote_stats_table, {key, {count_today + 1, count_alltime + 1}})
      [] ->
        :ets.insert(@emote_stats_table, {key, {1, 1}})
    end
  end

  defp get_recent_followers_list(limit) do
    :ets.foldl(fn {timestamp, username}, acc ->
      [{timestamp, username} | acc]
    end, [], @followers_table)
    |> Enum.sort(:desc)
    |> Enum.take(limit)
    |> Enum.map(fn {_timestamp, username} -> username end)
  end

  defp cleanup_old_followers do
    all_followers = :ets.tab2list(@followers_table)
    if length(all_followers) > 100 do
      # Keep only the 100 most recent
      sorted_followers = Enum.sort(all_followers, :desc)
      {keep, remove} = Enum.split(sorted_followers, 100)
      
      Enum.each(remove, fn {timestamp, _username} ->
        :ets.delete(@followers_table, timestamp)
      end)
    end
  end

  defp get_current_daily_stats do
    case :ets.lookup(@daily_stats_table, :stats) do
      [{:stats, stats}] -> stats
      [] -> %{total_messages: 0, total_follows: 0, started_at: DateTime.utc_now()}
    end
  end

  defp increment_daily_stat(stat_key) do
    current_stats = get_current_daily_stats()
    new_count = Map.get(current_stats, stat_key, 0) + 1
    updated_stats = Map.put(current_stats, stat_key, new_count)
    :ets.insert(@daily_stats_table, {:stats, updated_stats})
  end

  defp reset_daily_stats do
    # Reset daily emote counts but keep all-time counts
    :ets.foldl(fn
      {{emote, type}, {_count_today, count_alltime}}, _acc ->
        :ets.insert(@emote_stats_table, {{emote, type}, {0, count_alltime}})
        :ok
      _, acc -> acc
    end, :ok, @emote_stats_table)

    # Reset daily stats
    daily_stats = %{
      total_messages: 0,
      total_follows: 0,
      started_at: DateTime.utc_now()
    }
    :ets.insert(@daily_stats_table, {:stats, daily_stats})

    Logger.info("Daily stats reset completed")
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