defmodule Server.Services.OBS.StreamManager do
  @moduledoc """
  Manages OBS streaming and recording state.

  Tracks streaming status, recording status, and related metrics.

  ## Events Published

  Routes state change events through the unified Server.Events system
  using event types like "obs.stream_started", "obs.recording_started".
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

  @doc """
  Check if currently streaming.
  """
  def streaming?(manager) do
    GenServer.call(manager, :is_streaming)
  end

  @doc """
  Check if currently recording.
  """
  def recording?(manager) do
    GenServer.call(manager, :is_recording)
  end

  @doc """
  Check if recording is paused.
  """
  def recording_paused?(manager) do
    GenServer.call(manager, :is_recording_paused)
  end

  @doc """
  Check if virtual camera is active.
  """
  def virtual_cam_active?(manager) do
    GenServer.call(manager, :is_virtual_cam_active)
  end

  @doc """
  Check if replay buffer is active.
  """
  def replay_buffer_active?(manager) do
    GenServer.call(manager, :is_replay_buffer_active)
  end

  @doc """
  Get comprehensive stream information.
  """
  def get_stream_info(manager) do
    GenServer.call(manager, :get_stream_info)
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

  def handle_call(:is_streaming, _from, state) do
    {:reply, state.streaming_active, state}
  end

  def handle_call(:is_recording, _from, state) do
    {:reply, state.recording_active, state}
  end

  def handle_call(:is_recording_paused, _from, state) do
    {:reply, state.recording_paused, state}
  end

  def handle_call(:is_virtual_cam_active, _from, state) do
    {:reply, state.virtual_cam_active, state}
  end

  def handle_call(:is_replay_buffer_active, _from, state) do
    {:reply, state.replay_buffer_active, state}
  end

  def handle_call(:get_stream_info, _from, state) do
    info = %{
      streaming: state.streaming_active,
      recording: state.recording_active,
      recording_paused: state.recording_paused,
      virtual_cam: state.virtual_cam_active,
      replay_buffer: state.replay_buffer_active,
      session_id: state.session_id
    }

    {:reply, info, state}
  end

  @impl true
  def handle_info({:obs_event, %{eventType: "StreamStateChanged", eventData: data}}, state) do
    active = data[:outputActive]
    state = %{state | streaming_active: active}

    # Route through unified system ONLY
    event_type = if active, do: "obs.stream_started", else: "obs.stream_stopped"

    unified_data = %{
      output_active: active,
      session_id: state.session_id
    }

    case Server.Events.process_event(event_type, unified_data) do
      :ok -> Logger.debug("OBS stream state routed through unified system", event_type: event_type)
      {:error, reason} -> Logger.warning("Unified routing failed", reason: reason, event_type: event_type)
    end

    Logger.info("Stream state changed: #{if active, do: "started", else: "stopped"}",
      service: "obs",
      session_id: state.session_id
    )

    {:noreply, state}
  end

  def handle_info({:obs_event, %{eventType: "RecordStateChanged", eventData: data}}, state) do
    active = data[:outputActive]
    state = %{state | recording_active: active}

    # Route through unified system ONLY
    event_type = if active, do: "obs.recording_started", else: "obs.recording_stopped"

    unified_data = %{
      output_active: active,
      session_id: state.session_id
    }

    case Server.Events.process_event(event_type, unified_data) do
      :ok -> Logger.debug("OBS record state routed through unified system", event_type: event_type)
      {:error, reason} -> Logger.warning("Unified routing failed", reason: reason, event_type: event_type)
    end

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
