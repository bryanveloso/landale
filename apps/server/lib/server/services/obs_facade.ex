defmodule Server.Services.OBSFacade do
  @moduledoc """
  Facade module that maintains backward compatibility with the existing OBS API
  while delegating to the new decomposed architecture.

  This allows gradual migration without breaking existing code.
  """

  @behaviour Server.Services.OBSBehaviour

  require Logger
  alias Server.Services.OBS

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

  def start_link(opts \\ []) do
    # Start the connections supervisor and registry
    with {:ok, _} <- Registry.start_link(keys: :unique, name: Server.Services.OBS.SessionRegistry),
         {:ok, supervisor} <- Server.Services.OBS.ConnectionsSupervisor.start_link(opts) do
      # Start default session
      uri = opts[:url] || System.get_env("OBS_WEBSOCKET_URL", "ws://localhost:4455")

      case Server.Services.OBS.ConnectionsSupervisor.start_session(@default_session, uri: uri) do
        {:ok, _} -> {:ok, supervisor}
        error -> error
      end
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

      {:ok,
       %{
         connection_state: state,
         current_scene: scene_state.current_scene,
         scene_list: scene_state.scene_list,
         streaming_active: stream_state.streaming_active,
         recording_active: stream_state.recording_active
       }}
    end
  end

  @impl true
  def get_status do
    case get_connection() do
      {:ok, conn} ->
        state = Server.Services.OBS.Connection.get_state(conn)
        {:ok, %{connected: state in [:ready, :authenticating]}}

      {:error, _} ->
        {:ok, %{connected: false}}
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

  # Private helpers

  defp get_connection do
    OBS.Supervisor.get_process(@default_session, :connection)
  end

  defp get_scene_manager do
    OBS.Supervisor.get_process(@default_session, :scene_manager)
  end

  defp get_stream_manager do
    OBS.Supervisor.get_process(@default_session, :stream_manager)
  end
end
