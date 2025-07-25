defmodule Server.Services.OBS do
  @moduledoc """
  OBS WebSocket integration service.

  This module provides a facade that maintains backward compatibility
  while delegating to the new decomposed architecture.
  """

  @behaviour Server.Services.OBSBehaviour

  require Logger

  # Default session ID for backward compatibility
  @default_session "default"

  @doc """
  Start the default OBS session for backward compatibility.
  """
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor
    }
  end

  @impl true
  def start_link(opts \\ []) do
    children = [
      # Registry for tracking OBS sessions
      {Registry, keys: :unique, name: Server.Services.OBS.SessionRegistry},
      # ConnectionsSupervisor manages all OBS sessions
      {Server.Services.OBS.ConnectionsSupervisor, opts}
    ]

    supervisor_opts = [
      strategy: :one_for_one,
      name: __MODULE__.Supervisor
    ]

    case Supervisor.start_link(children, supervisor_opts) do
      {:ok, supervisor} ->
        # Start default session after supervisor is up
        uri = opts[:url] || System.get_env("OBS_WEBSOCKET_URL", "ws://localhost:4455")

        case Server.Services.OBS.ConnectionsSupervisor.start_session(@default_session, uri: uri) do
          {:ok, _} ->
            {:ok, supervisor}

          {:error, reason} ->
            Logger.warning("Failed to start default OBS session: #{inspect(reason)}")
            # Still return ok, session can be started later
            {:ok, supervisor}
        end

      error ->
        error
    end
  end

  # Delegate all public API methods to appropriate new modules

  @impl true
  def get_state do
    with {:ok, conn} <- get_connection(),
         state <- Server.Services.OBS.Connection.get_state(conn),
         {:ok, scene_manager} <- get_scene_manager(),
         {:ok, stream_manager} <- get_stream_manager() do
      # Combine states from multiple modules
      scene_state = GenServer.call(scene_manager, :get_state)
      stream_state = GenServer.call(stream_manager, :get_state)

      %{
        connection_state: state,
        current_scene: scene_state.current_scene,
        scene_list: scene_state.scene_list,
        streaming: %{
          active: stream_state.streaming_active,
          timecode: stream_state.streaming_timecode,
          duration: stream_state.streaming_duration
        },
        recording: %{
          active: stream_state.recording_active,
          paused: stream_state.recording_paused,
          timecode: stream_state.recording_timecode,
          duration: stream_state.recording_duration
        }
      }
    end
  end

  @impl true
  def get_status do
    case get_connection() do
      {:ok, conn} ->
        state = Server.Services.OBS.Connection.get_state(conn)

        {:ok,
         %{
           connected: state in [:ready, :authenticating],
           connection_state: state
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def set_current_scene(scene_name) do
    with {:ok, conn} <- get_connection() do
      Server.Services.OBS.Connection.send_request(conn, "SetCurrentProgramScene", %{sceneName: scene_name})
    end
  end

  @impl true
  def set_preview_scene(scene_name) do
    with {:ok, conn} <- get_connection() do
      Server.Services.OBS.Connection.send_request(conn, "SetCurrentPreviewScene", %{sceneName: scene_name})
    end
  end

  @impl true
  def start_streaming do
    with {:ok, conn} <- get_connection() do
      Server.Services.OBS.Connection.send_request(conn, "StartStream", %{})
    end
  end

  @impl true
  def stop_streaming do
    with {:ok, conn} <- get_connection() do
      Server.Services.OBS.Connection.send_request(conn, "StopStream", %{})
    end
  end

  @impl true
  def start_recording do
    with {:ok, conn} <- get_connection() do
      Server.Services.OBS.Connection.send_request(conn, "StartRecord", %{})
    end
  end

  @impl true
  def stop_recording do
    with {:ok, conn} <- get_connection() do
      Server.Services.OBS.Connection.send_request(conn, "StopRecord", %{})
    end
  end

  @impl true
  def pause_recording do
    with {:ok, conn} <- get_connection() do
      Server.Services.OBS.Connection.send_request(conn, "PauseRecord", %{})
    end
  end

  @impl true
  def resume_recording do
    with {:ok, conn} <- get_connection() do
      Server.Services.OBS.Connection.send_request(conn, "ResumeRecord", %{})
    end
  end

  @impl true
  def set_studio_mode_enabled(enabled) do
    with {:ok, conn} <- get_connection() do
      Server.Services.OBS.Connection.send_request(conn, "SetStudioModeEnabled", %{studioModeEnabled: enabled})
    end
  end

  @impl true
  def toggle_stream do
    with {:ok, conn} <- get_connection() do
      Server.Services.OBS.Connection.send_request(conn, "ToggleStream", %{})
    end
  end

  @impl true
  def toggle_record do
    with {:ok, conn} <- get_connection() do
      Server.Services.OBS.Connection.send_request(conn, "ToggleRecord", %{})
    end
  end

  @impl true
  def toggle_record_pause do
    with {:ok, conn} <- get_connection() do
      Server.Services.OBS.Connection.send_request(conn, "ToggleRecordPause", %{})
    end
  end

  @impl true
  def get_scene_list do
    with {:ok, conn} <- get_connection() do
      Server.Services.OBS.Connection.send_request(conn, "GetSceneList", %{})
    end
  end

  @impl true
  def get_input_list(kind) do
    params = if kind, do: %{inputKind: kind}, else: %{}

    with {:ok, conn} <- get_connection() do
      Server.Services.OBS.Connection.send_request(conn, "GetInputList", params)
    end
  end

  @impl true
  def refresh_browser_source(source_name) do
    with {:ok, conn} <- get_connection() do
      Server.Services.OBS.Connection.send_request(conn, "PressInputPropertiesButton", %{
        inputName: source_name,
        propertyName: "refreshnocache"
      })
    end
  end

  @impl true
  def send_batch_request(_requests, _options \\ %{}) do
    # TODO: Implement batch request handling
    {:error, :not_implemented}
  end

  @impl true
  def get_output_list do
    with {:ok, conn} <- get_connection() do
      Server.Services.OBS.Connection.send_request(conn, "GetOutputList", %{})
    end
  end

  @impl true
  def get_output_status(output_name) do
    with {:ok, conn} <- get_connection() do
      Server.Services.OBS.Connection.send_request(conn, "GetOutputStatus", %{outputName: output_name})
    end
  end

  # Additional methods for backward compatibility

  def get_current_scene do
    with {:ok, conn} <- get_connection() do
      case Server.Services.OBS.Connection.send_request(conn, "GetCurrentProgramScene", %{}) do
        {:ok, %{currentProgramSceneName: _scene_name}} = result ->
          result

        other ->
          other
      end
    end
  end

  def get_stream_status do
    with {:ok, _conn} <- get_connection(),
         {:ok, stream_manager} <- get_stream_manager() do
      state = GenServer.call(stream_manager, :get_state)

      {:ok,
       %{
         outputActive: state.streaming_active,
         outputTimecode: state.streaming_timecode,
         outputDuration: state.streaming_duration,
         outputCongestion: state.streaming_congestion,
         outputBytes: state.streaming_bytes,
         outputSkippedFrames: state.streaming_skipped_frames,
         outputTotalFrames: state.streaming_total_frames
       }}
    end
  end

  def get_record_status do
    with {:ok, _conn} <- get_connection(),
         {:ok, stream_manager} <- get_stream_manager() do
      state = GenServer.call(stream_manager, :get_state)

      {:ok,
       %{
         outputActive: state.recording_active,
         outputPaused: state.recording_paused,
         outputTimecode: state.recording_timecode,
         outputDuration: state.recording_duration,
         outputBytes: state.recording_bytes
       }}
    end
  end

  @impl true
  def get_version do
    with {:ok, conn} <- get_connection() do
      Server.Services.OBS.Connection.send_request(conn, "GetVersion", %{})
    end
  end

  @impl true
  def get_stats do
    with {:ok, conn} <- get_connection() do
      Server.Services.OBS.Connection.send_request(conn, "GetStats", %{})
    end
  end

  def get_virtual_cam_status do
    with {:ok, _conn} <- get_connection(),
         {:ok, stream_manager} <- get_stream_manager() do
      state = GenServer.call(stream_manager, :get_state)

      {:ok, %{outputActive: state.virtual_cam_active}}
    end
  end

  # ServiceBehaviour implementation

  @impl true
  def get_health do
    connection_status = check_connection_status()
    scene_manager_status = check_scene_manager_status()
    stream_manager_status = check_stream_manager_status()
    details = build_health_details()
    health_status = determine_overall_health(connection_status, scene_manager_status, stream_manager_status)

    {:ok,
     %{
       status: health_status,
       checks: %{
         websocket_connection: connection_status,
         scene_manager: scene_manager_status,
         stream_manager: stream_manager_status
       },
       details: details
     }}
  end

  defp check_connection_status do
    case get_connection() do
      {:ok, conn} -> evaluate_connection_state(conn)
      {:error, _} -> :fail
    end
  end

  defp evaluate_connection_state(conn) do
    case Server.Services.OBS.Connection.get_state(conn) do
      :ready -> :pass
      :authenticating -> :warn
      :connecting -> :warn
      :reconnecting -> :warn
      _ -> :fail
    end
  end

  defp check_scene_manager_status do
    case get_scene_manager() do
      {:ok, _} -> :pass
      {:error, _} -> :fail
    end
  end

  defp check_stream_manager_status do
    case get_stream_manager() do
      {:ok, _} -> :pass
      {:error, _} -> :fail
    end
  end

  defp build_health_details do
    case get_state() do
      %{connection_state: conn_state} = state ->
        %{
          connection_state: conn_state,
          streaming_active: get_in(state, [:streaming, :active]),
          recording_active: get_in(state, [:recording, :active]),
          current_scene: state[:current_scene]
        }

      _ ->
        %{}
    end
  end

  defp determine_overall_health(connection_status, scene_manager_status, stream_manager_status) do
    cond do
      connection_status == :fail -> :unhealthy
      scene_manager_status == :fail or stream_manager_status == :fail -> :degraded
      connection_status == :warn -> :degraded
      true -> :healthy
    end
  end

  @impl true
  def get_info do
    %{
      name: "obs",
      version: "2.0.0",
      capabilities: [:websocket, :streaming, :recording, :scene_management, :multi_session],
      description: "OBS WebSocket integration for streaming control and scene management"
    }
  end

  # Private helpers

  defp get_connection do
    Server.Services.OBS.Supervisor.get_process(@default_session, :connection)
  end

  defp get_scene_manager do
    Server.Services.OBS.Supervisor.get_process(@default_session, :scene_manager)
  end

  defp get_stream_manager do
    Server.Services.OBS.Supervisor.get_process(@default_session, :stream_manager)
  end
end
