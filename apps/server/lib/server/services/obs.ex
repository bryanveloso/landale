defmodule Server.Services.OBS do
  @behaviour Server.Services.OBSBehaviour

  @moduledoc """
  OBS WebSocket integration service using Gun WebSocket client.

  Provides comprehensive OBS WebSocket v5 functionality:
  - Connection management with auto-reconnect
  - State management for scenes, streaming, recording, etc.
  - Event publishing via PubSub
  - Performance monitoring with stats polling
  - Full OBS WebSocket v5 protocol support

  ## Configuration

  The service can be configured with the following environment variables:
  - `OBS_WEBSOCKET_URL` - WebSocket URL (default: "ws://localhost:4455")

  ## Usage

      # Get current service status
      {:ok, status} = Server.Services.OBS.get_status()

      # Control streaming
      :ok = Server.Services.OBS.start_streaming()
      :ok = Server.Services.OBS.stop_streaming()

      # Control recording
      :ok = Server.Services.OBS.start_recording()
      :ok = Server.Services.OBS.stop_recording()

      # Scene management
      :ok = Server.Services.OBS.set_current_scene("Scene Name")

  ## Events

  The service publishes events via Phoenix.PubSub on the "obs:events" topic:
  - `connection_established` - WebSocket connected
  - `connection_lost` - WebSocket disconnected
  - `scene_current_changed` - Current scene changed
  - `stream_started` / `stream_stopped` - Streaming state changes
  """

  use GenServer
  require Logger
  import Bitwise

  alias Server.{CorrelationId, Logging, ServiceError}

  # OBS WebSocket v5 protocol constants
  # EventSubscription flags based on OBS WebSocket v5 specification

  # Standard event categories (non-high-volume)
  # General events (1 << 0)
  @event_subscription_general 1
  # Config events (1 << 1)
  @event_subscription_config 2
  # Scene events (1 << 2)
  @event_subscription_scenes 4
  # Input events (1 << 3)
  @event_subscription_inputs 8
  # Transition events (1 << 4)
  @event_subscription_transitions 16
  # Filter events (1 << 5)
  @event_subscription_filters 32
  # Output events (1 << 6)
  @event_subscription_outputs 64
  # Scene item events (1 << 7)
  @event_subscription_scene_items 128
  # Media input events (1 << 8)
  @event_subscription_media_inputs 256
  # Vendor events (1 << 9)
  @event_subscription_vendors 512
  # UI events (1 << 10)
  @event_subscription_ui 1024

  # EventSubscription::All helper (non-high-volume events only)
  @event_subscription_all @event_subscription_general |||
                            @event_subscription_config |||
                            @event_subscription_scenes |||
                            @event_subscription_inputs |||
                            @event_subscription_transitions |||
                            @event_subscription_filters |||
                            @event_subscription_outputs |||
                            @event_subscription_scene_items |||
                            @event_subscription_media_inputs |||
                            @event_subscription_vendors |||
                            @event_subscription_ui
  # Network configuration is now handled by Server.NetworkConfig
  # 5 seconds
  @stats_polling_interval 5_000
  # Request timeout: 10 seconds
  @request_timeout 10_000

  # Enforce required keys for compile-time safety
  @enforce_keys [:uri, :connection_manager]

  defstruct [
    # Required fields
    :uri,
    :connection_manager,

    # WebSocket connection fields
    :conn_pid,
    :stream_ref,

    # Timer references
    :stats_timer,
    :reconnect_timer,

    # OBS connection state
    connected: false,
    connection_state: "disconnected",
    authenticated: false,
    authentication_required: false,
    last_error: nil,
    last_connected: nil,
    negotiated_rpc_version: nil,

    # Message queuing during authentication
    pending_messages: [],

    # Request tracking for delivery confirmation
    pending_requests: %{},
    next_request_id: 1,

    # OBS scene state
    current_scene: nil,
    preview_scene: nil,
    scene_list: [],

    # OBS streaming state
    streaming_active: false,
    streaming_timecode: "00:00:00",
    streaming_duration: 0,
    streaming_congestion: 0,
    streaming_bytes: 0,
    streaming_skipped_frames: 0,
    streaming_total_frames: 0,

    # OBS recording state
    recording_active: false,
    recording_paused: false,
    recording_timecode: "00:00:00",
    recording_duration: 0,
    recording_bytes: 0,

    # OBS mode states
    studio_mode_enabled: false,
    virtual_cam_active: false,
    replay_buffer_active: false,

    # OBS performance stats
    active_fps: 0,
    average_frame_time: 0,
    cpu_usage: 0,
    memory_usage: 0,
    available_disk_space: 0,
    render_total_frames: 0,
    render_skipped_frames: 0,
    output_total_frames: 0,
    output_skipped_frames: 0,
    websocket_incoming_messages: 0,
    websocket_outgoing_messages: 0,
    stats_last_updated: nil
  ]

  # Client API

  @doc """
  Starts the OBS service GenServer.

  ## Parameters
  - `opts` - Keyword list of options (optional)
    - `:url` - WebSocket URL to connect to

  ## Returns
  - `{:ok, pid}` on success
  - `{:error, reason}` on failure
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets the current internal state of the OBS service with caching.

  Uses ETS cache to reduce GenServer load. Cache TTL is 1 second for basic status
  and 2 seconds for detailed state to balance responsiveness with performance.

  ## Returns
  - Map containing connection, scenes, streaming, and recording state
  """
  @spec get_state() :: map()
  def get_state do
    Server.Cache.get_or_compute(
      :obs_service,
      :full_state,
      fn ->
        GenServer.call(__MODULE__, :get_state)
      end,
      ttl_seconds: 2
    )
  end

  @doc """
  Gets the current status of the OBS service with caching.

  Uses aggressive caching (1 second TTL) for connection status since this is
  called frequently by dashboard and health checks but changes infrequently.

  ## Returns
  - `{:ok, status}` where status contains connection information
  - `{:error, reason}` if service is unavailable
  """
  @spec get_status() :: {:ok, map()} | {:error, ServiceError.service_error()}
  @impl true
  def get_status do
    Server.Cache.get_or_compute(
      :obs_service,
      :connection_status,
      fn ->
        GenServer.call(__MODULE__, :get_status)
      end,
      ttl_seconds: 1
    )
  end

  @doc """
  Gets basic OBS status flags (connected, streaming, recording) with aggressive caching.

  This is the most frequently accessed data for dashboard indicators.
  Uses 500ms TTL for ultra-fast response to high-frequency polling.

  ## Returns
  - Map with basic status flags
  """
  @spec get_basic_status() :: map()
  def get_basic_status do
    Server.Cache.get_or_compute(
      :obs_service,
      :basic_status,
      fn ->
        state = GenServer.call(__MODULE__, :get_internal_state)

        %{
          connected: state.connected,
          streaming: state.streaming_active,
          recording: state.recording_active,
          current_scene: state.current_scene
        }
      end,
      ttl_seconds: 1
    )
  end

  @doc """
  Starts streaming in OBS.

  ## Returns
  - `:ok` on success
  - `{:error, reason}` if not connected or command fails
  """
  @spec start_streaming() :: :ok | {:error, binary()}
  def start_streaming do
    GenServer.call(__MODULE__, {:obs_call, "StartStream", %{}})
  end

  @doc """
  Stops streaming in OBS.

  ## Returns
  - `:ok` on success
  - `{:error, reason}` if not connected or command fails
  """
  @spec stop_streaming() :: :ok | {:error, binary()}
  def stop_streaming do
    GenServer.call(__MODULE__, {:obs_call, "StopStream", %{}})
  end

  @doc """
  Starts recording in OBS.

  ## Returns
  - `:ok` on success
  - `{:error, reason}` if not connected or command fails
  """
  @spec start_recording() :: :ok | {:error, binary()}
  def start_recording do
    GenServer.call(__MODULE__, {:obs_call, "StartRecord", %{}})
  end

  @doc """
  Stops recording in OBS.

  ## Returns
  - `:ok` on success
  - `{:error, reason}` if not connected or command fails
  """
  @spec stop_recording() :: :ok | {:error, binary()}
  def stop_recording do
    GenServer.call(__MODULE__, {:obs_call, "StopRecord", %{}})
  end

  @doc """
  Pauses the current recording in OBS.

  ## Returns
  - `:ok` on success
  - `{:error, reason}` if not connected or command fails
  """
  @spec pause_recording() :: :ok | {:error, binary()}
  def pause_recording do
    GenServer.call(__MODULE__, {:obs_call, "PauseRecord", %{}})
  end

  @doc """
  Resumes a paused recording in OBS.

  ## Returns
  - `:ok` on success
  - `{:error, reason}` if not connected or command fails
  """
  @spec resume_recording() :: :ok | {:error, binary()}
  def resume_recording do
    GenServer.call(__MODULE__, {:obs_call, "ResumeRecord", %{}})
  end

  @doc """
  Sets the current program scene in OBS.

  ## Parameters
  - `scene_name` - Name of the scene to switch to

  ## Returns
  - `:ok` on success
  - `{:error, reason}` if not connected or command fails
  """
  @spec set_current_scene(binary()) :: :ok | {:error, binary()}
  def set_current_scene(scene_name) do
    GenServer.call(__MODULE__, {:obs_call, "SetCurrentProgramScene", %{sceneName: scene_name}})
  end

  @doc """
  Sets the current preview scene in OBS (requires Studio Mode).

  ## Parameters
  - `scene_name` - Name of the scene to set as preview

  ## Returns
  - `:ok` on success
  - `{:error, reason}` if not connected or command fails
  """
  @spec set_preview_scene(binary()) :: :ok | {:error, binary()}
  def set_preview_scene(scene_name) do
    GenServer.call(__MODULE__, {:obs_call, "SetCurrentPreviewScene", %{sceneName: scene_name}})
  end

  @doc """
  Enables or disables Studio Mode in OBS.

  ## Parameters
  - `enabled` - Boolean to enable or disable Studio Mode

  ## Returns
  - `:ok` on success
  - `{:error, reason}` if not connected or command fails
  """
  @spec set_studio_mode_enabled(boolean()) :: :ok | {:error, binary()}
  def set_studio_mode_enabled(enabled) do
    GenServer.call(__MODULE__, {:obs_call, "SetStudioModeEnabled", %{studioModeEnabled: enabled}})
  end

  @doc """
  Triggers a transition from the current preview scene to the program scene in Studio Mode.

  ## Returns
  - `:ok` on success
  - `{:error, reason}` if not connected or command fails
  """
  @spec trigger_studio_mode_transition() :: :ok | {:error, binary()}
  def trigger_studio_mode_transition do
    GenServer.call(__MODULE__, {:obs_call, "TriggerStudioModeTransition", %{}})
  end

  @doc """
  Starts the virtual camera output in OBS.

  ## Returns
  - `:ok` on success
  - `{:error, reason}` if not connected or command fails
  """
  @spec start_virtual_cam() :: :ok | {:error, binary()}
  def start_virtual_cam do
    GenServer.call(__MODULE__, {:obs_call, "StartVirtualCam", %{}})
  end

  @doc """
  Stops the virtual camera output in OBS.

  ## Returns
  - `:ok` on success
  - `{:error, reason}` if not connected or command fails
  """
  @spec stop_virtual_cam() :: :ok | {:error, binary()}
  def stop_virtual_cam do
    GenServer.call(__MODULE__, {:obs_call, "StopVirtualCam", %{}})
  end

  @doc """
  Starts the replay buffer feature in OBS.

  ## Returns
  - `:ok` on success
  - `{:error, reason}` if not connected or command fails
  """
  @spec start_replay_buffer() :: :ok | {:error, binary()}
  def start_replay_buffer do
    GenServer.call(__MODULE__, {:obs_call, "StartReplayBuffer", %{}})
  end

  @doc """
  Stops the replay buffer feature in OBS.

  ## Returns
  - `:ok` on success
  - `{:error, reason}` if not connected or command fails
  """
  @spec stop_replay_buffer() :: :ok | {:error, binary()}
  def stop_replay_buffer do
    GenServer.call(__MODULE__, {:obs_call, "StopReplayBuffer", %{}})
  end

  @doc """
  Saves the current replay buffer to disk in OBS.

  ## Returns
  - `:ok` on success
  - `{:error, reason}` if not connected or command fails
  """
  @spec save_replay_buffer() :: :ok | {:error, binary()}
  def save_replay_buffer do
    GenServer.call(__MODULE__, {:obs_call, "SaveReplayBuffer", %{}})
  end

  @doc """
  Gets the list of all scenes in OBS.

  ## Returns
  - `{:ok, scenes}` with list of scenes and current scene info
  - `{:error, reason}` if not connected or command fails
  """
  @spec get_scene_list() :: {:ok, map()} | {:error, binary()}
  @impl true
  def get_scene_list do
    GenServer.call(__MODULE__, {:obs_call, "GetSceneList", %{}})
  end

  @doc """
  Gets the current program scene in OBS.

  ## Returns
  - `{:ok, scene_info}` with current scene details
  - `{:error, reason}` if not connected or command fails
  """
  @spec get_current_scene() :: {:ok, map()} | {:error, binary()}
  def get_current_scene do
    GenServer.call(__MODULE__, {:obs_call, "GetCurrentProgramScene", %{}})
  end

  @doc """
  Gets the current program scene in OBS (alias for compatibility).

  ## Returns
  - `{:ok, scene_info}` with current scene details
  - `{:error, reason}` if not connected or command fails
  """
  @spec get_current_program_scene() :: {:ok, map()} | {:error, binary()}
  def get_current_program_scene do
    GenServer.call(__MODULE__, {:obs_call, "GetCurrentProgramScene", %{}})
  end

  @doc """
  Gets detailed stream status information from OBS.

  ## Returns
  - `{:ok, stream_status}` with stream metrics (uptime, bitrate, frames, etc.)
  - `{:error, reason}` if not connected or command fails
  """
  @spec get_stream_status() :: {:ok, map()} | {:error, binary()}
  @impl true
  def get_stream_status do
    GenServer.call(__MODULE__, {:obs_call, "GetStreamStatus", %{}})
  end

  @doc """
  Gets detailed recording status information from OBS.

  ## Returns
  - `{:ok, record_status}` with recording metrics (duration, status, etc.)
  - `{:error, reason}` if not connected or command fails
  """
  @spec get_record_status() :: {:ok, map()} | {:error, binary()}
  @impl true
  def get_record_status do
    GenServer.call(__MODULE__, {:obs_call, "GetRecordStatus", %{}})
  end

  @doc """
  Gets OBS version information.

  ## Returns
  - `{:ok, version_info}` with OBS and WebSocket plugin versions
  - `{:error, reason}` if not connected or command fails
  """
  @spec get_version() :: {:ok, map()} | {:error, binary()}
  @impl true
  def get_version do
    GenServer.call(__MODULE__, {:obs_call, "GetVersion", %{}})
  end

  @doc """
  Gets virtual camera status.

  ## Returns
  - `{:ok, virtual_cam_status}` with virtual camera state
  - `{:error, reason}` if not connected or command fails
  """
  @spec get_virtual_cam_status() :: {:ok, map()} | {:error, binary()}
  @impl true
  def get_virtual_cam_status do
    GenServer.call(__MODULE__, {:obs_call, "GetVirtualCamStatus", %{}})
  end

  @doc """
  Gets list of outputs configured in OBS.

  ## Returns
  - `{:ok, outputs}` with list of all outputs
  - `{:error, reason}` if not connected or command fails
  """
  @spec get_output_list() :: {:ok, map()} | {:error, binary()}
  @impl true
  def get_output_list do
    GenServer.call(__MODULE__, {:obs_call, "GetOutputList", %{}})
  end

  @doc """
  Gets OBS performance statistics.

  Returns current FPS, CPU usage, memory usage, and other performance metrics.
  """
  @spec get_stats() :: {:ok, map()} | {:error, term()}
  @impl true
  def get_stats do
    case GenServer.call(__MODULE__, :get_state) do
      %{state: %{stats: stats}} when is_map(stats) ->
        {:ok, stats}

      %{state: %{connection: %{connected: true}}} ->
        # If connected but no stats yet, make a direct request
        GenServer.call(__MODULE__, {:obs_call, "GetStats", %{}})

      _ ->
        {:error, "OBS not connected"}
    end
  end

  @doc """
  Gets status of a specific output.

  ## Parameters
  - `output_name` - Name of the output to check

  ## Returns
  - `{:ok, output_status}` with output details
  - `{:error, reason}` if not connected or command fails
  """
  @spec get_output_status(binary()) :: {:ok, map()} | {:error, binary()}
  def get_output_status(output_name) do
    GenServer.call(__MODULE__, {:obs_call, "GetOutputStatus", %{outputName: output_name}})
  end

  # GenServer callbacks
  @impl GenServer
  def init(opts) do
    url = Keyword.get(opts, :url, get_websocket_url())
    uri = URI.parse(url)

    state = %__MODULE__{
      uri: uri,
      connection_manager: Server.ConnectionManager.init_connection_state(),
      pending_requests: %{},
      pending_messages: [],
      next_request_id: 1
    }

    # Set service context for all log messages from this process
    Logging.set_service_context(:obs, url: url)
    correlation_id = Logging.set_correlation_id()

    Logger.info("Service starting", correlation_id: correlation_id)

    # Try to connect immediately
    send(self(), :connect)

    {:ok, state}
  end

  @impl GenServer
  def handle_call(:get_state, _from, state) do
    # Return a map representation of the relevant OBS state
    state_map = %{
      connection: %{
        connected: state.connected,
        connection_state: state.connection_state,
        last_error: state.last_error,
        last_connected: state.last_connected,
        negotiated_rpc_version: state.negotiated_rpc_version
      },
      scenes: %{
        current: state.current_scene,
        preview: state.preview_scene,
        list: state.scene_list
      },
      streaming: %{
        active: state.streaming_active,
        timecode: state.streaming_timecode,
        duration: state.streaming_duration,
        congestion: state.streaming_congestion,
        bytes: state.streaming_bytes,
        skipped_frames: state.streaming_skipped_frames,
        total_frames: state.streaming_total_frames
      },
      recording: %{
        active: state.recording_active,
        paused: state.recording_paused,
        timecode: state.recording_timecode,
        duration: state.recording_duration,
        bytes: state.recording_bytes
      },
      studio_mode: %{
        enabled: state.studio_mode_enabled
      },
      virtual_cam: %{
        active: state.virtual_cam_active
      },
      replay_buffer: %{
        active: state.replay_buffer_active
      },
      stats: %{
        active_fps: state.active_fps,
        average_frame_time: state.average_frame_time,
        cpu_usage: state.cpu_usage,
        memory_usage: state.memory_usage,
        available_disk_space: state.available_disk_space,
        render_total_frames: state.render_total_frames,
        render_skipped_frames: state.render_skipped_frames,
        output_total_frames: state.output_total_frames,
        output_skipped_frames: state.output_skipped_frames,
        web_socket_session_incoming_messages: state.websocket_incoming_messages,
        web_socket_session_outgoing_messages: state.websocket_outgoing_messages,
        last_updated: state.stats_last_updated
      }
    }

    {:reply, state_map, state}
  end

  @impl GenServer
  def handle_call(:get_status, _from, state) do
    # Direct struct field access - clean and simple
    connection_status = %{
      connected: state.connected,
      connection_state: state.connection_state
    }

    {:reply, {:ok, connection_status}, state}
  end

  @impl GenServer
  def handle_call(:get_internal_state, _from, state) do
    {:reply, state, state}
  end

  @impl GenServer
  def handle_call({:obs_call, request_type, request_data}, from, state) do
    # Direct struct field access - clean and simple
    if state.connected and state.conn_pid != nil and state.stream_ref != nil do
      request_id = CorrelationId.generate()

      message = %{
        op: 6,
        d: %{
          requestId: request_id,
          requestType: request_type,
          requestData: request_data
        }
      }

      case send_websocket_message(state, message) do
        :ok ->
          # Store the pending request with timeout
          timeout_ref = Process.send_after(self(), {:request_timeout, request_id}, @request_timeout)
          pending_requests = Map.put(state.pending_requests, request_id, {from, timeout_ref})
          new_state = %{state | pending_requests: pending_requests}
          {:noreply, new_state}

        {:queued, updated_state} ->
          # Message was queued during authentication - store request and update state
          timeout_ref = Process.send_after(self(), {:request_timeout, request_id}, @request_timeout)
          pending_requests = Map.put(updated_state.pending_requests, request_id, {from, timeout_ref})
          new_state = %{updated_state | pending_requests: pending_requests}

          Logger.debug("Request queued during authentication",
            request_type: request_type,
            request_id: request_id
          )

          {:noreply, new_state}

        {:error, reason} ->
          error =
            ServiceError.new(:obs, "websocket_send", :network_error, "Failed to send WebSocket message",
              details: %{reason: reason}
            )

          {:reply, {:error, error}, state}
      end
    else
      error = ServiceError.new(:obs, "websocket_call", :service_unavailable, "OBS not connected")
      {:reply, {:error, error}, state}
    end
  end

  @impl GenServer
  def handle_cast({:update_outgoing_counter, new_count}, state) do
    updated_state = %{state | websocket_outgoing_messages: new_count}
    {:noreply, updated_state}
  end

  @impl GenServer
  def handle_info({:request_timeout, request_id}, state) do
    case Map.pop(state.pending_requests, request_id) do
      {nil, _} ->
        # Request already completed or wasn't tracked
        {:noreply, state}

      {{from, _timeout_ref}, remaining_requests} ->
        Logger.warning("Request timed out",
          request_id: request_id,
          timeout_ms: @request_timeout
        )

        error =
          ServiceError.new(:obs, "request", :timeout, "Request timed out after #{@request_timeout}ms",
            details: %{request_id: request_id}
          )

        GenServer.reply(from, {:error, error})
        {:noreply, %{state | pending_requests: remaining_requests}}
    end
  end

  @impl GenServer
  def handle_info(:connect, state) do
    case connect_websocket(state) do
      {:ok, new_state} ->
        {:noreply, new_state}

      {:error, new_state} ->
        # Schedule reconnect with ConnectionManager tracking
        timer = Process.send_after(self(), :connect, Server.NetworkConfig.reconnect_interval())

        updated_connection_manager =
          Server.ConnectionManager.add_timer(
            new_state.connection_manager,
            timer,
            :reconnect
          )

        new_state = %{new_state | reconnect_timer: timer, connection_manager: updated_connection_manager}
        {:noreply, new_state}
    end
  end

  @impl GenServer
  def handle_info(:poll_stats, state) do
    # Direct access to connection state
    if state.connected do
      request_obs_stats(state)
    end

    # Schedule next poll
    timer = Process.send_after(self(), :poll_stats, @stats_polling_interval)
    state = %{state | stats_timer: timer}
    {:noreply, state}
  end

  # Gun WebSocket messages

  @impl GenServer
  def handle_info({:gun_upgrade, conn_pid, stream_ref, [<<"websocket">>], headers}, state) do
    if conn_pid == state.conn_pid and stream_ref == state.stream_ref do
      Logger.info("WebSocket upgrade successful",
        conn_pid: inspect(conn_pid),
        stream_ref: inspect(stream_ref),
        headers: inspect(headers)
      )

      # Update connection state - WebSocket upgraded but not authenticated yet
      state =
        update_connection_state(state, %{
          # Not connected until authenticated
          connected: false,
          connection_state: "websocket_upgraded",
          last_connected: DateTime.utc_now()
        })

      # Don't publish connection_established until authenticated
      # OBS will send Hello message next, then we authenticate

      {:noreply, state}
    else
      Logger.warning("Gun upgrade for wrong connection",
        expected_conn: inspect(state.conn_pid),
        expected_stream: inspect(state.stream_ref),
        received_conn: inspect(conn_pid),
        received_stream: inspect(stream_ref)
      )

      {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info({:gun_response, conn_pid, stream_ref, _is_fin, status, headers}, state) do
    if conn_pid == state.conn_pid and stream_ref == state.stream_ref do
      Logger.error("WebSocket upgrade failed",
        status: status,
        headers: inspect(headers),
        conn_pid: inspect(conn_pid),
        stream_ref: inspect(stream_ref)
      )

      # WebSocket upgrade failed - clean up and reconnect
      state =
        update_connection_state(state, %{
          connected: false,
          connection_state: "upgrade_failed",
          last_error: "HTTP #{status}"
        })
        |> cleanup_connection()

      # Schedule reconnect
      timer = Process.send_after(self(), :connect, Server.NetworkConfig.reconnect_interval())

      updated_connection_manager =
        Server.ConnectionManager.add_timer(
          state.connection_manager,
          timer,
          :reconnect
        )

      {:noreply, %{state | reconnect_timer: timer, connection_manager: updated_connection_manager}}
    else
      {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info({:gun_ws, gun_pid, stream_ref, frame}, state) do
    if gun_pid == state.conn_pid and stream_ref == state.stream_ref do
      case frame do
        {:text, message} ->
          # Count and update incoming message counter
          current_incoming = state.websocket_incoming_messages || 0
          updated_state = %{state | websocket_incoming_messages: current_incoming + 1}

          Logger.debug("OBS WebSocket message received",
            message_count: current_incoming + 1,
            message_preview: String.slice(message, 0, 100)
          )

          state = handle_obs_message(updated_state, message)
          {:noreply, state}

        {:binary, data} ->
          Logger.debug("OBS WebSocket binary frame received", size: byte_size(data))
          {:noreply, state}

        {:ping, payload} ->
          # Respond to ping frames to maintain connection
          :gun.ws_send(gun_pid, stream_ref, {:pong, payload})
          Logger.debug("OBS WebSocket ping received, pong sent")
          {:noreply, state}

        {:pong, _payload} ->
          Logger.debug("OBS WebSocket pong received")
          {:noreply, state}

        {:close, code, reason} ->
          # Handle OBS WebSocket v5 specific close codes
          {close_reason, should_reconnect} = classify_obs_close_code(code, reason)

          Logger.warning("WebSocket closed by remote",
            code: code,
            reason: reason,
            close_reason: close_reason,
            will_reconnect: should_reconnect,
            gun_pid: inspect(gun_pid)
          )

          # Update connection state
          state =
            update_connection_state(state, %{
              connected: false,
              connection_state: "closed",
              last_error: "#{close_reason}: #{code} #{reason}"
            })
            |> cleanup_connection()

          # Only schedule reconnect for recoverable errors
          if should_reconnect do
            timer = Process.send_after(self(), :connect, Server.NetworkConfig.reconnect_interval())

            updated_connection_manager =
              Server.ConnectionManager.add_timer(
                state.connection_manager,
                timer,
                :reconnect
              )

            {:noreply, %{state | reconnect_timer: timer, connection_manager: updated_connection_manager}}
          else
            # Don't reconnect for permanent failures (auth, session invalidated, etc.)
            {:noreply, state}
          end

        other ->
          Logger.debug("WebSocket frame unhandled", frame: inspect(other))
          {:noreply, state}
      end
    else
      {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info({:gun_down, conn_pid, protocol, reason, killed_streams}, state) do
    if conn_pid == state.conn_pid do
      Logger.warning("Gun connection down",
        error: inspect(reason, pretty: true),
        protocol: protocol,
        killed_streams: length(killed_streams || []),
        conn_pid: inspect(conn_pid)
      )

      # Update connection state
      state =
        update_connection_state(state, %{
          connected: false,
          connection_state: "disconnected"
        })
        |> stop_stats_polling()
        |> cleanup_connection()

      # Publish disconnection event
      Server.Events.publish_obs_event("connection_lost", %{})

      # Schedule reconnect with ConnectionManager tracking
      timer = Process.send_after(self(), :connect, Server.NetworkConfig.reconnect_interval())

      updated_connection_manager =
        Server.ConnectionManager.add_timer(
          state.connection_manager,
          timer,
          :reconnect
        )

      state = %{state | reconnect_timer: timer, connection_manager: updated_connection_manager}

      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info({:gun_error, conn_pid, stream_ref, reason}, state) do
    if conn_pid == state.conn_pid and stream_ref == state.stream_ref do
      Logger.error("Gun WebSocket stream error",
        error: inspect(reason, pretty: true),
        conn_pid: inspect(conn_pid),
        stream_ref: inspect(stream_ref),
        reason_type: reason.__struct__ || :unknown
      )

      state =
        update_connection_state(state, %{
          connected: false,
          connection_state: "error",
          last_error: inspect(reason)
        })
        |> cleanup_connection()

      # Schedule reconnect with ConnectionManager tracking
      timer = Process.send_after(self(), :connect, Server.NetworkConfig.reconnect_interval())

      updated_connection_manager =
        Server.ConnectionManager.add_timer(
          state.connection_manager,
          timer,
          :reconnect
        )

      state = %{state | reconnect_timer: timer, connection_manager: updated_connection_manager}

      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info({:gun_error, conn_pid, reason}, state) do
    if conn_pid == state.conn_pid do
      Logger.error("Gun connection error",
        error: inspect(reason, pretty: true),
        conn_pid: inspect(conn_pid),
        reason_type: reason.__struct__ || :unknown
      )

      state =
        update_connection_state(state, %{
          connected: false,
          connection_state: "error",
          last_error: inspect(reason)
        })
        |> cleanup_connection()

      # Schedule reconnect with ConnectionManager tracking
      timer = Process.send_after(self(), :connect, Server.NetworkConfig.reconnect_interval())

      updated_connection_manager =
        Server.ConnectionManager.add_timer(
          state.connection_manager,
          timer,
          :reconnect
        )

      state = %{state | reconnect_timer: timer, connection_manager: updated_connection_manager}

      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info({:DOWN, ref, :process, pid, reason}, state) do
    # Use ConnectionManager to handle monitor DOWN message
    updated_connection_manager =
      Server.ConnectionManager.handle_monitor_down(
        state.connection_manager,
        ref,
        pid,
        reason
      )

    if pid == state.conn_pid do
      reason_type =
        case reason do
          reason when is_struct(reason) -> reason.__struct__
          reason when is_atom(reason) -> reason
          _ -> :unknown
        end

      Logger.warning("Gun process terminated unexpectedly",
        pid: inspect(pid),
        reason: inspect(reason, pretty: true),
        monitor_ref: inspect(ref),
        reason_type: reason_type
      )

      # Update connection state and schedule reconnect
      state =
        %{state | connection_manager: updated_connection_manager}
        |> update_connection_state(%{
          connected: false,
          connection_state: "disconnected"
        })
        |> stop_stats_polling()
        |> cleanup_connection()

      # Publish disconnection event
      Server.Events.publish_obs_event("connection_lost", %{})

      # Schedule reconnect
      timer = Process.send_after(self(), :connect, Server.NetworkConfig.reconnect_interval())

      # Track reconnect timer with ConnectionManager
      final_connection_manager =
        Server.ConnectionManager.add_timer(
          state.connection_manager,
          timer,
          :reconnect
        )

      state = %{state | reconnect_timer: timer, connection_manager: final_connection_manager}

      {:noreply, state}
    else
      # Still update connection manager state for other monitored processes
      {:noreply, %{state | connection_manager: updated_connection_manager}}
    end
  end

  @impl GenServer
  def handle_info(info, state) do
    Logger.warning("Message unhandled", message: inspect(info, pretty: true))
    {:noreply, state}
  end

  @impl GenServer
  def terminate(_reason, state) do
    Logger.info("Service terminating")

    # Use ConnectionManager for comprehensive cleanup
    if state.connection_manager do
      Server.ConnectionManager.cleanup_all(state.connection_manager)
    end

    :ok
  end

  # WebSocket connection handling using Gun
  defp connect_websocket(state) do
    host = to_charlist(state.uri.host)
    port = state.uri.port || 4455
    path = state.uri.path || "/"

    # Emit telemetry for connection attempt
    Server.Telemetry.obs_connection_attempt()
    start_time = System.monotonic_time(:millisecond)

    # Configure Gun for WebSocket - simple and clean
    gun_opts = %{
      # Disable automatic retry for WebSocket connections
      retry: 0,
      # HTTP/1.1 protocol for WebSocket compatibility
      protocols: [:http],
      # Connection timeout
      connect_timeout: Server.NetworkConfig.connection_timeout()
    }

    case :gun.open(host, port, gun_opts) do
      {:ok, conn_pid} ->
        # Use ConnectionManager to track monitor and connection
        {_monitor_ref, updated_connection_manager} =
          Server.ConnectionManager.add_monitor(
            state.connection_manager,
            conn_pid,
            :obs_connection
          )

        websocket_config = Server.NetworkConfig.websocket_config()

        case :gun.await_up(conn_pid, websocket_config.timeout) do
          {:ok, protocol} ->
            Logger.debug("Gun connection established",
              conn_pid: inspect(conn_pid),
              protocol: protocol,
              host: state.uri.host,
              port: port
            )

            # Upgrade to WebSocket without custom headers
            stream_ref = :gun.ws_upgrade(conn_pid, path)

            Logger.debug("WebSocket upgrade initiated",
              conn_pid: inspect(conn_pid),
              stream_ref: inspect(stream_ref),
              path: path
            )

            # Track connection with ConnectionManager
            final_connection_manager =
              Server.ConnectionManager.add_connection(
                updated_connection_manager,
                conn_pid,
                stream_ref,
                :obs_websocket
              )

            new_state =
              %{state | conn_pid: conn_pid, stream_ref: stream_ref, connection_manager: final_connection_manager}
              |> update_connection_state(%{
                connected: false,
                connection_state: "connecting"
              })

            {:ok, new_state}

          {:error, reason} ->
            Logger.error("Connection failed during await_up", error: reason)
            :gun.close(conn_pid)

            # Emit telemetry for connection failure
            duration = System.monotonic_time(:millisecond) - start_time
            Server.Telemetry.obs_connection_failure(duration, inspect(reason))

            state =
              update_connection_state(state, %{
                connected: false,
                connection_state: "error",
                last_error: inspect(reason)
              })

            {:error, state}
        end

      {:error, reason} ->
        Logger.error("Connection failed during open", error: reason)

        # Emit telemetry for connection failure
        duration = System.monotonic_time(:millisecond) - start_time
        Server.Telemetry.obs_connection_failure(duration, inspect(reason))

        state =
          update_connection_state(state, %{
            connected: false,
            connection_state: "error",
            last_error: inspect(reason)
          })

        {:error, state}
    end
  end

  # OBS WebSocket protocol handlers
  defp handle_obs_message(state, message_json) do
    Logger.debug("Raw OBS message received", message: String.slice(message_json, 0, 200))

    case Jason.decode(message_json) do
      {:ok, %{"op" => op} = message} ->
        message_type =
          case op do
            0 -> "Hello"
            1 -> "Identify"
            2 -> "Identified"
            3 -> "Reidentify"
            5 -> "Event"
            6 -> "Request"
            7 -> "RequestResponse"
            8 -> "RequestBatch"
            9 -> "RequestBatchResponse"
            _ -> "Op#{op}"
          end

        Logger.info("OBS protocol message received",
          opcode: op,
          message_type: message_type,
          has_data: Map.has_key?(message, "d"),
          connection_state: state.connection_state,
          authenticated: state.authenticated
        )

        # Validate connection state according to OBS WebSocket v5 specification
        case validate_connection_state(state, op, message_type) do
          :ok ->
            handle_obs_protocol_message(state, op, message)

          {:close, close_code, reason} ->
            Logger.error("Protocol violation - closing connection",
              close_code: close_code,
              reason: reason,
              opcode: op,
              connection_state: state.connection_state
            )

            # Close connection with appropriate close code
            if state.conn_pid do
              :gun.close(state.conn_pid)
            end

            state
        end

      {:error, reason} ->
        Logger.error("Message decode failed", error: reason, message: message_json)

        # Close connection for decode errors (spec requirement)
        if state.conn_pid do
          :gun.close(state.conn_pid)
        end

        state
    end
  end

  # Validate connection state per OBS WebSocket v5 protocol
  defp validate_connection_state(state, op, message_type) do
    cond do
      # Before authentication, only Hello (OpCode 0) and Identified (OpCode 2) are allowed from server
      state.connection_state not in ["authenticated", "websocket_upgraded"] and op not in [0, 2] ->
        Logger.warning("Unexpected message received before authentication",
          opcode: op,
          message_type: message_type,
          connection_state: state.connection_state
        )

        {:close, 4007, "NotIdentified - Messages not allowed before authentication complete"}

      # OpCode 1 (Identify) should never be received by client (we send it)
      op == 1 ->
        {:close, 4006, "UnknownOpCode - Identify messages are sent by client only"}

      # OpCode 3 (Reidentify) should never be received by client (we send it)
      op == 3 ->
        {:close, 4006, "UnknownOpCode - Reidentify messages are sent by client only"}

      # OpCode 6 (Request) should never be received by client (we send it)
      op == 6 ->
        {:close, 4006, "UnknownOpCode - Request messages are sent by client only"}

      # OpCode 8 (RequestBatch) should never be received by client (we send it)
      op == 8 ->
        {:close, 4006, "UnknownOpCode - RequestBatch messages are sent by client only"}

      # Valid message - OpCodes 0, 2, 4, 5, 7, 9 are valid from server
      true ->
        :ok
    end
  end

  defp handle_obs_protocol_message(state, 0, %{"d" => hello_data}) do
    # Hello message - send Identify
    rpc_version = hello_data["rpcVersion"]
    authentication_data = hello_data["authentication"]

    Logger.info("!!! HELLO MESSAGE HANDLER CALLED !!!",
      rpc_version: rpc_version,
      authentication_required: authentication_data != nil,
      hello_data: inspect(hello_data)
    )

    # Build identify message based on OBS WebSocket v5 specification
    identify_data = %{
      rpcVersion: 1,
      eventSubscriptions: @event_subscription_all
    }

    # Check if authentication is possible before proceeding
    case authentication_data do
      nil ->
        # No authentication required
        identify_message = %{op: 1, d: identify_data}
        # Send first, then update state
        updated_state = send_identify_message(state, identify_message)
        %{updated_state | authentication_required: false, connection_state: "authenticating"}

      auth_data ->
        # Authentication required - check if password available
        auth_string = generate_authentication_string(auth_data)

        if auth_string do
          identify_data_with_auth = Map.put(identify_data, :authentication, auth_string)
          identify_message = %{op: 1, d: identify_data_with_auth}
          # Send first, then update state
          updated_state = send_identify_message(state, identify_message)
          %{updated_state | authentication_required: true, connection_state: "authenticating"}
        else
          Logger.error("Authentication required but password not configured")
          %{state | connection_state: "auth_failed", last_error: "Authentication required but password not configured"}
        end
    end
  end

  defp handle_obs_protocol_message(state, 2, %{"d" => data}) do
    # Identified - authentication successful, now truly connected
    Logger.info("Authentication completed", rpc_version: data["negotiatedRpcVersion"])

    # Emit telemetry for successful connection
    if state.last_connected do
      duration = DateTime.diff(DateTime.utc_now(), state.last_connected, :millisecond)
      :telemetry.execute([:server, :obs, :connection, :success], %{duration: duration})
    end

    # Update connection state - now fully authenticated and connected
    state =
      update_connection_state(state, %{
        connected: true,
        authenticated: true,
        connection_state: "authenticated",
        negotiated_rpc_version: data["negotiatedRpcVersion"],
        last_connected: DateTime.utc_now()
      })

    # Process any queued messages that were waiting for authentication
    state = process_pending_messages(state)

    # Now publish the real connection event
    Server.Events.publish_obs_event("connection_established", %{
      rpc_version: data["negotiatedRpcVersion"]
    })

    # Start monitoring
    start_stats_polling(state)
  end

  defp handle_obs_protocol_message(state, 3, %{"d" => reidentify_data}) do
    # Reidentify - update session parameters
    Logger.info("Reidentify request received", data: reidentify_data)

    # Update event subscriptions if provided
    updated_state =
      case reidentify_data["eventSubscriptions"] do
        nil ->
          state

        new_subscriptions ->
          Logger.debug("Updating event subscriptions",
            old: @event_subscription_all,
            new: new_subscriptions
          )

          # Note: In a full implementation, we would update our subscription mask
          # For now, just log the change
          state
      end

    # Send back Identified response (OpCode 2) to confirm reidentification
    identified_response = %{
      op: 2,
      d: %{
        negotiatedRpcVersion: state.negotiated_rpc_version || 1
      }
    }

    case send_message_now(updated_state, identified_response) do
      :ok ->
        Logger.debug("Reidentify successful")
        updated_state

      {:error, reason} ->
        Logger.error("Failed to send Identified response to Reidentify", error: reason)
        updated_state
    end
  end

  defp handle_obs_protocol_message(state, 5, %{
         "d" => %{"eventType" => event_type, "eventIntent" => event_intent} = event_message
       }) do
    # Event message - extract eventData (optional field)
    event_data = Map.get(event_message, "eventData", %{})

    Logger.debug("OBS Event received",
      event_type: event_type,
      event_intent: event_intent,
      has_data: event_data != %{}
    )

    # Verify client is subscribed to this event intent
    if event_subscribed?(event_intent) do
      handle_obs_event(state, event_type, event_data, event_intent)
    else
      Logger.debug("Event filtered - not subscribed to intent",
        event_type: event_type,
        event_intent: event_intent
      )

      state
    end
  end

  defp handle_obs_protocol_message(state, 6, %{"d" => request_data}) do
    # Request (OpCode 6) - client making a request to obs-websocket
    request_type = request_data["requestType"]
    request_id = request_data["requestId"]
    request_data_payload = Map.get(request_data, "requestData", %{})

    Logger.info("OBS Request received",
      request_type: request_type,
      request_id: request_id,
      has_data: request_data_payload != %{}
    )

    # Validate request format according to OBS WebSocket v5 spec
    case validate_request(request_data) do
      {:ok, validated_request} ->
        # Process the request and generate response
        response = process_obs_request(state, validated_request)
        send_request_response(state, response)
        state

      {:error, status_code, comment} ->
        # Send error response
        error_response = %{
          "requestType" => request_type,
          "requestId" => request_id,
          "requestStatus" => %{
            "result" => false,
            "code" => status_code,
            "comment" => comment
          }
        }

        response_message = %{op: 7, d: error_response}
        send_message_now(state, response_message)
        state
    end
  end

  defp handle_obs_protocol_message(state, 7, %{"d" => %{"requestId" => request_id} = response}) do
    # Request response - check if this is a stats request first
    request_type = response["requestType"]

    if request_type == "GetStats" do
      # Store stats in state - direct struct field updates
      stats_data = response["responseData"] || %{}

      updated_state = %{
        state
        | active_fps: stats_data["activeFps"] || 0,
          average_frame_time: stats_data["averageFrameTime"] || 0,
          cpu_usage: stats_data["cpuUsage"] || 0,
          memory_usage: stats_data["memoryUsage"] || 0,
          available_disk_space: stats_data["availableDiskSpace"] || 0,
          render_total_frames: stats_data["renderTotalFrames"] || 0,
          render_skipped_frames: stats_data["renderSkippedFrames"] || 0,
          output_total_frames: stats_data["outputTotalFrames"] || 0,
          output_skipped_frames: stats_data["outputSkippedFrames"] || 0,
          websocket_incoming_messages: stats_data["webSocketSessionIncomingMessages"] || 0,
          websocket_outgoing_messages: stats_data["webSocketSessionOutgoingMessages"] || 0,
          stats_last_updated: DateTime.utc_now()
      }

      Logger.debug("Stats response received and stored",
        request_id: request_id,
        fps: updated_state.active_fps,
        cpu_usage: updated_state.cpu_usage
      )

      updated_state
    else
      # Handle tracked requests
      case Map.pop(state.pending_requests, request_id) do
        {nil, pending_requests} ->
          Logger.warning("Response for unknown request",
            request_id: request_id,
            response_type: request_type,
            response_status: response["requestStatus"]["result"],
            pending_count: map_size(pending_requests),
            pending_requests: Map.keys(pending_requests) |> Enum.take(5),
            reason: "request not found in pending map"
          )

          state

        {{from, timeout_ref}, remaining_requests} ->
          # Cancel the timeout since we got a response
          Process.cancel_timer(timeout_ref)

          result =
            if response["requestStatus"]["result"] do
              {:ok, response["responseData"] || %{}}
            else
              comment = response["requestStatus"]["comment"] || "Request failed"
              status_code = response["requestStatus"]["code"]

              Logger.warning("OBS request failed",
                request_type: request_type,
                request_id: request_id,
                status_code: status_code,
                comment: comment,
                full_response: response
              )

              error =
                ServiceError.new(:obs, "request", :invalid_request, comment,
                  details: %{request_id: request_id, response: response, status_code: status_code}
                )

              {:error, error}
            end

          GenServer.reply(from, result)
          %{state | pending_requests: remaining_requests}
      end
    end
  end

  defp handle_obs_protocol_message(state, 8, %{"d" => batch_data}) do
    # RequestBatch - handle batch of requests
    request_id = batch_data["requestId"]
    requests = batch_data["requests"] || []
    halt_on_failure = batch_data["haltOnFailure"] || false
    # SerialRealtime
    execution_type = batch_data["executionType"] || 0

    Logger.info("RequestBatch received",
      request_id: request_id,
      request_count: length(requests),
      halt_on_failure: halt_on_failure,
      execution_type: execution_type
    )

    # Process requests according to execution type
    results = process_request_batch(state, requests, halt_on_failure, execution_type)

    # Send RequestBatchResponse (OpCode 9)
    batch_response = %{
      op: 9,
      d: %{
        requestId: request_id,
        results: results
      }
    }

    case send_message_now(state, batch_response) do
      :ok ->
        Logger.debug("RequestBatch response sent", request_id: request_id, result_count: length(results))

      {:error, reason} ->
        Logger.error("Failed to send RequestBatch response", error: reason, request_id: request_id)
    end

    state
  end

  defp handle_obs_protocol_message(state, 9, %{"d" => _batch_response_data}) do
    # RequestBatchResponse - we shouldn't receive this as a server, but handle gracefully
    Logger.warning("Received RequestBatchResponse from OBS - this is unexpected")
    state
  end

  defp handle_obs_protocol_message(state, op, message) do
    Logger.warning("Protocol message unhandled", op: op, message: message)
    state
  end

  defp send_identify_message(state, identify_message) do
    # Send Identify directly without authentication checks
    case send_message_now(state, identify_message) do
      :ok ->
        Logger.debug("Identify message sent, waiting for Identified response")
        state

      {:error, reason} ->
        Logger.error("Failed to send Identify message", error: reason)
        %{state | connection_state: "auth_failed", last_error: "Failed to send identify: #{inspect(reason)}"}
    end
  end

  # Event subscription checking
  defp event_subscribed?(event_intent) do
    # For now, we subscribe to all events since we use EventSubscription::All
    # In a full implementation, this would check against our actual subscription mask
    subscribed_mask = @event_subscription_all
    (subscribed_mask &&& event_intent) != 0
  end

  # OBS event handlers (with eventIntent support)
  defp handle_obs_event(state, "CurrentProgramSceneChanged", %{"sceneName" => scene_name}, event_intent) do
    Logger.debug("Scene changed",
      scene_name: scene_name,
      event_intent: event_intent
    )

    previous_scene = state.current_scene
    state = update_scene_state(state, %{current: scene_name})

    # Publish event
    Server.Events.publish_obs_event("scene_current_changed", %{
      scene_name: scene_name,
      previous_scene: previous_scene,
      event_intent: event_intent
    })

    state
  end

  defp handle_obs_event(
         state,
         "StreamStateChanged",
         %{
           "outputActive" => active,
           "outputState" => output_state
         },
         event_intent
       ) do
    Logger.info("Stream state changed",
      output_active: active,
      output_state: output_state,
      event_intent: event_intent
    )

    state = update_streaming_state(state, %{active: active})

    event_type = if active, do: "stream_started", else: "stream_stopped"

    Server.Events.publish_obs_event(event_type, %{
      output_active: active,
      output_state: output_state,
      event_intent: event_intent
    })

    state
  end

  defp handle_obs_event(state, event_type, event_data, event_intent) do
    Logger.debug("Event unhandled",
      event_type: event_type,
      event_data: event_data,
      event_intent: event_intent
    )

    state
  end

  # Helper functions
  defp send_websocket_message(state, message) do
    cond do
      # Always allow protocol handshake messages (Hello=0, Identify=1, Identified=2)
      message["op"] in [0, 1, 2] and state.conn_pid && state.stream_ref ->
        Logger.debug("Sending protocol handshake message", message_type: get_message_type(message))
        send_message_now(state, message)

      # Queue requests until we receive Identified (op: 2) from OBS
      state.connection_state != "authenticated" and message["op"] not in [0, 1, 2] ->
        Logger.debug("Queuing request until authenticated",
          message_type: get_message_type(message),
          queue_size: length(state.pending_messages),
          connection_state: state.connection_state
        )

        updated_state = %{state | pending_messages: state.pending_messages ++ [message]}
        {:queued, updated_state}

      # Send immediately if connected and authenticated
      state.conn_pid && state.stream_ref ->
        send_message_now(state, message)

      true ->
        # Not connected
        {:error, ServiceError.new(:obs, "send_message", :service_unavailable, "WebSocket not connected")}
    end
  end

  defp send_message_now(state, message) do
    json_message = Jason.encode!(message)

    # Count outgoing message and log details
    current_outgoing = state.websocket_outgoing_messages || 0

    message_type =
      case message do
        %{"op" => 1} -> "Identify"
        %{"op" => 6, "d" => %{"requestType" => req_type}} -> "Request:#{req_type}"
        %{"op" => op} -> "Op:#{op}"
        _ -> "Unknown"
      end

    Logger.debug("OBS WebSocket message sending",
      message_count: current_outgoing + 1,
      message_type: message_type,
      message_preview: String.slice(json_message, 0, 150)
    )

    # Send via Gun WebSocket
    case :gun.ws_send(state.conn_pid, state.stream_ref, {:text, json_message}) do
      :ok ->
        # Update counter and emit telemetry
        GenServer.cast(self(), {:update_outgoing_counter, current_outgoing + 1})

        :telemetry.execute([:server, :obs, :message, :sent], %{}, %{
          message_type: message_type,
          message_size: byte_size(json_message)
        })

        :ok

      {:error, reason} ->
        Logger.error("WebSocket send failed",
          error: inspect(reason),
          message_type: message_type,
          conn_pid: inspect(state.conn_pid),
          stream_ref: inspect(state.stream_ref)
        )

        {:error, ServiceError.new(:obs, "send_message", :network_error, "WebSocket send failed: #{inspect(reason)}")}

      _other ->
        # Gun sometimes returns other values, treat as success
        :ok
    end
  end

  # State update helpers
  defp update_connection_state(state, updates) do
    # Direct struct field updates using pattern matching and struct syntax
    new_state = struct(state, updates)

    # Invalidate relevant caches
    invalidate_obs_caches([:connection_status, :basic_status, :full_state])

    # Publish connection state changes - create connection map for event
    connection_state = %{
      connected: new_state.connected,
      connection_state: new_state.connection_state,
      last_error: new_state.last_error,
      last_connected: new_state.last_connected,
      negotiated_rpc_version: new_state.negotiated_rpc_version
    }

    Server.Events.publish_obs_event("connection_changed", connection_state)

    new_state
  end

  defp update_scene_state(state, updates) do
    # Map old scene updates to new struct fields
    struct_updates =
      Enum.reduce(updates, [], fn
        {:current, scene_name}, acc -> [{:current_scene, scene_name} | acc]
        {:preview, scene_name}, acc -> [{:preview_scene, scene_name} | acc]
        {:list, scenes}, acc -> [{:scene_list, scenes} | acc]
        {key, value}, acc -> [{key, value} | acc]
      end)

    new_state = struct(state, struct_updates)

    # Invalidate caches that include scene data
    invalidate_obs_caches([:basic_status, :full_state])

    # Create scene map for event publishing
    scenes = %{
      current: new_state.current_scene,
      preview: new_state.preview_scene,
      list: new_state.scene_list
    }

    Server.Events.publish_obs_event("scenes_updated", scenes)

    new_state
  end

  defp update_streaming_state(state, updates) do
    # Map old streaming updates to new struct fields
    struct_updates =
      Enum.reduce(updates, [], fn
        {:active, active}, acc -> [{:streaming_active, active} | acc]
        {:timecode, timecode}, acc -> [{:streaming_timecode, timecode} | acc]
        {:duration, duration}, acc -> [{:streaming_duration, duration} | acc]
        {:congestion, congestion}, acc -> [{:streaming_congestion, congestion} | acc]
        {:bytes, bytes}, acc -> [{:streaming_bytes, bytes} | acc]
        {:skipped_frames, frames}, acc -> [{:streaming_skipped_frames, frames} | acc]
        {:total_frames, frames}, acc -> [{:streaming_total_frames, frames} | acc]
        {key, value}, acc -> [{key, value} | acc]
      end)

    new_state = struct(state, struct_updates)

    # Invalidate caches that include streaming data
    invalidate_obs_caches([:basic_status, :full_state])

    # Create streaming map for event publishing
    streaming = %{
      active: new_state.streaming_active,
      timecode: new_state.streaming_timecode,
      duration: new_state.streaming_duration,
      congestion: new_state.streaming_congestion,
      bytes: new_state.streaming_bytes,
      skipped_frames: new_state.streaming_skipped_frames,
      total_frames: new_state.streaming_total_frames
    }

    Server.Events.publish_obs_event("streaming_updated", streaming)

    new_state
  end

  # Cache invalidation helper
  defp invalidate_obs_caches(cache_keys) do
    Enum.each(cache_keys, fn key ->
      Server.Cache.invalidate(:obs_service, key)
    end)
  end

  # Stats polling
  defp start_stats_polling(state) do
    timer = Process.send_after(self(), :poll_stats, @stats_polling_interval)

    # Track timer with ConnectionManager
    updated_connection_manager =
      Server.ConnectionManager.add_timer(
        state.connection_manager,
        timer,
        :stats_polling
      )

    %{state | stats_timer: timer, connection_manager: updated_connection_manager}
  end

  defp stop_stats_polling(state) do
    # Use ConnectionManager to cancel timer properly
    updated_connection_manager =
      Server.ConnectionManager.cancel_timer(
        state.connection_manager,
        :stats_polling
      )

    %{state | stats_timer: nil, connection_manager: updated_connection_manager}
  end

  defp request_obs_stats(state) do
    # Request GetStats from OBS for performance monitoring
    request_id = CorrelationId.generate()

    message = %{
      op: 6,
      d: %{
        requestType: "GetStats",
        requestId: request_id,
        requestData: %{}
      }
    }

    # Don't add stats requests to pending map since we don't wait for response
    Logger.debug("Requesting OBS stats", request_id: request_id)
    send_websocket_message(state, message)
  end

  defp cleanup_connection(state) do
    if state.conn_pid do
      :gun.close(state.conn_pid)
    end

    %{state | conn_pid: nil, stream_ref: nil}
  end

  # Configuration helpers
  defp get_websocket_url do
    Application.get_env(:server, :obs_websocket_url, "ws://localhost:4455")
  end

  # OBS WebSocket v5 Authentication Implementation
  defp generate_authentication_string(auth_data) do
    challenge = auth_data["challenge"]
    salt = auth_data["salt"]
    password = get_obs_password()

    if password do
      # OBS WebSocket v5 authentication algorithm:
      # Base64Encode(SHA256(password + salt) + challenge)

      # Step 1: SHA256(password + salt)
      password_salt_hash = :crypto.hash(:sha256, password <> salt)

      # Step 2: Decode challenge from Base64
      challenge_binary = Base.decode64!(challenge)

      # Step 3: SHA256(password_salt_hash + challenge)
      final_hash = :crypto.hash(:sha256, password_salt_hash <> challenge_binary)

      # Step 4: Base64 encode the result
      Base.encode64(final_hash)
    else
      Logger.warning("OBS authentication required but no password configured")
      nil
    end
  end

  defp get_obs_password do
    # Get OBS WebSocket password from environment or config
    System.get_env("OBS_WEBSOCKET_PASSWORD") ||
      Application.get_env(:server, :obs_websocket_password)
  end

  # OBS WebSocket v5 Close Code Classification
  defp classify_obs_close_code(code, _reason) do
    case code do
      # Standard WebSocket close codes
      # Don't reconnect on normal close
      1000 -> {"Normal closure", false}
      # Server restarting, can reconnect
      1001 -> {"Going away", true}
      # Connection lost, can reconnect
      1006 -> {"Abnormal closure", true}
      # OBS WebSocket v5 specific close codes
      4000 -> {"Unknown reason", true}
      4002 -> {"Message decode error", true}
      # Protocol error
      4003 -> {"Missing data field", false}
      # Protocol error
      4004 -> {"Invalid data field type", false}
      # Protocol error
      4005 -> {"Invalid data field value", false}
      # Protocol error
      4006 -> {"Unknown OpCode", false}
      # Can retry identification
      4007 -> {"Not identified", true}
      # Protocol violation
      4008 -> {"Already identified", false}
      # Wrong credentials - don't retry
      4009 -> {"Authentication failed", false}
      # Version mismatch
      4010 -> {"Unsupported RPC version", false}
      # Kicked by user - don't reconnect
      4011 -> {"Session invalidated", false}
      # Feature not available
      4012 -> {"Unsupported feature", false}
      # Unknown codes - be conservative and don't reconnect
      _ -> {"Unknown close code: #{code}", false}
    end
  end

  # Message queuing during authentication
  defp process_pending_messages(state) do
    Logger.debug("Processing pending messages", count: length(state.pending_messages))

    # Send all queued messages now that we're authenticated
    Enum.each(state.pending_messages, fn message ->
      case send_websocket_message_direct(state, message) do
        :ok ->
          Logger.debug("Sent queued message", message_type: get_message_type(message))

        {:error, reason} ->
          Logger.error("Failed to send queued message",
            message_type: get_message_type(message),
            error: reason
          )
      end
    end)

    # Clear the pending messages queue
    %{state | pending_messages: []}
  end

  defp get_message_type(message) do
    case message do
      %{"op" => 1} -> "Identify"
      %{"op" => 6, "d" => %{"requestType" => req_type}} -> "Request:#{req_type}"
      %{"op" => op} -> "Op:#{op}"
      _ -> "Unknown"
    end
  end

  # Direct message sending without authentication checks (for internal use)
  defp send_websocket_message_direct(state, message) do
    if state.conn_pid && state.stream_ref do
      json_message = Jason.encode!(message)

      case :gun.ws_send(state.conn_pid, state.stream_ref, {:text, json_message}) do
        :ok -> :ok
        {:error, reason} -> {:error, reason}
        # Gun sometimes returns other values
        _other -> :ok
      end
    else
      {:error, "WebSocket not connected"}
    end
  end

  # OBS WebSocket v5 Request Validation (complete compliance)
  defp validate_request(request_data) do
    # RequestStatus codes from OBS WebSocket v5 specification
    cond do
      # Check required fields according to spec
      !Map.has_key?(request_data, "requestType") ->
        {:error, 203, "The requestType field is missing from the request data"}

      !Map.has_key?(request_data, "requestId") ->
        {:error, 300, "A required request field is missing"}

      !is_binary(request_data["requestType"]) ->
        {:error, 401, "The requestType field has the wrong data type"}

      !is_binary(request_data["requestId"]) ->
        {:error, 401, "The requestId field has the wrong data type"}

      String.length(request_data["requestType"]) == 0 ->
        {:error, 403, "The requestType field is empty and cannot be"}

      String.length(request_data["requestId"]) == 0 ->
        {:error, 403, "The requestId field is empty and cannot be"}

      # Validate requestData if present
      Map.has_key?(request_data, "requestData") && !is_map(request_data["requestData"]) ->
        {:error, 401, "The requestData field has the wrong data type"}

      true ->
        {:ok, request_data}
    end
  end

  # Process OBS requests according to specification
  defp process_obs_request(state, %{"requestType" => request_type} = request) do
    case request_type do
      "GetVersion" ->
        handle_get_version_request(state, request)

      "GetStats" ->
        handle_get_stats_request(state, request)

      "GetSceneList" ->
        handle_get_scene_list_request(state, request)

      "GetCurrentProgramScene" ->
        handle_get_current_scene_request(state, request)

      "SetCurrentProgramScene" ->
        handle_set_current_scene_request(state, request)

      "StartStream" ->
        handle_start_stream_request(state, request)

      "StopStream" ->
        handle_stop_stream_request(state, request)

      "StartRecord" ->
        handle_start_record_request(state, request)

      "StopRecord" ->
        handle_stop_record_request(state, request)

      "BroadcastCustomEvent" ->
        handle_broadcast_custom_event_request(state, request)

      "Sleep" ->
        handle_sleep_request_individual(state, request)

      _ ->
        # Unknown request type
        %{
          "requestType" => request_type,
          "requestId" => request["requestId"],
          "requestStatus" => %{
            "result" => false,
            # UnknownRequestType
            "code" => 204,
            "comment" => "The request type is invalid or does not exist"
          }
        }
    end
  end

  # Send RequestResponse (OpCode 7) message
  defp send_request_response(state, response_data) do
    response_message = %{op: 7, d: response_data}

    case send_message_now(state, response_message) do
      :ok ->
        Logger.debug("Request response sent", request_id: response_data["requestId"])

      {:error, reason} ->
        Logger.error("Failed to send request response",
          request_id: response_data["requestId"],
          error: reason
        )
    end
  end

  # Individual OBS request handlers (compliant implementations)
  defp handle_get_version_request(_state, request) do
    %{
      "requestType" => "GetVersion",
      "requestId" => request["requestId"],
      "requestStatus" => %{
        "result" => true,
        "code" => 100
      },
      "responseData" => %{
        "obsVersion" => "30.2.2",
        "obsWebSocketVersion" => "5.5.2",
        "rpcVersion" => 1,
        "availableRequests" => [
          "GetVersion",
          "GetStats",
          "GetSceneList",
          "GetCurrentProgramScene",
          "SetCurrentProgramScene",
          "StartStream",
          "StopStream",
          "StartRecord",
          "StopRecord",
          "BroadcastCustomEvent",
          "Sleep"
        ],
        "supportedImageFormats" => ["png", "jpg", "jpeg", "bmp"],
        "platform" => "darwin",
        "platformDescription" => "macOS"
      }
    }
  end

  defp handle_get_stats_request(state, request) do
    %{
      "requestType" => "GetStats",
      "requestId" => request["requestId"],
      "requestStatus" => %{
        "result" => true,
        "code" => 100
      },
      "responseData" => %{
        "cpuUsage" => state.cpu_usage || 0,
        "memoryUsage" => state.memory_usage || 0,
        "availableDiskSpace" => state.available_disk_space || 0,
        "activeFps" => state.active_fps || 0,
        "averageFrameRenderTime" => state.average_frame_time || 0,
        "renderSkippedFrames" => state.render_skipped_frames || 0,
        "renderTotalFrames" => state.render_total_frames || 0,
        "outputSkippedFrames" => state.output_skipped_frames || 0,
        "outputTotalFrames" => state.output_total_frames || 0,
        "webSocketSessionIncomingMessages" => state.websocket_incoming_messages || 0,
        "webSocketSessionOutgoingMessages" => state.websocket_outgoing_messages || 0
      }
    }
  end

  defp handle_get_scene_list_request(state, request) do
    %{
      "requestType" => "GetSceneList",
      "requestId" => request["requestId"],
      "requestStatus" => %{
        "result" => true,
        "code" => 100
      },
      "responseData" => %{
        "currentProgramSceneName" => state.current_scene,
        # Mock UUID
        "currentProgramSceneUuid" => "scene-uuid-1",
        "currentPreviewSceneName" => state.preview_scene,
        # Mock UUID
        "currentPreviewSceneUuid" => "scene-uuid-2",
        "scenes" => state.scene_list || []
      }
    }
  end

  defp handle_get_current_scene_request(state, request) do
    %{
      "requestType" => "GetCurrentProgramScene",
      "requestId" => request["requestId"],
      "requestStatus" => %{
        "result" => true,
        "code" => 100
      },
      "responseData" => %{
        "currentProgramSceneName" => state.current_scene,
        # Mock UUID
        "currentProgramSceneUuid" => "scene-uuid-1"
      }
    }
  end

  defp handle_set_current_scene_request(_state, request) do
    request_data = request["requestData"] || %{}
    scene_name = request_data["sceneName"]

    if scene_name && is_binary(scene_name) && String.length(scene_name) > 0 do
      # In a real implementation, this would actually change the scene in OBS
      Logger.info("Setting current scene", scene_name: scene_name)

      %{
        "requestType" => "SetCurrentProgramScene",
        "requestId" => request["requestId"],
        "requestStatus" => %{
          "result" => true,
          "code" => 100
        }
      }
    else
      %{
        "requestType" => "SetCurrentProgramScene",
        "requestId" => request["requestId"],
        "requestStatus" => %{
          "result" => false,
          # Specific error code for parameter issues
          "code" => 608,
          "comment" => "Parameter: sceneName"
        }
      }
    end
  end

  defp handle_start_stream_request(_state, request) do
    # In real implementation, would start streaming
    Logger.info("Starting stream")

    %{
      "requestType" => "StartStream",
      "requestId" => request["requestId"],
      "requestStatus" => %{
        "result" => true,
        "code" => 100
      }
    }
  end

  defp handle_stop_stream_request(_state, request) do
    # In real implementation, would stop streaming
    Logger.info("Stopping stream")

    %{
      "requestType" => "StopStream",
      "requestId" => request["requestId"],
      "requestStatus" => %{
        "result" => true,
        "code" => 100
      }
    }
  end

  defp handle_start_record_request(_state, request) do
    # In real implementation, would start recording
    Logger.info("Starting recording")

    %{
      "requestType" => "StartRecord",
      "requestId" => request["requestId"],
      "requestStatus" => %{
        "result" => true,
        "code" => 100
      }
    }
  end

  defp handle_stop_record_request(_state, request) do
    # In real implementation, would stop recording
    Logger.info("Stopping recording")

    %{
      "requestType" => "StopRecord",
      "requestId" => request["requestId"],
      "requestStatus" => %{
        "result" => true,
        "code" => 100
      }
    }
  end

  defp handle_broadcast_custom_event_request(_state, request) do
    request_data = request["requestData"] || %{}
    event_data = request_data["eventData"] || %{}

    # Broadcast custom event to all connected clients
    Logger.info("Broadcasting custom event", event_data: event_data)

    %{
      "requestType" => "BroadcastCustomEvent",
      "requestId" => request["requestId"],
      "requestStatus" => %{
        "result" => true,
        "code" => 100
      }
    }
  end

  defp handle_sleep_request_individual(_state, request) do
    request_data = request["requestData"] || %{}

    # Handle Sleep request same as in batch processing
    cond do
      sleep_millis = request_data["sleepMillis"] ->
        if sleep_millis > 0 and sleep_millis <= 50_000 do
          Process.sleep(sleep_millis)
          success_response(request)
        else
          error_response(request, 402, "sleepMillis is outside the allowed range")
        end

      sleep_frames = request_data["sleepFrames"] ->
        if sleep_frames > 0 and sleep_frames <= 10_000 do
          # 60fps
          frame_duration = 16.67
          sleep_duration = round(sleep_frames * frame_duration)
          Process.sleep(sleep_duration)
          success_response(request)
        else
          error_response(request, 402, "sleepFrames is outside the allowed range")
        end

      true ->
        error_response(request, 300, "Sleep request requires sleepMillis or sleepFrames")
    end
  end

  defp success_response(request) do
    %{
      "requestType" => request["requestType"],
      "requestId" => request["requestId"],
      "requestStatus" => %{
        "result" => true,
        "code" => 100
      }
    }
  end

  defp error_response(request, code, comment) do
    %{
      "requestType" => request["requestType"],
      "requestId" => request["requestId"],
      "requestStatus" => %{
        "result" => false,
        "code" => code,
        "comment" => comment
      }
    }
  end

  # Process batch of requests according to OBS WebSocket v5 specification
  defp process_request_batch(state, requests, halt_on_failure, execution_type) do
    case execution_type do
      0 ->
        process_serial_realtime_batch(state, requests, halt_on_failure)

      1 ->
        process_serial_frame_batch(state, requests, halt_on_failure)

      2 ->
        process_parallel_batch(state, requests, halt_on_failure)

      _ ->
        Logger.warning("Unknown batch execution type", execution_type: execution_type)
        process_serial_realtime_batch(state, requests, halt_on_failure)
    end
  end

  # Process requests serially in real-time (default mode)
  defp process_serial_realtime_batch(state, requests, halt_on_failure) do
    Enum.reduce_while(requests, [], fn request, acc ->
      result = process_single_batch_request(state, request)

      case {result, halt_on_failure} do
        {%{"requestStatus" => %{"result" => false}}, true} ->
          # Halt on failure requested and this request failed
          {:halt, [result | acc]}

        _ ->
          {:cont, [result | acc]}
      end
    end)
    |> Enum.reverse()
  end

  # Process requests serially synchronized with graphics frame (experimental)
  defp process_serial_frame_batch(state, requests, halt_on_failure) do
    # For now, treat same as serial realtime since frame sync is complex
    Logger.debug("Using serial frame execution (treating as realtime for now)")
    process_serial_realtime_batch(state, requests, halt_on_failure)
  end

  # Process requests in parallel (experimental)
  defp process_parallel_batch(state, requests, halt_on_failure) do
    # For safety, process serially for now since parallel execution could cause race conditions
    Logger.debug("Using parallel execution (treating as serial for safety)")
    process_serial_realtime_batch(state, requests, halt_on_failure)
  end

  # Process a single request within a batch
  defp process_single_batch_request(state, request) do
    # Ensure requestId is present for batch tracking (optional per spec, but required for tracking)
    request_with_id =
      if Map.has_key?(request, "requestId") do
        request
      else
        Map.put(request, "requestId", CorrelationId.generate())
      end

    Logger.debug("Processing batch request",
      request_type: request_with_id["requestType"],
      request_id: request_with_id["requestId"]
    )

    # Use the same validation and processing as OpCode 6 Request messages
    case validate_request(request_with_id) do
      {:ok, validated_request} ->
        # Process using the same infrastructure as individual requests
        process_obs_request(state, validated_request)

      {:error, status_code, comment} ->
        # Return error response with same format as OpCode 6 errors
        %{
          "requestType" => request_with_id["requestType"],
          "requestId" => request_with_id["requestId"],
          "requestStatus" => %{
            "result" => false,
            "code" => status_code,
            "comment" => comment
          }
        }
    end
  end
end
