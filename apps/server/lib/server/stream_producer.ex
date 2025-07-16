defmodule Server.StreamProducer do
  @moduledoc """
  Central state machine for stream overlay coordination.

  Manages priority-based content scheduling:
  - Alerts (priority 100) - breaking news style interrupts
  - Sub trains (priority 50) - subscription celebration timers  
  - Ticker content (priority 10) - rotating stats and metrics

  Coordinates with show contexts (IronMON, variety, coding) to determine
  appropriate content types and theming.
  """

  use GenServer
  require Logger

  alias Server.Domains.StreamState

  # Default timing configuration - can be overridden via Application config
  defp ticker_interval, do: Application.get_env(:server, :ticker_interval, 15_000)
  defp sub_train_duration, do: Application.get_env(:server, :sub_train_duration, 300_000)
  defp cleanup_interval, do: Application.get_env(:server, :cleanup_interval, 600_000)
  defp max_timers, do: Application.get_env(:server, :max_timers, 100)

  # Cleanup configuration
  @cleanup_config Application.compile_env(:server, :cleanup_settings, %{
                    max_interrupt_stack_size: 50,
                    interrupt_stack_keep_count: 25
                  })

  defp max_interrupt_stack_size, do: Map.get(@cleanup_config, :max_interrupt_stack_size, 50)
  defp interrupt_stack_keep_count, do: Map.get(@cleanup_config, :interrupt_stack_keep_count, 25)
  @state_persistence_table :stream_producer_state

  defstruct current_show: :variety,
            active_content: nil,
            interrupt_stack: [],
            ticker_rotation: [],
            ticker_index: 0,
            timers: %{},
            version: 0,
            last_updated: nil,
            metadata: %{last_updated: nil, state_version: 0}

  ## Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Get current stream state"
  def get_current_state do
    GenServer.call(__MODULE__, :get_state)
  end

  @doc "Change the current show context"
  def change_show(show, metadata \\ %{}) do
    GenServer.cast(__MODULE__, {:change_show, show, metadata})
  end

  @doc "Add a priority interrupt (alert, sub train, etc.)"
  def add_interrupt(type, data, opts \\ []) do
    GenServer.cast(__MODULE__, {:add_interrupt, type, data, opts})
  end

  @doc "Remove an interrupt by ID"
  def remove_interrupt(interrupt_id) do
    GenServer.cast(__MODULE__, {:remove_interrupt, interrupt_id})
  end

  @doc "Update ticker content for current show"
  def update_ticker_content(content_list) do
    GenServer.cast(__MODULE__, {:update_ticker_content, content_list})
  end

  @doc "Force display specific content (manual override)"
  def force_content(content_type, data, duration \\ 30_000) do
    GenServer.cast(__MODULE__, {:force_content, content_type, data, duration})
  end

  ## GenServer Implementation

  @impl true
  def init(_opts) do
    Logger.info("StreamProducer starting")

    # Subscribe to various event sources
    Phoenix.PubSub.subscribe(Server.PubSub, "chat")
    Phoenix.PubSub.subscribe(Server.PubSub, "followers")
    Phoenix.PubSub.subscribe(Server.PubSub, "subscriptions")
    Phoenix.PubSub.subscribe(Server.PubSub, "cheers")
    Phoenix.PubSub.subscribe(Server.PubSub, "twitch:events")
    Phoenix.PubSub.subscribe(Server.PubSub, "channel:updates")

    # Create persistence table (public so it survives process restarts)
    :ets.new(@state_persistence_table, [:named_table, :set, :public])

    # Try to restore previous state
    state =
      case restore_state() do
        nil ->
          Logger.info("Starting with fresh state")

          %__MODULE__{
            current_show: :variety,
            ticker_rotation: default_ticker_content(:variety),
            metadata: %{last_updated: DateTime.utc_now(), state_version: 0}
          }

        restored_state ->
          Logger.info("Restored previous state",
            show: restored_state.current_show,
            version: restored_state.version,
            interrupts: length(restored_state.interrupt_stack)
          )

          # Restore timers for active interrupts
          restored_state = restore_interrupt_timers(restored_state)

          # Ensure metadata exists (for backward compatibility)
          case restored_state.metadata do
            nil ->
              %{restored_state | metadata: %{last_updated: DateTime.utc_now(), state_version: restored_state.version}}

            _ ->
              restored_state
          end
      end

    # Start ticker rotation and cleanup timer
    schedule_ticker_rotation()
    schedule_cleanup()

    # Save initial state
    persist_state(state)

    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_cast({:change_show, show, metadata}, state) do
    Logger.info("Show changed", show: show, metadata: metadata)

    new_state = StreamState.update_show_context(state, show)
    new_state = %{new_state | ticker_index: 0}

    Phoenix.PubSub.broadcast(
      Server.PubSub,
      "stream:updates",
      {:show_change,
       %{
         show: show,
         game: metadata[:game],
         changed_at: DateTime.utc_now()
       }}
    )

    broadcast_state_update(new_state)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:add_interrupt, type, data, opts}, state) do
    new_state = StreamState.add_interrupt(state, type, data, opts)

    interrupt = List.first(new_state.interrupt_stack)
    duration = interrupt.duration

    {_timer_ref, new_timers} = register_timer_atomically(state.timers, interrupt.id, duration)

    final_state = %{new_state | timers: new_timers}
    final_state = update_active_content_with_domain(final_state)

    broadcast_state_update(final_state)
    {:noreply, final_state}
  end

  @impl true
  def handle_cast({:remove_interrupt, interrupt_id}, state) do
    {timer_ref, new_timers} = Map.pop(state.timers, interrupt_id)

    if timer_ref do
      Process.cancel_timer(timer_ref)
    end

    new_state = StreamState.remove_interrupt(state, interrupt_id)
    new_state = %{new_state | timers: new_timers}
    new_state = update_active_content_with_domain(new_state)

    broadcast_state_update(new_state)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:update_ticker_content, content_list}, state) do
    new_state =
      %{state | ticker_rotation: content_list, ticker_index: 0}
      |> update_metadata()

    broadcast_state_update(new_state)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:force_content, content_type, data, duration}, state) do
    # Create high-priority override interrupt via async cast
    GenServer.cast(self(), {:add_interrupt, :manual_override, %{type: content_type, data: data}, [duration: duration]})
    {:noreply, state}
  end

  # Handle ticker rotation
  @impl true
  def handle_info(:ticker_tick, state) do
    new_state = advance_ticker(state)
    schedule_ticker_rotation()
    {:noreply, new_state}
  end

  # Handle periodic cleanup
  @impl true
  def handle_info(:cleanup, state) do
    Logger.debug("Running periodic cleanup")
    new_state = cleanup_stale_data(state)
    schedule_cleanup()
    {:noreply, new_state}
  end

  # Handle interrupt expiration
  @impl true
  def handle_info({:interrupt_expired, interrupt_id}, state) do
    Logger.debug("Interrupt expired", interrupt_id: interrupt_id)
    new_state = remove_interrupt_by_id(state, interrupt_id)

    # Enforce timer limits to prevent memory leaks
    new_state = enforce_timer_limits(new_state)

    broadcast_state_update(new_state)
    {:noreply, new_state}
  end

  # Handle chat events for real-time updates
  @impl true
  def handle_info({:chat_message, event}, state) do
    # If emote stats are currently active, send real-time updates
    if active_content_type(state) == :emote_stats do
      Phoenix.PubSub.broadcast(
        Server.PubSub,
        "stream:updates",
        {:content_update,
         %{
           type: :emote_increment,
           data: %{
             emotes: event.emotes,
             native_emotes: event.native_emotes,
             username: event.username
           },
           timestamp: event.timestamp
         }}
      )
    end

    {:noreply, state}
  end

  # Handle Twitch channel updates for show detection
  @impl true
  def handle_info({:channel_update, event}, state) do
    Logger.info("Channel update received",
      game: event.category_name,
      category_id: event.category_id
    )

    # Determine show from game
    new_show = determine_show_from_game(event.category_name, event.category_id)

    # Only change show if it's different
    if new_show != state.current_show do
      change_show(new_show, %{
        game: %{
          id: event.category_id,
          name: event.category_name
        },
        title: event.title
      })
    end

    {:noreply, state}
  end

  # Handle subscription events for sub trains
  @impl true
  def handle_info({:new_subscription, event}, state) do
    # Check if sub train is already active (and not expired)
    now = DateTime.utc_now()

    existing_sub_train =
      Enum.find(state.interrupt_stack, fn interrupt ->
        interrupt.type == :sub_train and
          Map.has_key?(state.timers, interrupt.id) and
          DateTime.diff(now, interrupt.started_at, :millisecond) < (interrupt.duration || sub_train_duration())
      end)

    if existing_sub_train do
      # Extend existing sub train
      new_state = extend_sub_train(state, existing_sub_train.id, event)
      broadcast_state_update(new_state)
      {:noreply, new_state}
    else
      sub_data = %{
        subscriber: Map.get(event, :user_name, "unknown"),
        tier: Map.get(event, :tier, "1000"),
        count: 1,
        total_months: Map.get(event, :cumulative_months, 0)
      }

      interrupt_id = generate_interrupt_id()
      options = [id: interrupt_id, duration: sub_train_duration()]

      new_state = StreamState.add_interrupt(state, :sub_train, sub_data, options)

      {_timer_ref, new_timers} = register_timer_atomically(state.timers, interrupt_id, sub_train_duration())

      final_state = %{new_state | timers: new_timers}
      final_state = update_active_content_with_domain(final_state)

      broadcast_state_update(final_state)
      {:noreply, final_state}
    end
  end

  ## Private Functions

  defp default_ticker_content(:ironmon) do
    [:ironmon_run_stats, :ironmon_deaths, :emote_stats, :recent_follows]
  end

  defp default_ticker_content(:variety) do
    [:emote_stats, :recent_follows, :stream_goals, :daily_stats]
  end

  defp default_ticker_content(:coding) do
    [:commit_stats, :build_status, :emote_stats, :recent_follows]
  end

  defp default_ticker_content(_), do: default_ticker_content(:variety)

  # Game ID to show mapping configuration
  defp game_to_show_mapping do
    Application.get_env(:server, :game_show_mapping, %{
      # Pokemon FireRed/LeafGreen for IronMON
      "490100" => :ironmon,
      # Software and Game Development
      "509658" => :coding,
      # Just Chatting
      "509660" => :variety
    })
  end

  defp determine_show_from_game(game_name, game_id) do
    Logger.debug("Determining show", game_name: game_name, game_id: game_id)

    # First try game ID mapping (most reliable)
    case Map.get(game_to_show_mapping(), game_id) do
      nil ->
        # Fall back to name-based detection for edge cases
        game_name_lower = String.downcase(game_name || "")

        cond do
          String.contains?(game_name_lower, "pokemon") and String.contains?(game_name_lower, "fire") -> :ironmon
          String.contains?(game_name_lower, "software") or String.contains?(game_name_lower, "development") -> :coding
          String.contains?(game_name_lower, "just chatting") -> :variety
          # Default fallback - use config value
          true -> Application.get_env(:server, :default_show, :variety)
        end

      show ->
        show
    end
  end

  defp generate_interrupt_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  defp register_timer_atomically(timers, interrupt_id, duration) do
    case Map.get(timers, interrupt_id) do
      nil ->
        # No existing timer, safe to add
        timer_ref = Process.send_after(self(), {:interrupt_expired, interrupt_id}, duration)
        {timer_ref, Map.put(timers, interrupt_id, timer_ref)}

      existing_timer ->
        # Timer already exists (likely duplicate ID), keep existing
        {existing_timer, timers}
    end
  end

  defp update_active_content_with_domain(state) do
    ticker_content =
      if Enum.empty?(state.ticker_rotation) do
        []
      else
        [Enum.at(state.ticker_rotation, state.ticker_index)]
      end

    active_content = StreamState.determine_active_content(state.interrupt_stack, ticker_content)

    final_active =
      case active_content do
        %{type: ticker_type}
        when ticker_type in [
               :emote_stats,
               :recent_follows,
               :daily_stats,
               :ironmon_run_stats,
               :commit_stats,
               :build_status,
               :stream_goals
             ] ->
          %{active_content | data: get_content_data(ticker_type)}

        other ->
          other
      end

    %{state | active_content: final_active}
  end

  defp advance_ticker(state) do
    if Enum.empty?(state.ticker_rotation) do
      state
    else
      new_index = rem(state.ticker_index + 1, length(state.ticker_rotation))

      new_state =
        %{state | ticker_index: new_index}
        |> update_metadata()

      # Only update if no interrupts are active
      if Enum.empty?(state.interrupt_stack) do
        new_state = update_active_content_with_domain(new_state)
        broadcast_state_update(new_state)
        new_state
      else
        new_state
      end
    end
  end

  defp remove_interrupt_by_id(state, interrupt_id) do
    new_stack = Enum.reject(state.interrupt_stack, &(&1.id == interrupt_id))
    new_timers = Map.delete(state.timers, interrupt_id)

    new_state =
      %{state | interrupt_stack: new_stack, timers: new_timers}
      |> update_metadata()

    update_active_content_with_domain(new_state)
  end

  defp extend_sub_train(state, sub_train_id, event) do
    # Cancel existing timer atomically
    {timer_ref, new_timers} = Map.pop(state.timers, sub_train_id)

    if timer_ref do
      Process.cancel_timer(timer_ref)
    end

    # Update sub train data
    new_stack =
      Enum.map(state.interrupt_stack, fn interrupt ->
        if interrupt.id == sub_train_id do
          new_count = (interrupt.data.count || 0) + 1

          %{
            interrupt
            | data:
                Map.merge(interrupt.data, %{
                  count: new_count,
                  latest_subscriber: Map.get(event, :user_name, "unknown"),
                  latest_tier: Map.get(event, :tier, "1000")
                })
          }
        else
          interrupt
        end
      end)

    # Set new timer using atomic registration
    {_new_timer_ref, final_timers} = register_timer_atomically(new_timers, sub_train_id, sub_train_duration())

    new_state = %{state | interrupt_stack: new_stack, timers: final_timers, version: state.version + 1}

    # Update active content to reflect the new count
    update_active_content_with_domain(new_state)
  end

  defp active_content_type(state) do
    case state.active_content do
      nil -> nil
      content -> content.type
    end
  end

  defp schedule_ticker_rotation do
    Process.send_after(self(), :ticker_tick, ticker_interval())
  end

  # Enhanced safe service call that uses centralized fallback system
  defp safe_service_call_with_fallback(service_fun, content_type) do
    try do
      service_fun.()
    rescue
      error ->
        Logger.warning("Service call failed, using centralized fallback",
          error: Exception.message(error),
          content_type: content_type,
          module: service_fun |> :erlang.fun_info(:module) |> elem(1)
        )

        Server.ContentFallbacks.get_fallback_content(content_type)
    catch
      :exit, reason ->
        Logger.warning("Service call exited, using centralized fallback",
          reason: inspect(reason),
          content_type: content_type
        )

        Server.ContentFallbacks.get_fallback_content(content_type)
    end
  end

  defp get_content_data(content_type) do
    case content_type do
      :emote_stats ->
        safe_service_call_with_fallback(
          fn -> Server.ContentAggregator.get_emote_stats() end,
          :emote_stats
        )

      :recent_follows ->
        safe_service_call_with_fallback(
          fn ->
            recent_followers = Server.ContentAggregator.get_recent_followers(5)
            %{recent_followers: recent_followers}
          end,
          :recent_follows
        )

      :daily_stats ->
        safe_service_call_with_fallback(
          fn -> Server.ContentAggregator.get_daily_stats() end,
          :daily_stats
        )

      :ironmon_run_stats ->
        # TODO: Get from IronMON service
        Server.ContentFallbacks.get_fallback_content(:ironmon_run_stats)

      :commit_stats ->
        # TODO: Get from git integration
        Server.ContentFallbacks.get_fallback_content(:commit_stats)

      :build_status ->
        # TODO: Get from CI integration
        Server.ContentFallbacks.get_fallback_content(:build_status)

      :stream_goals ->
        # TODO: Get from goals tracking
        Server.ContentFallbacks.get_fallback_content(:stream_goals)

      _ ->
        Server.ContentFallbacks.get_fallback_content(content_type)
    end
  end

  defp broadcast_state_update(state) do
    # Emit telemetry for state updates
    :telemetry.execute(
      [:server, :stream_producer, :state_update],
      %{
        interrupt_count: length(state.interrupt_stack),
        timer_count: map_size(state.timers),
        version: state.version
      },
      %{
        show: state.current_show,
        has_active_content: not is_nil(state.active_content)
      }
    )

    # Persist state whenever we broadcast it
    persist_state(state)
    Phoenix.PubSub.broadcast(Server.PubSub, "stream:updates", {:stream_update, state})
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, cleanup_interval())
  end

  defp cleanup_stale_data(state) do
    initial_timer_count = map_size(state.timers)
    initial_stack_size = length(state.interrupt_stack)

    # Clean up timers that might be stale (shouldn't happen with atomic operations, but safety net)
    active_interrupt_ids = MapSet.new(state.interrupt_stack, & &1.id)
    stale_timers = Map.drop(state.timers, MapSet.to_list(active_interrupt_ids))

    # Cancel stale timers
    Enum.each(stale_timers, fn {_id, timer_ref} ->
      Process.cancel_timer(timer_ref)
    end)

    new_timers = Map.take(state.timers, MapSet.to_list(active_interrupt_ids))

    # Limit interrupt stack size (should not be needed in normal operation)
    new_interrupt_stack =
      if not Enum.empty?(state.interrupt_stack) and length(state.interrupt_stack) > max_interrupt_stack_size() do
        # Keep only the highest priority interrupts
        state.interrupt_stack
        |> Enum.sort_by(& &1.priority, :desc)
        |> Enum.take(interrupt_stack_keep_count())
      else
        state.interrupt_stack
      end

    # Log and emit telemetry for cleanup if anything was cleaned
    if map_size(stale_timers) > 0 or length(state.interrupt_stack) != length(new_interrupt_stack) do
      Logger.info("Cleanup completed",
        timers_before: initial_timer_count,
        timers_after: map_size(new_timers),
        stale_timers_removed: map_size(stale_timers),
        stack_before: initial_stack_size,
        stack_after: length(new_interrupt_stack)
      )

      # Emit cleanup telemetry
      :telemetry.execute(
        [:server, :stream_producer, :cleanup],
        %{
          stale_timers_removed: map_size(stale_timers),
          interrupts_pruned: initial_stack_size - length(new_interrupt_stack)
        },
        %{
          timer_count_before: initial_timer_count,
          timer_count_after: map_size(new_timers)
        }
      )
    end

    new_state = %{state | timers: new_timers, interrupt_stack: new_interrupt_stack, version: state.version + 1}

    # Persist the cleaned state
    persist_state(new_state)
    new_state
  end

  defp enforce_timer_limits(state) do
    timer_count = map_size(state.timers)

    if timer_count > max_timers() do
      Logger.warning("Timer limit exceeded, cleaning up oldest timers",
        current_count: timer_count,
        max_allowed: max_timers()
      )

      # Emit telemetry for timer limit breach
      :telemetry.execute(
        [:server, :stream_producer, :timer_limit_exceeded],
        %{
          current_count: timer_count,
          max_allowed: max_timers(),
          excess_count: timer_count - max_timers()
        },
        %{}
      )

      # Get oldest interrupts by started_at time
      oldest_interrupts =
        state.interrupt_stack
        |> Enum.sort_by(& &1.started_at, DateTime)
        |> Enum.take(timer_count - max_timers())

      # Cancel timers for oldest interrupts
      Enum.each(oldest_interrupts, fn interrupt ->
        if timer_ref = Map.get(state.timers, interrupt.id) do
          Process.cancel_timer(timer_ref)
        end
      end)

      # Remove oldest interrupts from state
      oldest_ids = MapSet.new(oldest_interrupts, & &1.id)
      new_interrupt_stack = Enum.reject(state.interrupt_stack, &MapSet.member?(oldest_ids, &1.id))
      new_timers = Map.drop(state.timers, MapSet.to_list(oldest_ids))

      new_state = %{state | interrupt_stack: new_interrupt_stack, timers: new_timers, version: state.version + 1}
      update_active_content_with_domain(new_state)
    else
      state
    end
  end

  # Metadata management

  defp update_metadata(state) do
    state = ensure_metadata(state)
    new_version = state.version + 1
    %{state | version: new_version, metadata: %{last_updated: DateTime.utc_now(), state_version: new_version}}
  end

  # Safely ensure metadata exists (for backward compatibility)
  defp ensure_metadata(state) do
    case Map.get(state, :metadata) do
      nil -> %{state | metadata: %{last_updated: DateTime.utc_now(), state_version: state.version}}
      _ -> state
    end
  end

  # State persistence functions

  defp persist_state(state) do
    # Only persist essential state, not timers (they'll be recreated)
    persisted_state = %{state | timers: %{}}
    :ets.insert(@state_persistence_table, {:current_state, persisted_state})
  end

  defp restore_state do
    try do
      case :ets.lookup(@state_persistence_table, :current_state) do
        [{:current_state, state}] when is_map(state) ->
          # Validate state has required fields
          if Map.has_key?(state, :current_show) and Map.has_key?(state, :version) do
            state
          else
            Logger.warning("Persisted state missing required fields, starting fresh")
            nil
          end

        [] ->
          nil

        invalid ->
          Logger.warning("Invalid persisted state format", data: inspect(invalid))
          nil
      end
    rescue
      error ->
        Logger.error("Failed to restore state",
          error: Exception.message(error),
          type: error.__struct__
        )

        nil
    end
  end

  defp restore_interrupt_timers(state) do
    # Recreate timers for active interrupts
    new_timers =
      Enum.reduce(state.interrupt_stack, %{}, fn interrupt, acc ->
        # Validate interrupt has required fields
        case interrupt do
          %{started_at: started_at, id: id} when not is_nil(started_at) ->
            # Calculate remaining time for interrupt (handle clock skew)
            elapsed = DateTime.diff(DateTime.utc_now(), started_at, :millisecond)
            total_duration = interrupt.duration || sub_train_duration()

            remaining =
              cond do
                elapsed < 0 ->
                  # Clock skew - use full duration
                  Logger.warning("Clock skew detected for interrupt", id: id)
                  total_duration

                elapsed >= total_duration ->
                  # Already expired
                  0

                true ->
                  # Normal case - at least 1 second remaining
                  max(1000, total_duration - elapsed)
              end

            if remaining > 0 do
              timer_ref = Process.send_after(self(), {:interrupt_expired, id}, remaining)
              Map.put(acc, id, timer_ref)
            else
              Logger.debug("Interrupt expired during restoration", id: id)
              acc
            end

          invalid_interrupt ->
            Logger.warning("Invalid interrupt found during restoration", interrupt: inspect(invalid_interrupt))
            acc
        end
      end)

    # Filter out expired interrupts
    active_interrupts =
      Enum.filter(state.interrupt_stack, fn interrupt ->
        Map.has_key?(new_timers, interrupt.id)
      end)

    %{state | timers: new_timers, interrupt_stack: active_interrupts}
  end
end
