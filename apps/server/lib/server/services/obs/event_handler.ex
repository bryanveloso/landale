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

    # Publish scene change event
    Phoenix.PubSub.broadcast(Server.PubSub, "overlay:scene_changed", %{
      scene: scene_name,
      session_id: state.session_id
    })

    # Log event
    Logger.info("Scene changed to: #{scene_name}",
      service: "obs",
      session_id: state.session_id
    )

    new_state
  end

  defp handle_obs_event(%{eventType: "StreamStateChanged"} = event, state) do
    stream_active = event[:eventData][:outputActive]

    # Update state
    new_state = %{state | stream_active: stream_active, last_event_type: "StreamStateChanged"}

    # Publish stream state change event
    Phoenix.PubSub.broadcast(Server.PubSub, "overlay:stream_state", %{
      active: stream_active,
      state: event[:eventData][:outputState],
      session_id: state.session_id
    })

    # Log event
    Logger.info("Stream state changed",
      service: "obs",
      session_id: state.session_id,
      active: stream_active,
      state: event[:eventData][:outputState]
    )

    new_state
  end

  defp handle_obs_event(%{eventType: "RecordStateChanged"} = event, state) do
    record_active = event[:eventData][:outputActive]

    # Update state
    new_state = %{state | record_active: record_active, last_event_type: "RecordStateChanged"}

    # Publish record state change event
    Phoenix.PubSub.broadcast(Server.PubSub, "overlay:record_state", %{
      active: record_active,
      state: event[:eventData][:outputState],
      session_id: state.session_id
    })

    # Log event
    Logger.info("Record state changed",
      service: "obs",
      session_id: state.session_id,
      active: record_active,
      state: event[:eventData][:outputState]
    )

    new_state
  end

  defp handle_obs_event(event, state) when is_map(event) do
    event_type = event[:eventType]

    # Update state to track unhandled events
    new_state = %{state | last_event_type: event_type}

    # Publish unhandled event
    Phoenix.PubSub.broadcast(Server.PubSub, "overlay:unhandled_event", %{
      event_type: event_type,
      session_id: state.session_id
    })

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
