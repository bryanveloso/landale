defmodule Server.StreamProducer do
  @moduledoc """
  Central state machine for stream overlay coordination with 4-layer architecture.

  ## Layer Architecture
  - **base**: Persistent latest event display (latest_event from database)
  - **ticker**: Rotating content based on current show context
  - **timeline**: Event sequence display (midground layer)
  - **alerts**: High-priority interrupts (foreground layer)

  ## Priority System
  - Alerts (priority 100) - breaking news style interrupts
  - Sub trains (priority 50) - subscription celebration timers
  - Ticker content (priority 10) - rotating stats and metrics

  ## Show Contexts
  Coordinates with show contexts (IronMON, variety, coding) to determine
  appropriate content types and theming. The base layer always shows
  the latest event regardless of show context.

  ## State Management
  - `current`: Currently active content from alerts or ticker
  - `base`: Latest event for persistent background display
  - `alerts`: Priority interrupt stack (renamed from interrupt_stack)
  - `ticker`: Rotating content list (renamed from ticker_rotation)
  """

  use GenServer
  require Logger

  # Priority levels
  @priority_alert 100
  @priority_sub_train 50
  @priority_ticker 10

  # Default timing configuration - can be overridden via Application config
  defp ticker_interval, do: Application.get_env(:server, :ticker_interval, 15_000)
  defp sub_train_duration, do: Application.get_env(:server, :sub_train_duration, 300_000)
  defp cleanup_interval, do: Application.get_env(:server, :cleanup_interval, 600_000)
  defp max_timers, do: Application.get_env(:server, :max_timers, 100)

  # Alert and manual override durations
  defp alert_duration, do: Application.get_env(:server, :alert_duration, 10_000)
  defp manual_override_duration, do: Application.get_env(:server, :manual_override_duration, 30_000)

  # Cleanup configuration
  @cleanup_config Application.compile_env(:server, :cleanup_settings, %{
                    max_alerts_size: 50,
                    alerts_keep_count: 25
                  })

  defp max_alerts_size, do: Map.get(@cleanup_config, :max_alerts_size, 50)
  defp alerts_keep_count, do: Map.get(@cleanup_config, :alerts_keep_count, 25)
  @state_persistence_table :stream_producer_state

  defstruct current_show: :variety,
            base: nil,
            alerts: [],
            ticker: [],
            timeline: [],
            ticker_idx: 0,
            timers: %{},
            version: 0,
            metadata: %{last_updated: nil, state_version: 0}

  ## Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Get current stream state"
  @spec get_current_state() :: map()
  def get_current_state do
    GenServer.call(__MODULE__, :get_state)
  end

  @doc "Change the current show context"
  @spec change_show(atom(), map()) :: :ok
  def change_show(show, metadata \\ %{}) do
    GenServer.cast(__MODULE__, {:change_show, show, metadata})
  end

  @doc "Add a priority interrupt (alert, sub train, etc.)"
  @spec add_interrupt(atom(), map(), keyword()) :: :ok
  def add_interrupt(type, data, opts \\ []) do
    GenServer.cast(__MODULE__, {:add_interrupt, type, data, opts})
  end

  @doc "Remove an interrupt by ID"
  @spec remove_interrupt(String.t()) :: :ok
  def remove_interrupt(interrupt_id) do
    GenServer.cast(__MODULE__, {:remove_interrupt, interrupt_id})
  end

  @doc "Update ticker content for current show"
  @spec update_ticker_content([map()]) :: :ok
  def update_ticker_content(content_list) do
    GenServer.cast(__MODULE__, {:update_ticker_content, content_list})
  end

  @doc "Force display specific content (manual override)"
  @spec force_content(atom(), map(), pos_integer()) :: :ok
  def force_content(content_type, data, duration \\ 30_000) do
    GenServer.cast(__MODULE__, {:force_content, content_type, data, duration})
  end

  ## GenServer Implementation

  @impl true
  def init(_opts) do
    Logger.info("StreamProducer started", service: :stream_producer)

    # Subscribe to event stream
    Phoenix.PubSub.subscribe(Server.PubSub, "events")

    # Create persistence table (protected to prevent unauthorized writes)
    # Handle race condition in tests gracefully
    try do
      :ets.new(@state_persistence_table, [:named_table, :set, :protected])
    catch
      :error, {:badarg, _} ->
        # Table already exists, which is fine
        @state_persistence_table
    end

    # Try to restore previous state
    state =
      case restore_state(@state_persistence_table) do
        nil ->
          Logger.info("Starting with fresh state")

          %__MODULE__{
            current_show: :variety,
            ticker: default_ticker_content(:variety),
            base: get_initial_base(),
            metadata: %{last_updated: DateTime.utc_now(), state_version: 0}
          }

        restored_state ->
          Logger.info("Restored previous state",
            show: restored_state.current_show,
            version: restored_state.version,
            interrupts: length(restored_state.alerts)
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

  def handle_call({:remove_interrupt, id}, _from, state) do
    # Remove the interrupt from the stack
    new_stack = Enum.reject(state.alerts, fn item -> item.id == id end)
    new_state = %{state | alerts: new_stack} |> update_metadata()

    # Process interrupt removal through unified event system
    Server.Events.process_event("stream.interrupt_removed", %{
      interrupt_id: id,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    })

    persist_state(new_state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_cast({:change_show, show, metadata}, state) do
    Logger.info("Show changed", show: show, metadata: metadata)

    new_state =
      %{
        state
        | current_show: show,
          ticker: default_ticker_content(show),
          ticker_idx: 0
      }
      |> update_metadata()

    # Process show change through unified event system
    Server.Events.process_event("stream.show_changed", %{
      show: Atom.to_string(show),
      game_id: get_in(metadata, [:game, :id]),
      game_name: get_in(metadata, [:game, :name]),
      title: metadata[:title],
      changed_at: DateTime.utc_now() |> DateTime.to_iso8601()
    })

    broadcast_state_update(new_state)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:add_interrupt, type, data, opts}, state) do
    priority = get_priority_for_type(type)
    duration = Keyword.get(opts, :duration, get_default_duration(type))
    interrupt_id = Keyword.get(opts, :id, generate_interrupt_id())

    interrupt = %{
      id: interrupt_id,
      type: type,
      priority: priority,
      duration: duration,
      started_at: DateTime.utc_now(),
      data: data
    }

    # Add to alerts and sort by priority
    new_alerts =
      [interrupt | state.alerts]
      |> Enum.sort_by(& &1.priority, :desc)

    # Set timer for interrupt expiration using atomic registration
    {_timer_ref, new_timers} = register_timer_atomically(state.timers, interrupt_id, duration)

    new_state =
      %{state | alerts: new_alerts, timers: new_timers}
      |> update_metadata()

    # Update current content if this alert has higher priority
    new_state = update_base(new_state)

    broadcast_state_update(new_state)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:remove_interrupt, interrupt_id}, state) do
    # Cancel timer atomically if exists
    {timer_ref, new_timers} = Map.pop(state.timers, interrupt_id)

    if timer_ref do
      Process.cancel_timer(timer_ref)
    end

    new_alerts = Enum.reject(state.alerts, &(&1.id == interrupt_id))

    new_state =
      %{state | alerts: new_alerts, timers: new_timers}
      |> update_metadata()

    # Update current content after removal
    new_state = update_base(new_state)

    broadcast_state_update(new_state)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:update_ticker_content, content_list}, state) do
    new_state =
      %{state | ticker: content_list, ticker_idx: 0}
      |> update_metadata()

    broadcast_state_update(new_state)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:force_content, content_type, data, duration}, state) do
    # Create high-priority override interrupt via async cast
    # Merge content_type into data without overwriting existing fields
    merged_data = Map.merge(%{type: content_type}, data)
    GenServer.cast(self(), {:add_interrupt, :manual_override, merged_data, [duration: duration]})
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

  # Handle events
  @impl true
  def handle_info({:twitch_event, %{type: "channel.chat.message", data: data, timestamp: timestamp}}, state) do
    # If emote stats are currently active, send real-time updates through unified event system
    if current_content_type(state) == :emote_stats do
      Server.Events.process_event("stream.emote_increment", %{
        emotes: Map.get(data, :emotes, []),
        native_emotes: Map.get(data, :native_emotes, []),
        user_name: Map.get(data, :user_name, "unknown"),
        timestamp: if(is_binary(timestamp), do: timestamp, else: DateTime.to_iso8601(timestamp))
      })
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:twitch_event, %{type: "channel.update", data: data}}, state) do
    Logger.info("Channel update received",
      game: Map.get(data, :category_name),
      category_id: Map.get(data, :category_id)
    )

    # Determine show from game
    new_show = determine_show_from_game(Map.get(data, :category_name), Map.get(data, :category_id))

    # Only change show if it's different
    if new_show != state.current_show do
      change_show(new_show, %{
        game: %{
          id: Map.get(data, :category_id),
          name: Map.get(data, :category_name)
        },
        title: Map.get(data, :title)
      })
    end

    {:noreply, state}
  end

  # Handle IronMON events
  @impl true
  def handle_info({:new_run, %{seed_id: seed_id, challenge_id: _challenge_id}}, state) do
    Logger.info("New IronMON run started", seed_id: seed_id)

    # Force refresh of IronMON content if currently showing
    if state.current_show == :ironmon and current_content_type(state) in [:ironmon_run_stats, :ironmon_progression] do
      new_state = update_base(state)
      broadcast_state_update(new_state)
      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:checkpoint_result, %{checkpoint: checkpoint_name, passed: true} = event}, state) do
    Logger.info("IronMON checkpoint cleared", checkpoint: checkpoint_name)

    # Create a brief alert for checkpoint clear
    if state.current_show == :ironmon do
      add_interrupt(
        :alert,
        %{
          type: :checkpoint_clear,
          checkpoint_name: checkpoint_name,
          seed_id: event[:seed_id]
        },
        duration: 5_000
      )
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:checkpoint_result, %{passed: false}}, state) do
    # Don't alert on failures, just track them
    {:noreply, state}
  end

  @impl true
  def handle_info({:twitch_event, %{type: "channel.subscribe", data: data, timestamp: timestamp}}, state) do
    # Check if sub train is already active (and not expired)
    now = DateTime.utc_now()

    existing_sub_train =
      Enum.find(state.alerts, fn interrupt ->
        interrupt.type == :sub_train and
          Map.has_key?(state.timers, interrupt.id) and
          DateTime.diff(now, interrupt.started_at, :millisecond) < (interrupt.duration || sub_train_duration())
      end)

    if existing_sub_train do
      # Extend existing sub train
      new_state = extend_sub_train(state, existing_sub_train.id, data, timestamp)
      broadcast_state_update(new_state)
      {:noreply, new_state}
    else
      # Start new sub train synchronously
      priority = get_priority_for_type(:sub_train)
      duration = sub_train_duration()
      interrupt_id = generate_interrupt_id()

      interrupt = %{
        id: interrupt_id,
        type: :sub_train,
        priority: priority,
        duration: duration,
        started_at: DateTime.utc_now(),
        data: %{
          subscriber: Map.get(data, :user_name, "unknown"),
          tier: Map.get(data, :tier, "1000"),
          latest_subscriber: Map.get(data, :user_name, "unknown"),
          latest_tier: Map.get(data, :tier, "1000"),
          count: 1,
          total_months: Map.get(data, :cumulative_months, 0)
        }
      }

      # Add to interrupt stack and sort by priority
      new_stack =
        [interrupt | state.alerts]
        |> Enum.sort_by(& &1.priority, :desc)

      # Set timer for interrupt expiration using atomic registration
      {_timer_ref, new_timers} = register_timer_atomically(state.timers, interrupt_id, duration)

      new_state =
        %{state | alerts: new_stack, timers: new_timers}
        |> update_metadata()

      # Update active content if this interrupt has higher priority
      new_state = update_base(new_state)

      broadcast_state_update(new_state)
      {:noreply, new_state}
    end
  end

  # Handle event messages from PubSub
  @impl true
  def handle_info({:event, event_data}, state) do
    Logger.debug("StreamProducer received event", event_type: event_data.type)

    # Ignore our own stream.state_updated events to prevent infinite loop
    if event_data.type == "stream.state_updated" do
      {:noreply, state}
    else
      # Update base with latest event reactively
      new_base = get_latest_event()
      new_state = %{state | base: new_base} |> update_metadata()

      broadcast_state_update(new_state)
      {:noreply, new_state}
    end
  end

  # Catch-all for unhandled messages
  @impl true
  def handle_info(unhandled_msg, state) do
    Logger.debug("Unhandled message in StreamProducer",
      message: inspect(unhandled_msg, limit: 50)
    )

    {:noreply, state}
  end

  ## Private Functions

  defp default_ticker_content(:ironmon) do
    [:ironmon_run_stats, :ironmon_progression]
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

  defp get_priority_for_type(:alert), do: @priority_alert
  defp get_priority_for_type(:sub_train), do: @priority_sub_train
  defp get_priority_for_type(:manual_override), do: @priority_alert
  defp get_priority_for_type(_), do: @priority_ticker

  defp get_default_duration(:alert), do: alert_duration()
  defp get_default_duration(:sub_train), do: sub_train_duration()
  defp get_default_duration(:manual_override), do: manual_override_duration()
  defp get_default_duration(_), do: ticker_interval()

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

  defp update_base(state) do
    new_base =
      if Enum.empty?(state.ticker) do
        nil
      else
        ticker_content = Enum.at(state.ticker, state.ticker_idx)

        content_data = get_content_data(ticker_content)

        Map.merge(content_data, %{
          type: ticker_content,
          priority: @priority_ticker,
          started_at: DateTime.utc_now()
        })
      end

    %{state | base: new_base}
  end

  defp advance_ticker(state) do
    if Enum.empty?(state.ticker) do
      state
    else
      new_index = rem(state.ticker_idx + 1, length(state.ticker))

      new_state =
        %{state | ticker_idx: new_index}
        |> update_metadata()

      # Only update if no alerts are active
      if Enum.empty?(state.alerts) do
        new_state = update_base(new_state)
        broadcast_state_update(new_state)
        new_state
      else
        new_state
      end
    end
  end

  defp remove_interrupt_by_id(state, interrupt_id) do
    new_stack = Enum.reject(state.alerts, &(&1.id == interrupt_id))
    new_timers = Map.delete(state.timers, interrupt_id)

    new_state =
      %{state | alerts: new_stack, timers: new_timers}
      |> update_metadata()

    update_base(new_state)
  end

  defp extend_sub_train(state, sub_train_id, event_data, _timestamp) do
    # Cancel existing timer atomically
    {timer_ref, new_timers} = Map.pop(state.timers, sub_train_id)

    if timer_ref do
      Process.cancel_timer(timer_ref)
    end

    # Update sub train data
    new_stack =
      Enum.map(state.alerts, fn interrupt ->
        if interrupt.id == sub_train_id do
          current_data = interrupt.data || %{}
          new_count = (Map.get(current_data, :count) || 0) + 1

          %{
            interrupt
            | data: %{
                current_data
                | count: new_count,
                  latest_subscriber: Map.get(event_data, :user_name, "unknown"),
                  latest_tier: Map.get(event_data, :tier, "1000")
              }
          }
        else
          interrupt
        end
      end)

    # Set new timer using atomic registration
    {_new_timer_ref, final_timers} = register_timer_atomically(new_timers, sub_train_id, sub_train_duration())

    new_state = %{state | alerts: new_stack, timers: final_timers, version: state.version + 1}

    # Update active content to reflect the new count
    update_base(new_state)
  end

  defp current_content_type(state) do
    case state.base do
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
      :emote_stats -> get_emote_stats()
      :recent_follows -> get_recent_follows()
      :daily_stats -> get_daily_stats()
      :ironmon_run_stats -> get_ironmon_run_stats()
      :ironmon_progression -> get_ironmon_progression()
      :stream_goals -> get_stream_goals()
      :latest_event -> get_latest_event()
      :latest_events -> get_latest_events()
      _ -> Server.ContentFallbacks.get_fallback_content(content_type)
    end
  end

  defp get_emote_stats do
    safe_service_call_with_fallback(
      fn -> Server.ContentAggregator.get_emote_stats() end,
      :emote_stats
    )
  end

  defp get_recent_follows do
    safe_service_call_with_fallback(
      fn ->
        recent_followers = Server.ContentAggregator.get_recent_followers(5)
        %{recent_followers: recent_followers}
      end,
      :recent_follows
    )
  end

  defp get_daily_stats do
    safe_service_call_with_fallback(
      fn -> Server.ContentAggregator.get_daily_stats() end,
      :daily_stats
    )
  end

  defp get_stream_goals do
    safe_service_call_with_fallback(
      fn -> Server.ContentAggregator.get_stream_goals() end,
      :stream_goals
    )
  end

  defp get_latest_event do
    safe_service_call_with_fallback(
      fn ->
        case Server.ContentAggregator.get_latest_event() do
          nil ->
            nil

          event ->
            Map.merge(event, %{
              priority: 10,
              layer: "background",
              started_at: DateTime.utc_now() |> DateTime.to_iso8601()
            })
        end
      end,
      :latest_event
    )
  end

  defp get_latest_events do
    safe_service_call_with_fallback(
      fn ->
        events = Server.ContentAggregator.get_latest_events(20)
        %{events: events}
      end,
      :latest_events
    )
  end

  defp get_initial_base do
    get_latest_event()
  end

  defp get_ironmon_run_stats do
    safe_service_call_with_fallback(
      fn ->
        case Server.Ironmon.get_current_seed() do
          nil -> get_no_active_run_stats()
          current_seed -> get_active_run_stats(current_seed)
        end
      end,
      :ironmon_run_stats
    )
  end

  defp get_no_active_run_stats do
    %{
      run_number: nil,
      checkpoints_cleared: 0,
      current_checkpoint: "No active run",
      clear_rate: 0.0,
      message: "Start a new IronMON run!"
    }
  end

  defp get_active_run_stats(current_seed) do
    stats = Server.Ironmon.get_run_statistics(current_seed.id)
    checkpoint_progress = Server.Ironmon.get_current_checkpoint_progress()

    %{
      run_number: current_seed.id,
      checkpoints_cleared: stats.checkpoints_cleared,
      total_checkpoints: stats.total_checkpoints,
      progress_percentage: stats.progress_percentage,
      current_checkpoint: checkpoint_progress[:current_checkpoint] || "Unknown",
      trainer: checkpoint_progress[:trainer],
      clear_rate: Float.round((checkpoint_progress[:clear_rate] || 0.0) * 100, 1)
    }
  end

  defp get_ironmon_progression do
    safe_service_call_with_fallback(
      fn ->
        case Server.Ironmon.get_current_checkpoint_progress() do
          nil -> get_no_active_progression()
          checkpoint_progress -> get_active_progression(checkpoint_progress)
        end
      end,
      :ironmon_progression
    )
  end

  defp get_no_active_progression do
    %{
      has_active_run: false,
      message: "No active IronMON run"
    }
  end

  defp get_active_progression(checkpoint_progress) do
    recent_clears = Server.Ironmon.get_recent_checkpoint_clears(100)

    last_clear =
      Enum.find(recent_clears, fn clear ->
        clear.checkpoint_name == checkpoint_progress.current_checkpoint
      end)

    %{
      has_active_run: true,
      current_checkpoint: checkpoint_progress.current_checkpoint,
      trainer: checkpoint_progress.trainer,
      clear_rate: checkpoint_progress.clear_rate,
      clear_rate_percentage: Float.round(checkpoint_progress.clear_rate * 100, 1),
      last_cleared_seed: last_clear && last_clear.seed_id,
      attempts_on_record: checkpoint_progress.attempts,
      checkpoints_cleared: checkpoint_progress.checkpoints_cleared,
      total_checkpoints: checkpoint_progress.total_checkpoints
    }
  end

  defp enrich_state_with_layers(state) do
    # Enrich base content with layer
    enriched_base =
      if state.base do
        content_type = to_string(state.base.type)
        Map.put(state.base, :layer, Server.LayerMapping.get_layer(content_type, Atom.to_string(state.current_show)))
      else
        nil
      end

    # Enrich alerts with layers
    enriched_alerts =
      Enum.map(state.alerts, fn alert ->
        content_type = to_string(alert.type)
        Map.put(alert, :layer, Server.LayerMapping.get_layer(content_type, Atom.to_string(state.current_show)))
      end)

    # Enrich timeline with layers
    enriched_timeline =
      Enum.map(state.timeline, fn event ->
        content_type = to_string(event.type)
        Map.put(event, :layer, Server.LayerMapping.get_layer(content_type, Atom.to_string(state.current_show)))
      end)

    # Enrich ticker rotation with layers
    enriched_ticker =
      Enum.map(state.ticker, fn ticker_type ->
        cond do
          is_binary(ticker_type) ->
            %{
              type: ticker_type,
              layer: Server.LayerMapping.get_layer(ticker_type, Atom.to_string(state.current_show))
            }

          is_atom(ticker_type) ->
            ticker_type_string = to_string(ticker_type)

            %{
              type: ticker_type_string,
              layer: Server.LayerMapping.get_layer(ticker_type_string, Atom.to_string(state.current_show))
            }

          true ->
            ticker_type
        end
      end)

    %{
      state
      | base: enriched_base,
        alerts: enriched_alerts,
        timeline: enriched_timeline,
        ticker: enriched_ticker
    }
  end

  defp broadcast_state_update(state) do
    # Enrich state with layer information before broadcasting
    enriched_state = enrich_state_with_layers(state)

    # Persist state whenever we broadcast it
    persist_state(state)

    # Process stream state update through unified event system
    Server.Events.process_event("stream.state_updated", %{
      current_show: Atom.to_string(enriched_state.current_show),
      base: enriched_state.base,
      alerts: enriched_state.alerts,
      timeline: enriched_state.timeline,
      ticker:
        Enum.map(enriched_state.ticker, fn
          %{type: type} when is_binary(type) -> type
          ticker when is_atom(ticker) -> Atom.to_string(ticker)
          ticker when is_binary(ticker) -> ticker
          # Fallback for any other cases
          ticker -> to_string(ticker)
        end),
      version: enriched_state.version,
      metadata: enriched_state.metadata
    })
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, cleanup_interval())
  end

  defp cleanup_stale_data(state) do
    initial_timer_count = map_size(state.timers)
    initial_alerts_size = length(state.alerts)

    # Clean up timers that might be stale (shouldn't happen with atomic operations, but safety net)
    active_interrupt_ids = MapSet.new(state.alerts, & &1.id)
    stale_timers = Map.drop(state.timers, MapSet.to_list(active_interrupt_ids))

    # Cancel stale timers
    Enum.each(stale_timers, fn {_id, timer_ref} ->
      Process.cancel_timer(timer_ref)
    end)

    new_timers = Map.take(state.timers, MapSet.to_list(active_interrupt_ids))

    # Limit alerts size (should not be needed in normal operation)
    new_alerts =
      if not Enum.empty?(state.alerts) and length(state.alerts) > max_alerts_size() do
        # Keep only the highest priority interrupts
        state.alerts
        |> Enum.sort_by(& &1.priority, :desc)
        |> Enum.take(alerts_keep_count())
      else
        state.alerts
      end

    # Log and emit telemetry for cleanup if anything was cleaned
    if map_size(stale_timers) > 0 or length(state.alerts) != length(new_alerts) do
      Logger.info("Cleanup completed",
        timers_before: initial_timer_count,
        timers_after: map_size(new_timers),
        stale_timers_removed: map_size(stale_timers),
        alerts_before: initial_alerts_size,
        alerts_after: length(new_alerts)
      )
    end

    new_state = %{state | timers: new_timers, alerts: new_alerts, version: state.version + 1}

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

      # Get oldest interrupts by started_at time
      oldest_interrupts =
        state.alerts
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
      new_alerts = Enum.reject(state.alerts, &MapSet.member?(oldest_ids, &1.id))
      new_timers = Map.drop(state.timers, MapSet.to_list(oldest_ids))

      new_state = %{state | alerts: new_alerts, timers: new_timers, version: state.version + 1}
      update_base(new_state)
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

  defp restore_state(table_name) do
    try do
      case :ets.lookup(table_name, :current_state) do
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
      Enum.reduce(state.alerts, %{}, fn interrupt, acc ->
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
      Enum.filter(state.alerts, fn interrupt ->
        Map.has_key?(new_timers, interrupt.id)
      end)

    %{state | timers: new_timers, alerts: active_interrupts}
  end
end
