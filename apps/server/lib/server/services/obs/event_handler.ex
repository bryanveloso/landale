defmodule Server.Services.OBS.EventHandler do
  @moduledoc """
  Processes OBS events and routes them to appropriate handlers.

  Subscribes to the session-specific PubSub topic and handles
  all incoming OBS events.
  """
  use GenServer
  require Logger

  defstruct [:session_id, :current_scene, :stream_active, :record_active, :last_event_type]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  @doc """
  Get the current state.
  """
  def get_state(handler) do
    GenServer.call(handler, :get_state)
  end

  @doc """
  Get the session ID.
  """
  def get_session_id(handler) do
    GenServer.call(handler, :get_session_id)
  end

  @impl true
  def init(opts) do
    session_id = Keyword.fetch!(opts, :session_id)

    # Subscribe to OBS events for this session
    Phoenix.PubSub.subscribe(Server.PubSub, "obs_events:#{session_id}")

    {:ok,
     %__MODULE__{
       session_id: session_id,
       current_scene: nil,
       stream_active: false,
       record_active: false,
       last_event_type: nil
     }}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  def handle_call(:get_session_id, _from, state) do
    {:reply, state.session_id, state}
  end

  @impl true
  def handle_info({:obs_event, event}, state) do
    # Log event for debugging
    Logger.debug("OBS event received",
      service: "obs",
      session_id: state.session_id,
      event_type: event[:eventType],
      event: event
    )

    # Route event to appropriate handler and update state
    new_state = handle_obs_event(event, state)

    {:noreply, new_state}
  end

  # Catch-all for unexpected messages
  def handle_info(_msg, state) do
    # Ignore unexpected messages
    {:noreply, state}
  end

  # Event handlers

  defp handle_obs_event(%{eventType: "CurrentProgramSceneChanged"} = event, state) do
    scene_name = event[:eventData][:sceneName]

    # Update state
    new_state = %{
      state
      | current_scene: scene_name,
        last_event_type: "CurrentProgramSceneChanged"
    }

    # Route through unified system ONLY
    unified_data = %{scene_name: scene_name, session_id: state.session_id}

    case Server.Events.process_event("obs.scene_changed", unified_data) do
      :ok -> Logger.debug("OBS scene change routed through unified system")
      {:error, reason} -> Logger.warning("Unified routing failed", reason: reason)
    end

    # Log event
    Logger.info("Scene changed to: #{scene_name}",
      service: "obs",
      session_id: state.session_id
    )

    new_state
  end

  defp handle_obs_event(%{eventType: "StreamStateChanged"} = event, state) do
    stream_active = event[:eventData][:outputActive]
    output_state = event[:eventData][:outputState]

    # Update state
    new_state = %{state | stream_active: stream_active, last_event_type: "StreamStateChanged"}

    # Route through unified system ONLY - map to appropriate started/stopped event
    event_type = if stream_active, do: "obs.stream_started", else: "obs.stream_stopped"

    unified_data = %{
      output_active: stream_active,
      output_state: output_state,
      session_id: state.session_id
    }

    case Server.Events.process_event(event_type, unified_data) do
      :ok -> Logger.debug("OBS stream state change routed through unified system", event_type: event_type)
      {:error, reason} -> Logger.warning("Unified routing failed", reason: reason, event_type: event_type)
    end

    # Log event
    Logger.info("Stream state changed",
      service: "obs",
      session_id: state.session_id,
      active: stream_active,
      state: output_state
    )

    new_state
  end

  defp handle_obs_event(%{eventType: "RecordStateChanged"} = event, state) do
    record_active = event[:eventData][:outputActive]
    output_state = event[:eventData][:outputState]

    # Update state
    new_state = %{state | record_active: record_active, last_event_type: "RecordStateChanged"}

    # Route through unified system ONLY - map to appropriate started/stopped event
    event_type = if record_active, do: "obs.recording_started", else: "obs.recording_stopped"

    unified_data = %{
      output_active: record_active,
      output_state: output_state,
      session_id: state.session_id
    }

    case Server.Events.process_event(event_type, unified_data) do
      :ok -> Logger.debug("OBS record state change routed through unified system", event_type: event_type)
      {:error, reason} -> Logger.warning("Unified routing failed", reason: reason, event_type: event_type)
    end

    # Log event
    Logger.info("Record state changed",
      service: "obs",
      session_id: state.session_id,
      active: record_active,
      state: output_state
    )

    new_state
  end

  defp handle_obs_event(event, state) when is_map(event) do
    event_type = event[:eventType]

    # Update state to track unhandled events
    new_state = %{state | last_event_type: event_type}

    # Route unknown OBS events through unified system ONLY
    unified_data = %{
      event_type: event_type,
      event_data: event[:eventData] || %{},
      session_id: state.session_id
    }

    case Server.Events.process_event("obs.unknown_event", unified_data) do
      :ok -> Logger.debug("OBS unknown event routed through unified system", event_type: event_type)
      {:error, reason} -> Logger.warning("Unified routing failed", reason: reason, event_type: event_type)
    end

    # Log generic event handling
    Logger.debug("Unhandled OBS event",
      service: "obs",
      session_id: state.session_id,
      event_type: event_type
    )

    new_state
  end

  defp handle_obs_event(malformed_event, state) do
    # Handle malformed events gracefully
    Logger.warning("Received malformed OBS event",
      service: "obs",
      session_id: state.session_id,
      event: malformed_event
    )

    # Don't update state for malformed events
    state
  end
end
