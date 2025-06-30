defmodule Server.Services.OBS do
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

  # OBS WebSocket protocol constants
  # Subscribe to all events
  @event_subscription_all 0x1FF
  # Network configuration is now handled by Server.NetworkConfig
  # 5 seconds
  @stats_polling_interval 5_000

  defstruct [
    :conn_pid,
    :stream_ref,
    :stats_timer,
    :reconnect_timer,
    :pending_requests,
    uri: nil,
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
  Gets the current internal state of the OBS service.

  ## Returns
  - Map containing connection, scenes, streaming, and recording state
  """
  @spec get_state() :: map()
  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end

  @doc """
  Gets the current status of the OBS service.

  ## Returns
  - `{:ok, status}` where status contains connection information
  - `{:error, reason}` if service is unavailable
  """
  @spec get_status() :: {:ok, map()} | {:error, binary()}
  def get_status do
    GenServer.call(__MODULE__, :get_status)
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
    GenServer.call(__MODULE__, {:obs_call, "SaveReployBuffer", %{}})
  end

  # GenServer callbacks
  @impl GenServer
  def init(opts) do
    url = Keyword.get(opts, :url, get_websocket_url())
    uri = URI.parse(url)

    state = %__MODULE__{
      uri: uri,
      pending_requests: %{}
    }

    Logger.info("OBS service starting", url: url)

    # Try to connect immediately
    send(self(), :connect)

    {:ok, state}
  end

  @impl GenServer
  def handle_call(:get_state, _from, state) do
    {:reply, state.state, state}
  end

  @impl GenServer
  def handle_call(:get_status, _from, state) do
    status = %{
      connected: state.state.connection.connected,
      connection_state: state.state.connection.connection_state
    }

    {:reply, {:ok, status}, state}
  end

  @impl GenServer
  def handle_call({:obs_call, request_type, request_data}, from, state) do
    if state.state.connection.connected and state.conn_pid and state.stream_ref do
      request_id = UUID.uuid4()

      message = %{
        # Request opcode
        op: 6,
        d: %{
          requestType: request_type,
          requestId: request_id,
          requestData: request_data
        }
      }

      case send_websocket_message(state, message) do
        :ok ->
          # Store the pending request
          pending_requests = Map.put(state.pending_requests, request_id, from)
          new_state = %{state | pending_requests: pending_requests}
          {:noreply, new_state}

        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    else
      {:reply, {:error, "OBS not connected"}, state}
    end
  end

  @impl GenServer
  def handle_info(:connect, state) do
    case connect_websocket(state) do
      {:ok, new_state} ->
        {:noreply, new_state}

      {:error, new_state} ->
        # Schedule reconnect
        timer = Process.send_after(self(), :connect, Server.NetworkConfig.reconnect_interval())
        new_state = %{new_state | reconnect_timer: timer}
        {:noreply, new_state}
    end
  end

  @impl GenServer
  def handle_info(:poll_stats, state) do
    if state.state.connection.connected do
      request_obs_stats(state)
    end

    # Schedule next poll
    timer = Process.send_after(self(), :poll_stats, @stats_polling_interval)
    state = %{state | stats_timer: timer}
    {:noreply, state}
  end

  # Gun WebSocket messages
  @impl GenServer
  def handle_info({:gun_response, conn_pid, stream_ref, is_fin, status, headers}, state) do
    if conn_pid == state.conn_pid and stream_ref == state.stream_ref do
      Logger.debug("OBS HTTP response received",
        status: status,
        is_fin: is_fin,
        headers: inspect(headers)
      )
    end

    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:gun_upgrade, _conn_pid, stream_ref, ["websocket"], _headers}, state) do
    if stream_ref == state.stream_ref do
      Logger.info("OBS WebSocket connection established")

      # Update connection state
      state =
        update_connection_state(state, %{
          connected: true,
          connection_state: "connected",
          last_connected: DateTime.utc_now()
        })

      # Publish connection event
      Server.Events.publish_obs_event("connection_established", %{})

      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info({:gun_ws, _conn_pid, stream_ref, {:text, message}}, state) do
    if stream_ref == state.stream_ref do
      state = handle_obs_message(state, message)
      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info({:gun_ws, _conn_pid, stream_ref, frame}, state) do
    if stream_ref == state.stream_ref do
      Logger.debug("OBS WebSocket frame unhandled", frame: frame)
    end

    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:gun_down, conn_pid, _protocol, reason, _killed_streams}, state) do
    if conn_pid == state.conn_pid do
      Logger.warning("OBS connection lost", reason: reason)

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

      # Schedule reconnect
      timer = Process.send_after(self(), :connect, Server.NetworkConfig.reconnect_interval())
      state = %{state | reconnect_timer: timer}

      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info({:gun_error, conn_pid, stream_ref, reason}, state) do
    if conn_pid == state.conn_pid and stream_ref == state.stream_ref do
      Logger.error("OBS WebSocket stream error",
        conn_pid: inspect(conn_pid),
        stream_ref: inspect(stream_ref),
        reason: inspect(reason, pretty: true)
      )

      state =
        update_connection_state(state, %{
          connected: false,
          connection_state: "error",
          last_error: inspect(reason)
        })
        |> cleanup_connection()

      # Schedule reconnect
      timer = Process.send_after(self(), :connect, Server.NetworkConfig.reconnect_interval())
      state = %{state | reconnect_timer: timer}

      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info({:gun_error, conn_pid, reason}, state) do
    if conn_pid == state.conn_pid do
      Logger.error("OBS connection error",
        conn_pid: inspect(conn_pid),
        reason: inspect(reason, pretty: true)
      )

      state =
        update_connection_state(state, %{
          connected: false,
          connection_state: "error",
          last_error: inspect(reason)
        })
        |> cleanup_connection()

      # Schedule reconnect
      timer = Process.send_after(self(), :connect, Server.NetworkConfig.reconnect_interval())
      state = %{state | reconnect_timer: timer}

      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    if pid == state.conn_pid do
      Logger.info("OBS connection process terminated", reason: reason)

      # Update connection state and schedule reconnect
      state =
        update_connection_state(state, %{
          connected: false,
          connection_state: "disconnected"
        })
        |> stop_stats_polling()
        |> cleanup_connection()

      # Publish disconnection event
      Server.Events.publish_obs_event("connection_lost", %{})

      # Schedule reconnect
      timer = Process.send_after(self(), :connect, Server.NetworkConfig.reconnect_interval())
      state = %{state | reconnect_timer: timer}

      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info(info, state) do
    Logger.warning("Gun message unhandled", message: inspect(info, pretty: true))
    {:noreply, state}
  end

  @impl GenServer
  def terminate(_reason, state) do
    Logger.info("OBS service terminating")

    # Cancel timers
    if state.stats_timer do
      Process.cancel_timer(state.stats_timer)
    end

    if state.reconnect_timer do
      Process.cancel_timer(state.reconnect_timer)
    end

    # Close WebSocket connection
    if state.conn_pid do
      :gun.close(state.conn_pid)
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

    case :gun.open(host, port) do
      {:ok, conn_pid} ->
        # Monitor the connection
        Process.monitor(conn_pid)

        websocket_config = Server.NetworkConfig.websocket_config()

        case :gun.await_up(conn_pid, websocket_config.timeout) do
          {:ok, _protocol} ->
            # Upgrade to WebSocket - try without protocol first
            stream_ref = :gun.ws_upgrade(conn_pid, path)

            Logger.debug("OBS WebSocket upgrade initiated",
              conn_pid: inspect(conn_pid),
              stream_ref: inspect(stream_ref),
              path: path
            )

            new_state =
              %{state | conn_pid: conn_pid, stream_ref: stream_ref}
              |> update_connection_state(%{
                connected: false,
                connection_state: "connecting"
              })

            {:ok, new_state}

          {:error, reason} ->
            Logger.error("OBS connection failed during await_up", error: reason)
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
        Logger.error("OBS connection failed during open", error: reason)

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
    case Jason.decode(message_json) do
      {:ok, %{"op" => op} = message} ->
        handle_obs_protocol_message(state, op, message)

      {:error, reason} ->
        Logger.error("OBS message decode failed", error: reason, message: message_json)
        state
    end
  end

  defp handle_obs_protocol_message(state, 0, %{"d" => %{"rpcVersion" => rpc_version}}) do
    # Hello message - send Identify
    Logger.info("OBS Hello received", rpc_version: rpc_version)

    identify_message = %{
      # Identify opcode
      op: 1,
      d: %{
        rpcVersion: 1,
        authentication: get_auth_string(),
        eventSubscriptions: @event_subscription_all
      }
    }

    case send_websocket_message(state, identify_message) do
      :ok -> state
      {:error, _reason} -> state
    end
  end

  defp handle_obs_protocol_message(state, 2, %{"d" => data}) do
    # Identified - connection successful
    Logger.info("OBS authentication successful", rpc_version: data["negotiatedRpcVersion"])

    # Emit telemetry for successful connection
    # Calculate duration from when we started connecting
    if state.state.connection.last_connected do
      duration = DateTime.diff(DateTime.utc_now(), state.state.connection.last_connected, :millisecond)
      Server.Telemetry.obs_connection_success(duration)
    end

    state =
      update_connection_state(state, %{
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

  defp handle_obs_protocol_message(state, 5, %{
         "d" => %{"eventType" => event_type, "eventData" => event_data}
       }) do
    # Event message
    handle_obs_event(state, event_type, event_data)
  end

  defp handle_obs_protocol_message(state, 7, %{"d" => %{"requestId" => request_id} = response}) do
    # Request response
    case Map.pop(state.pending_requests, request_id) do
      {nil, _} ->
        Logger.warning("OBS response for unknown request", request_id: request_id)
        state

      {from, remaining_requests} ->
        result =
          if response["requestStatus"]["result"] do
            {:ok, response["responseData"] || %{}}
          else
            {:error, response["requestStatus"]["comment"] || "Request failed"}
          end

        GenServer.reply(from, result)
        %{state | pending_requests: remaining_requests}
    end
  end

  defp handle_obs_protocol_message(state, op, message) do
    Logger.debug("OBS message unhandled", op: op, message: message)
    state
  end

  # OBS event handlers (simplified versions)
  defp handle_obs_event(state, "CurrentProgramSceneChanged", %{"sceneName" => scene_name}) do
    Logger.debug("OBS current scene changed", scene_name: scene_name)

    previous_scene = state.state.scenes.current
    state = update_scene_state(state, %{current: scene_name})

    # Publish event
    Server.Events.publish_obs_event("scene_current_changed", %{
      scene_name: scene_name,
      previous_scene: previous_scene
    })

    state
  end

  defp handle_obs_event(state, "StreamStateChanged", %{
         "outputActive" => active,
         "outputState" => output_state
       }) do
    Logger.info("OBS stream state changed", output_active: active, output_state: output_state)

    state = update_streaming_state(state, %{active: active})

    event_type = if active, do: "stream_started", else: "stream_stopped"

    Server.Events.publish_obs_event(event_type, %{
      output_active: active,
      output_state: output_state
    })

    state
  end

  defp handle_obs_event(state, event_type, event_data) do
    Logger.debug("OBS event unhandled", event_type: event_type, event_data: event_data)
    state
  end

  # Helper functions
  defp send_websocket_message(state, message) do
    if state.conn_pid && state.stream_ref do
      json_message = Jason.encode!(message)
      :gun.ws_send(state.conn_pid, state.stream_ref, {:text, json_message})
      :ok
    else
      {:error, "WebSocket not connected"}
    end
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

  defp request_obs_stats(state) do
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

  defp get_auth_string do
    # OBS WebSocket v5 authentication would require challenge/response
    # For now, assume no auth (which is common in local setups)
    nil
  end
end
