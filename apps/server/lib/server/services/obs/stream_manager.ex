defmodule Server.Services.OBS.StreamManager do
  @moduledoc """
  Manages OBS streaming and recording state.

  Tracks streaming status, recording status, and related metrics.
  """
  use GenServer
  require Logger

  defstruct [
    :session_id,
    # Streaming state
    streaming_active: false,
    streaming_timecode: "00:00:00",
    streaming_duration: 0,
    streaming_congestion: 0,
    streaming_bytes: 0,
    streaming_skipped_frames: 0,
    streaming_total_frames: 0,
    # Recording state
    recording_active: false,
    recording_paused: false,
    recording_timecode: "00:00:00",
    recording_duration: 0,
    recording_bytes: 0,
    # Other outputs
    virtual_cam_active: false,
    replay_buffer_active: false
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  @doc """
  Get the current state.
  """
  def get_state(manager) do
    GenServer.call(manager, :get_state)
  end

  @impl true
  def init(opts) do
    session_id = Keyword.fetch!(opts, :session_id)

    # Subscribe to OBS events
    Phoenix.PubSub.subscribe(Server.PubSub, "obs_events:#{session_id}")

    state = %__MODULE__{
      session_id: session_id
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_info({:obs_event, %{eventType: "StreamStateChanged", eventData: data}}, state) do
    active = data[:outputActive]
    state = %{state | streaming_active: active}

    # Broadcast state change
    event_type = if active, do: :stream_started, else: :stream_stopped

    Phoenix.PubSub.broadcast(
      Server.PubSub,
      "obs:events",
      {event_type,
       %{
         session_id: state.session_id,
         active: active
       }}
    )

    Logger.info("Stream state changed: #{if active, do: "started", else: "stopped"}",
      service: "obs",
      session_id: state.session_id
    )

    {:noreply, state}
  end

  def handle_info({:obs_event, %{eventType: "RecordStateChanged", eventData: data}}, state) do
    active = data[:outputActive]
    state = %{state | recording_active: active}

    # Broadcast state change
    event_type = if active, do: :record_started, else: :record_stopped

    Phoenix.PubSub.broadcast(
      Server.PubSub,
      "obs:events",
      {event_type,
       %{
         session_id: state.session_id,
         active: active
       }}
    )

    Logger.info("Record state changed: #{if active, do: "started", else: "stopped"}",
      service: "obs",
      session_id: state.session_id
    )

    {:noreply, state}
  end

  def handle_info({:obs_event, %{eventType: "RecordPauseStateChanged", eventData: data}}, state) do
    paused = data[:outputPaused]
    state = %{state | recording_paused: paused}

    Logger.info("Record pause state changed: #{if paused, do: "paused", else: "resumed"}",
      service: "obs",
      session_id: state.session_id
    )

    {:noreply, state}
  end

  def handle_info({:obs_event, %{eventType: "VirtualCamStateChanged", eventData: data}}, state) do
    active = data[:outputActive]
    state = %{state | virtual_cam_active: active}

    {:noreply, state}
  end

  def handle_info({:obs_event, %{eventType: "ReplayBufferStateChanged", eventData: data}}, state) do
    active = data[:outputActive]
    state = %{state | replay_buffer_active: active}

    {:noreply, state}
  end

  def handle_info({:obs_event, _event}, state) do
    # Ignore other events
    {:noreply, state}
  end
end
