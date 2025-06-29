defmodule Server.Services.OBS do
  @moduledoc """
  OBS WebSocket integration service using Fresh WebSocket client.
  
  Provides comprehensive OBS WebSocket v5 functionality:
  - Connection management with auto-reconnect
  - State management for scenes, streaming, recording, etc.
  - Event publishing via PubSub
  - Performance monitoring with stats polling
  - Full OBS WebSocket v5 protocol support
  """

  use Fresh
  require Logger

  # OBS WebSocket protocol constants
  @event_subscription_all 0x1FF  # Subscribe to all events
  @stats_polling_interval 5_000  # 5 seconds

  defstruct [
    :stats_timer,
    :pending_requests,
    state: %{
      connection: %{
        connected: false,
        connection_state: "disconnected",
        last_error: nil,
        last_connected: nil,
        negotiated_rpc_version: nil
      },
      scenes: %{
        current: nil,
        preview: nil,
        list: []
      },
      streaming: %{
        active: false,
        timecode: "00:00:00",
        duration: 0,
        congestion: 0,
        bytes: 0,
        skipped_frames: 0,
        total_frames: 0
      },
      recording: %{
        active: false,
        paused: false,
        timecode: "00:00:00", 
        duration: 0,
        bytes: 0
      },
      studio_mode: %{
        enabled: false
      },
      virtual_cam: %{
        active: false
      },
      replay_buffer: %{
        active: false
      }
    }
  ]

  # Client API
  def start_link(opts \\ []) do
    url = Keyword.get(opts, :url, get_websocket_url())
    
    state = %__MODULE__{
      pending_requests: %{}
    }

    Logger.info("Starting OBS WebSocket service", url: url)
    
    Fresh.start_link(url, state, [], name: __MODULE__)
  end

  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end

  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end

  def start_streaming do
    GenServer.call(__MODULE__, {:obs_call, "StartStream", %{}})
  end

  def stop_streaming do
    GenServer.call(__MODULE__, {:obs_call, "StopStream", %{}})
  end

  def start_recording do
    GenServer.call(__MODULE__, {:obs_call, "StartRecord", %{}})
  end

  def stop_recording do
    GenServer.call(__MODULE__, {:obs_call, "StopRecord", %{}})
  end

  def pause_recording do
    GenServer.call(__MODULE__, {:obs_call, "PauseRecord", %{}})
  end

  def resume_recording do
    GenServer.call(__MODULE__, {:obs_call, "ResumeRecord", %{}})
  end

  def set_current_scene(scene_name) do
    GenServer.call(__MODULE__, {:obs_call, "SetCurrentProgramScene", %{sceneName: scene_name}})
  end

  def set_preview_scene(scene_name) do
    GenServer.call(__MODULE__, {:obs_call, "SetCurrentPreviewScene", %{sceneName: scene_name}})
  end

  def set_studio_mode_enabled(enabled) do
    GenServer.call(__MODULE__, {:obs_call, "SetStudioModeEnabled", %{studioModeEnabled: enabled}})
  end

  def trigger_studio_mode_transition do
    GenServer.call(__MODULE__, {:obs_call, "TriggerStudioModeTransition", %{}})
  end

  def start_virtual_cam do
    GenServer.call(__MODULE__, {:obs_call, "StartVirtualCam", %{}})
  end

  def stop_virtual_cam do
    GenServer.call(__MODULE__, {:obs_call, "StopVirtualCam", %{}})
  end

  def start_replay_buffer do
    GenServer.call(__MODULE__, {:obs_call, "StartReplayBuffer", %{}})
  end

  def stop_replay_buffer do
    GenServer.call(__MODULE__, {:obs_call, "StopReplayBuffer", %{}})
  end

  def save_replay_buffer do
    GenServer.call(__MODULE__, {:obs_call, "SaveReplayBuffer", %{}})
  end

  # Fresh callbacks
  @impl Fresh
  def handle_connect(_status, _headers, state) do
    Logger.info("OBS WebSocket connected")
    
    # Update connection state
    state = update_connection_state(state, %{
      connected: true,
      connection_state: "connected",
      last_connected: DateTime.utc_now()
    })

    # Publish connection event
    Server.Events.publish_obs_event("connection_established", %{})

    {:ok, state}
  end

  @impl Fresh
  def handle_disconnect(_code, _reason, state) do
    Logger.warning("OBS WebSocket disconnected")
    
    # Update connection state
    state = update_connection_state(state, %{
      connected: false,
      connection_state: "disconnected"
    })
    |> stop_stats_polling()

    # Publish disconnection event
    Server.Events.publish_obs_event("connection_lost", %{})

    {:ok, state}
  end

  @impl Fresh
  def handle_in({:text, message}, state) do
    state = handle_obs_message(state, message)
    {:ok, state}
  end

  @impl Fresh
  def handle_in(frame, state) do
    Logger.debug("Unhandled WebSocket frame", frame: frame)
    {:ok, state}
  end

  @impl Fresh
  def handle_error(error, state) do
    Logger.error("OBS WebSocket error", error: error)
    
    state = update_connection_state(state, %{
      connected: false,
      connection_state: "error",
      last_error: to_string(error)
    })

    {:ok, state}
  end

  @impl Fresh
  def handle_info(:poll_stats, state) do
    if state.state.connection.connected do
      request_obs_stats()
    end
    
    # Schedule next poll
    timer = Process.send_after(self(), :poll_stats, @stats_polling_interval)
    state = %{state | stats_timer: timer}
    {:ok, state}
  end

  @impl Fresh
  def handle_info({:get_state, from}, state) do
    GenServer.reply(from, state.state)
    {:ok, state}
  end

  @impl Fresh
  def handle_info({:get_status, from}, state) do
    status = %{
      connected: state.state.connection.connected,
      connection_state: state.state.connection.connection_state
    }
    GenServer.reply(from, {:ok, status})
    {:ok, state}
  end

  @impl Fresh
  def handle_info({{:obs_call, request_type, request_data}, from}, state) do
    if state.state.connection.connected do
      request_id = UUID.uuid4()
      
      message = %{
        op: 6,  # Request opcode
        d: %{
          requestType: request_type,
          requestId: request_id,
          requestData: request_data
        }
      }

      case send_message(message) do
        :ok ->
          # Store the pending request
          pending_requests = Map.put(state.pending_requests, request_id, from)
          state = %{state | pending_requests: pending_requests}
          {:ok, state}

        {:error, reason} ->
          GenServer.reply(from, {:error, reason})
          {:ok, state}
      end
    else
      GenServer.reply(from, {:error, "OBS not connected"})
      {:ok, state}
    end
  end

  @impl Fresh
  def handle_info(info, state) do
    Logger.debug("Unhandled info message", info: info)
    {:ok, state}
  end

  # OBS WebSocket protocol handlers
  defp handle_obs_message(state, message_json) do
    case Jason.decode(message_json) do
      {:ok, %{"op" => op} = message} ->
        handle_obs_protocol_message(state, op, message)
      
      {:error, reason} ->
        Logger.error("Failed to decode OBS WebSocket message", error: reason, message: message_json)
        state
    end
  end

  defp handle_obs_protocol_message(state, 0, %{"d" => %{"rpcVersion" => rpc_version}}) do
    # Hello message - send Identify
    Logger.info("Received OBS Hello", rpc_version: rpc_version)
    
    identify_message = %{
      op: 1,  # Identify opcode
      d: %{
        rpcVersion: 1,
        authentication: get_auth_string(),
        eventSubscriptions: @event_subscription_all
      }
    }
    
    send_message(identify_message)
    state
  end

  defp handle_obs_protocol_message(state, 2, %{"d" => data}) do
    # Identified - connection successful
    Logger.info("OBS connection identified", rpc_version: data["negotiatedRpcVersion"])
    
    state = update_connection_state(state, %{
      connected: true,
      connection_state: "connected",
      negotiated_rpc_version: data["negotiatedRpcVersion"],
      last_connected: DateTime.utc_now()
    })

    # Publish connection event
    Server.Events.publish_obs_event("connection_identified", %{
      rpc_version: data["negotiatedRpcVersion"]
    })

    # Start monitoring
    start_stats_polling(state)
  end

  defp handle_obs_protocol_message(state, 5, %{"d" => %{"eventType" => event_type, "eventData" => event_data}}) do
    # Event message
    handle_obs_event(state, event_type, event_data)
  end

  defp handle_obs_protocol_message(state, 7, %{"d" => %{"requestId" => request_id} = response}) do
    # Request response
    case Map.pop(state.pending_requests, request_id) do
      {nil, _} ->
        Logger.warning("Received response for unknown request", request_id: request_id)
        state

      {from, remaining_requests} ->
        result = if response["requestStatus"]["result"] do
          {:ok, response["responseData"] || %{}}
        else
          {:error, response["requestStatus"]["comment"] || "Request failed"}
        end
        
        GenServer.reply(from, result)
        %{state | pending_requests: remaining_requests}
    end
  end

  defp handle_obs_protocol_message(state, op, message) do
    Logger.debug("Unhandled OBS WebSocket message", op: op, message: message)
    state
  end

  # OBS event handlers
  defp handle_obs_event(state, "CurrentProgramSceneChanged", %{"sceneName" => scene_name}) do
    Logger.debug("Current program scene changed", scene_name: scene_name)
    
    previous_scene = state.state.scenes.current
    state = update_scene_state(state, %{current: scene_name})
    
    # Publish event
    Server.Events.publish_obs_event("scene_current_changed", %{
      scene_name: scene_name,
      previous_scene: previous_scene
    })
    
    state
  end

  defp handle_obs_event(state, "CurrentPreviewSceneChanged", %{"sceneName" => scene_name}) do
    Logger.debug("Current preview scene changed", scene_name: scene_name)
    
    state = update_scene_state(state, %{preview: scene_name})
    
    Server.Events.publish_obs_event("scene_preview_changed", %{scene_name: scene_name})
    
    state
  end

  defp handle_obs_event(state, "SceneListChanged", %{"scenes" => scenes}) do
    Logger.debug("Scene list changed", scene_count: length(scenes))
    
    state = update_scene_state(state, %{list: scenes})
    
    Server.Events.publish_obs_event("scene_list_changed", %{scenes: scenes})
    
    state
  end

  defp handle_obs_event(state, "StreamStateChanged", %{"outputActive" => active, "outputState" => output_state}) do
    Logger.info("Stream state changed", output_active: active, output_state: output_state)
    
    state = update_streaming_state(state, %{active: active})
    
    event_type = if active, do: "stream_started", else: "stream_stopped"
    Server.Events.publish_obs_event(event_type, %{
      output_active: active,
      output_state: output_state
    })
    
    state
  end

  defp handle_obs_event(state, "RecordStateChanged", data) do
    %{"outputActive" => active, "outputState" => output_state} = data
    paused = Map.get(data, "outputPaused", false)
    
    Logger.info("Record state changed", output_active: active, output_state: output_state, paused: paused)
    
    state = update_recording_state(state, %{active: active, paused: paused})
    
    event_type = cond do
      active and not state.state.recording.active -> "recording_started"
      not active and state.state.recording.active -> "recording_stopped"
      paused -> "recording_paused"
      true -> "recording_state_changed"
    end
    
    Server.Events.publish_obs_event(event_type, data)
    
    state
  end

  defp handle_obs_event(state, "StudioModeStateChanged", %{"studioModeEnabled" => enabled}) do
    Logger.info("Studio mode changed", enabled: enabled)
    
    state = update_studio_mode_state(state, %{enabled: enabled})
    
    Server.Events.publish_obs_event("studio_mode_changed", %{enabled: enabled})
    
    state
  end

  defp handle_obs_event(state, "VirtualcamStateChanged", %{"outputActive" => active}) do
    Logger.info("Virtual camera state changed", active: active)
    
    state = update_virtual_cam_state(state, %{active: active})
    
    Server.Events.publish_obs_event("virtual_cam_changed", %{active: active})
    
    state
  end

  defp handle_obs_event(state, "ReplayBufferStateChanged", %{"outputActive" => active}) do
    Logger.info("Replay buffer state changed", active: active)
    
    state = update_replay_buffer_state(state, %{active: active})
    
    Server.Events.publish_obs_event("replay_buffer_changed", %{active: active})
    
    state
  end

  defp handle_obs_event(state, event_type, event_data) do
    Logger.debug("Unhandled OBS event", event_type: event_type, event_data: event_data)
    state
  end

  # State update helpers
  defp update_connection_state(state, updates) do
    connection = Map.merge(state.state.connection, updates)
    new_state = put_in(state.state.connection, connection)
    
    # Publish connection state changes
    Server.Events.publish_obs_event("connection_changed", connection)
    
    new_state
  end

  defp update_scene_state(state, updates) do
    scenes = Map.merge(state.state.scenes, updates)
    new_state = put_in(state.state.scenes, scenes)
    
    Server.Events.publish_obs_event("scenes_updated", scenes)
    
    new_state
  end

  defp update_streaming_state(state, updates) do
    streaming = Map.merge(state.state.streaming, updates)
    new_state = put_in(state.state.streaming, streaming)
    
    Server.Events.publish_obs_event("streaming_updated", streaming)
    
    new_state
  end

  defp update_recording_state(state, updates) do
    recording = Map.merge(state.state.recording, updates)
    new_state = put_in(state.state.recording, recording)
    
    Server.Events.publish_obs_event("recording_updated", recording)
    
    new_state
  end

  defp update_studio_mode_state(state, updates) do
    studio_mode = Map.merge(state.state.studio_mode, updates)
    new_state = put_in(state.state.studio_mode, studio_mode)
    
    Server.Events.publish_obs_event("studio_mode_updated", studio_mode)
    
    new_state
  end

  defp update_virtual_cam_state(state, updates) do
    virtual_cam = Map.merge(state.state.virtual_cam, updates)
    new_state = put_in(state.state.virtual_cam, virtual_cam)
    
    Server.Events.publish_obs_event("virtual_cam_updated", virtual_cam)
    
    new_state
  end

  defp update_replay_buffer_state(state, updates) do
    replay_buffer = Map.merge(state.state.replay_buffer, updates)
    new_state = put_in(state.state.replay_buffer, replay_buffer)
    
    Server.Events.publish_obs_event("replay_buffer_updated", replay_buffer)
    
    new_state
  end

  # Stats polling
  defp start_stats_polling(state) do
    timer = Process.send_after(self(), :poll_stats, @stats_polling_interval)
    %{state | stats_timer: timer}
  end

  defp stop_stats_polling(state) do
    if state.stats_timer do
      Process.cancel_timer(state.stats_timer)
    end
    %{state | stats_timer: nil}
  end

  defp request_obs_stats do
    # Request GetStats from OBS for performance monitoring
    request_id = UUID.uuid4()
    
    message = %{
      op: 6,
      d: %{
        requestType: "GetStats",
        requestId: request_id,
        requestData: %{}
      }
    }
    
    send_message(message)
  end

  # Helper functions
  defp send_message(message) do
    json_message = Jason.encode!(message)
    Fresh.send(__MODULE__, {:text, json_message})
  end

  # Configuration helpers
  defp get_websocket_url do
    Application.get_env(:server, :obs_websocket_url, "ws://localhost:4455")
  end

  defp get_auth_string do
    # OBS WebSocket v5 authentication would require challenge/response
    # For now, assume no auth (which is common in local setups)
    nil
  end
end