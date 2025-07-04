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

  # Priority levels
  @priority_alert 100
  @priority_sub_train 50  
  @priority_ticker 10

  # Default ticker rotation intervals (milliseconds)
  @ticker_interval 15_000
  @sub_train_duration 300_000  # 5 minutes

  defstruct [
    current_show: :variety,
    active_content: nil,
    interrupt_stack: [],
    ticker_rotation: [],
    ticker_index: 0,
    timers: %{},
    version: 0
  ]

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

    state = %__MODULE__{
      current_show: :variety,
      ticker_rotation: default_ticker_content(:variety)
    }

    # Start ticker rotation
    schedule_ticker_rotation()

    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_cast({:change_show, show, metadata}, state) do
    Logger.info("Show changed", show: show, metadata: metadata)
    
    new_state = %{state | 
      current_show: show,
      ticker_rotation: default_ticker_content(show),
      ticker_index: 0,
      version: state.version + 1
    }

    # Broadcast show change
    Phoenix.PubSub.broadcast(Server.PubSub, "stream:updates", {:show_change, %{
      show: show,
      game: metadata[:game],
      changed_at: DateTime.utc_now()
    }})

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
      data: data,
      duration: duration,
      started_at: DateTime.utc_now()
    }

    # Add to interrupt stack and sort by priority
    new_stack = [interrupt | state.interrupt_stack]
                |> Enum.sort_by(& &1.priority, :desc)

    # Set timer for interrupt expiration
    timer_ref = Process.send_after(self(), {:interrupt_expired, interrupt_id}, duration)
    new_timers = Map.put(state.timers, interrupt_id, timer_ref)

    new_state = %{state |
      interrupt_stack: new_stack,
      timers: new_timers,
      version: state.version + 1
    }

    # Update active content if this interrupt has higher priority
    new_state = update_active_content(new_state)

    broadcast_state_update(new_state)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:remove_interrupt, interrupt_id}, state) do
    # Cancel timer if exists
    if timer_ref = state.timers[interrupt_id] do
      Process.cancel_timer(timer_ref)
    end

    new_stack = Enum.reject(state.interrupt_stack, &(&1.id == interrupt_id))
    new_timers = Map.delete(state.timers, interrupt_id)

    new_state = %{state |
      interrupt_stack: new_stack,
      timers: new_timers,
      version: state.version + 1
    }

    # Update active content after removal
    new_state = update_active_content(new_state)

    broadcast_state_update(new_state)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:update_ticker_content, content_list}, state) do
    new_state = %{state |
      ticker_rotation: content_list,
      ticker_index: 0,
      version: state.version + 1
    }

    broadcast_state_update(new_state)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:force_content, content_type, data, duration}, state) do
    # Create high-priority override interrupt
    add_interrupt(:manual_override, %{type: content_type, data: data}, [duration: duration])
    {:noreply, state}
  end

  # Handle ticker rotation
  @impl true
  def handle_info(:ticker_tick, state) do
    new_state = advance_ticker(state)
    schedule_ticker_rotation()
    {:noreply, new_state}
  end

  # Handle interrupt expiration
  @impl true
  def handle_info({:interrupt_expired, interrupt_id}, state) do
    Logger.debug("Interrupt expired", interrupt_id: interrupt_id)
    new_state = remove_interrupt_by_id(state, interrupt_id)
    broadcast_state_update(new_state)
    {:noreply, new_state}
  end

  # Handle chat events for real-time updates
  @impl true
  def handle_info({:chat_message, event}, state) do
    # If emote stats are currently active, send real-time updates
    if active_content_type(state) == :emote_stats do
      Phoenix.PubSub.broadcast(Server.PubSub, "stream:updates", {:content_update, %{
        type: :emote_increment,
        data: %{
          emotes: event.emotes,
          native_emotes: event.native_emotes,
          username: event.username
        },
        timestamp: event.timestamp
      }})
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
    # Check if sub train is already active
    existing_sub_train = Enum.find(state.interrupt_stack, &(&1.type == :sub_train))
    
    if existing_sub_train do
      # Extend existing sub train
      new_state = extend_sub_train(state, existing_sub_train.id, event)
      broadcast_state_update(new_state)
      {:noreply, new_state}
    else
      # Start new sub train
      add_interrupt(:sub_train, %{
        subscriber: event.username,
        tier: event.tier,
        count: 1,
        total_months: event.cumulative_months
      }, [duration: @sub_train_duration])
      {:noreply, state}
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

  # Game ID to show mapping (using Twitch game IDs)
  @game_to_show_mapping %{
    # Pokemon FireRed/LeafGreen for IronMON
    "490100" => :ironmon,
    # Software and Game Development
    "509658" => :coding,
    # Just Chatting
    "509660" => :variety
  }

  defp determine_show_from_game(game_name, game_id) do
    Logger.debug("Determining show", game_name: game_name, game_id: game_id)
    
    # First try game ID mapping (most reliable)
    case Map.get(@game_to_show_mapping, game_id) do
      nil ->
        # Fall back to name-based detection for edge cases
        case String.downcase(game_name || "") do
          name when name =~ "pokemon" and name =~ "fire" -> :ironmon
          name when name =~ "software" or name =~ "development" -> :coding
          name when name =~ "just chatting" -> :variety
          _ -> :variety  # Default fallback
        end
      
      show -> show
    end
  end

  defp get_priority_for_type(:alert), do: @priority_alert
  defp get_priority_for_type(:sub_train), do: @priority_sub_train
  defp get_priority_for_type(:manual_override), do: @priority_alert
  defp get_priority_for_type(_), do: @priority_ticker

  defp get_default_duration(:alert), do: 10_000  # 10 seconds
  defp get_default_duration(:sub_train), do: @sub_train_duration
  defp get_default_duration(:manual_override), do: 30_000  # 30 seconds
  defp get_default_duration(_), do: @ticker_interval

  defp generate_interrupt_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  defp update_active_content(state) do
    new_active = cond do
      # Highest priority interrupt wins
      length(state.interrupt_stack) > 0 ->
        List.first(state.interrupt_stack)
      
      # Fall back to ticker content
      length(state.ticker_rotation) > 0 ->
        ticker_content = Enum.at(state.ticker_rotation, state.ticker_index)
        %{
          type: ticker_content,
          priority: @priority_ticker,
          data: get_content_data(ticker_content),
          started_at: DateTime.utc_now()
        }
      
      # Nothing to show
      true -> nil
    end

    %{state | active_content: new_active}
  end

  defp advance_ticker(state) do
    return state if length(state.ticker_rotation) == 0
    
    new_index = rem(state.ticker_index + 1, length(state.ticker_rotation))
    new_state = %{state | 
      ticker_index: new_index,
      version: state.version + 1
    }
    
    # Only update if no interrupts are active
    if length(state.interrupt_stack) == 0 do
      new_state = update_active_content(new_state)
      broadcast_state_update(new_state)
      new_state
    else
      new_state
    end
  end

  defp remove_interrupt_by_id(state, interrupt_id) do
    new_stack = Enum.reject(state.interrupt_stack, &(&1.id == interrupt_id))
    new_timers = Map.delete(state.timers, interrupt_id)

    new_state = %{state |
      interrupt_stack: new_stack,
      timers: new_timers,
      version: state.version + 1
    }

    update_active_content(new_state)
  end

  defp extend_sub_train(state, sub_train_id, event) do
    # Cancel existing timer
    if timer_ref = state.timers[sub_train_id] do
      Process.cancel_timer(timer_ref)
    end

    # Update sub train data
    new_stack = Enum.map(state.interrupt_stack, fn interrupt ->
      if interrupt.id == sub_train_id do
        new_count = (interrupt.data.count || 0) + 1
        %{interrupt | 
          data: Map.merge(interrupt.data, %{
            count: new_count,
            latest_subscriber: event.username,
            latest_tier: event.tier
          })
        }
      else
        interrupt
      end
    end)

    # Set new timer
    new_timer_ref = Process.send_after(self(), {:interrupt_expired, sub_train_id}, @sub_train_duration)
    new_timers = Map.put(state.timers, sub_train_id, new_timer_ref)

    %{state |
      interrupt_stack: new_stack,
      timers: new_timers,
      version: state.version + 1
    }
  end

  defp active_content_type(state) do
    case state.active_content do
      nil -> nil
      content -> content.type
    end
  end

  defp schedule_ticker_rotation do
    Process.send_after(self(), :ticker_tick, @ticker_interval)
  end

  defp get_content_data(content_type) do
    case content_type do
      :emote_stats ->
        Server.ContentAggregator.get_emote_stats()
      
      :recent_follows ->
        %{recent_followers: Server.ContentAggregator.get_recent_followers(5)}
      
      :daily_stats ->
        Server.ContentAggregator.get_daily_stats()
      
      :ironmon_run_stats ->
        # TODO: Get from IronMON service
        %{
          run_number: 47,
          deaths: 3,
          location: "Cerulean City",
          gym_progress: 2
        }
      
      :commit_stats ->
        # TODO: Get from git integration
        %{
          commits_today: 12,
          lines_added: 245,
          lines_removed: 89
        }
      
      :build_status ->
        # TODO: Get from CI integration
        %{
          status: "passing",
          last_build: "2 hours ago",
          coverage: "85%"
        }
      
      :stream_goals ->
        # TODO: Get from goals tracking
        %{
          follower_goal: %{current: 1250, target: 1500},
          sub_goal: %{current: 42, target: 50}
        }
      
      _ ->
        %{message: "Content type #{content_type} not implemented yet"}
    end
  end

  defp broadcast_state_update(state) do
    Phoenix.PubSub.broadcast(Server.PubSub, "stream:updates", {:stream_update, state})
  end
end