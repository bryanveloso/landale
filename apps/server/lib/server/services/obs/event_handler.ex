defmodule Server.Services.OBS.EventHandler do
  @moduledoc """
  Processes OBS events and routes them to appropriate handlers.

  Subscribes to the session-specific PubSub topic and handles
  all incoming OBS events.
  """
  use GenServer
  require Logger

  defstruct [:session_id]

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

    {:ok, %__MODULE__{session_id: session_id}}
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

    # Route event to appropriate handler
    handle_obs_event(event, state)

    {:noreply, state}
  end

  # Catch-all for unexpected messages
  def handle_info(_msg, state) do
    # Ignore unexpected messages
    {:noreply, state}
  end

  # Event handlers

  defp handle_obs_event(%{eventType: "CurrentProgramSceneChanged"} = event, state) do
    # Scene change events are handled by SceneManager
    # Just log here
    Logger.info("Scene changed to: #{event[:eventData][:sceneName]}",
      service: "obs",
      session_id: state.session_id
    )
  end

  defp handle_obs_event(%{eventType: "StreamStateChanged"} = event, state) do
    # Stream state events are handled by StreamManager
    Logger.info("Stream state changed",
      service: "obs",
      session_id: state.session_id,
      active: event[:eventData][:outputActive],
      state: event[:eventData][:outputState]
    )
  end

  defp handle_obs_event(%{eventType: "RecordStateChanged"} = event, state) do
    # Record state events are handled by StreamManager
    Logger.info("Record state changed",
      service: "obs",
      session_id: state.session_id,
      active: event[:eventData][:outputActive],
      state: event[:eventData][:outputState]
    )
  end

  defp handle_obs_event(event, state) do
    # Generic event handling
    Logger.debug("Unhandled OBS event",
      service: "obs",
      session_id: state.session_id,
      event_type: event[:eventType]
    )
  end
end
