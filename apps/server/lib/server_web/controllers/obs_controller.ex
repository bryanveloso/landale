defmodule ServerWeb.OBSController do
  @moduledoc "Controller for OBS WebSocket operations and status monitoring."

  use ServerWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias ServerWeb.Schemas

  operation(:status,
    summary: "Get OBS WebSocket status",
    description: "Returns current OBS WebSocket connection status and state information",
    responses: %{
      200 => {"Success", "application/json", Schemas.SuccessResponse},
      503 => {"Service Unavailable", "application/json", Schemas.ErrorResponse}
    }
  )

  def status(conn, _params) do
    case Server.Services.OBS.get_state() do
      state when is_map(state) ->
        json(conn, %{success: true, data: state})

      _ ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{success: false, error: "OBS service unavailable"})
    end
  end

  operation(:start_streaming,
    summary: "Start OBS streaming",
    description: "Starts streaming in OBS Studio",
    responses: %{
      200 => {"Success", "application/json", Schemas.SuccessResponse},
      400 => {"Bad Request", "application/json", Schemas.ErrorResponse},
      503 => {"Service Unavailable", "application/json", Schemas.ErrorResponse}
    }
  )

  def start_streaming(conn, _params) do
    case Server.Services.OBS.start_streaming() do
      {:ok, _} ->
        json(conn, %{success: true, message: "Stream started"})

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{success: false, error: reason})
    end
  end

  operation(:stop_streaming,
    summary: "Stop OBS streaming",
    description: "Stops streaming in OBS Studio",
    responses: %{
      200 => {"Success", "application/json", Schemas.SuccessResponse},
      400 => {"Bad Request", "application/json", Schemas.ErrorResponse},
      503 => {"Service Unavailable", "application/json", Schemas.ErrorResponse}
    }
  )

  def stop_streaming(conn, _params) do
    case Server.Services.OBS.stop_streaming() do
      {:ok, _} ->
        json(conn, %{success: true, message: "Stream stopped"})

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{success: false, error: reason})
    end
  end

  operation(:start_recording,
    summary: "Start OBS recording",
    description: "Starts recording in OBS Studio",
    responses: %{
      200 => {"Success", "application/json", Schemas.SuccessResponse},
      400 => {"Bad Request", "application/json", Schemas.ErrorResponse},
      503 => {"Service Unavailable", "application/json", Schemas.ErrorResponse}
    }
  )

  def start_recording(conn, _params) do
    case Server.Services.OBS.start_recording() do
      {:ok, _} ->
        json(conn, %{success: true, message: "Recording started"})

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{success: false, error: reason})
    end
  end

  operation(:stop_recording,
    summary: "Stop OBS recording",
    description: "Stops recording in OBS Studio",
    responses: %{
      200 => {"Success", "application/json", Schemas.SuccessResponse},
      400 => {"Bad Request", "application/json", Schemas.ErrorResponse},
      503 => {"Service Unavailable", "application/json", Schemas.ErrorResponse}
    }
  )

  def stop_recording(conn, _params) do
    case Server.Services.OBS.stop_recording() do
      {:ok, _} ->
        json(conn, %{success: true, message: "Recording stopped"})

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{success: false, error: reason})
    end
  end

  operation(:set_scene,
    summary: "Set OBS scene",
    description: "Changes the current scene in OBS Studio",
    parameters: [
      scene_name: [in: :path, description: "Name of the scene to switch to", type: :string, required: true]
    ],
    responses: %{
      200 => {"Success", "application/json", Schemas.SuccessResponse},
      400 => {"Bad Request", "application/json", Schemas.ErrorResponse},
      503 => {"Service Unavailable", "application/json", Schemas.ErrorResponse}
    }
  )

  def set_scene(conn, %{"scene_name" => scene_name}) do
    case Server.Services.OBS.set_current_scene(scene_name) do
      {:ok, _} ->
        json(conn, %{success: true, message: "Scene changed to #{scene_name}"})

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{success: false, error: reason})
    end
  end

  # Enhanced endpoints for dashboard metrics

  operation(:scenes,
    summary: "Get OBS scenes",
    description: "Returns list of available scenes and current scene information",
    responses: %{
      200 => {"Success", "application/json", Schemas.SuccessResponse},
      503 => {"Service Unavailable", "application/json", Schemas.ErrorResponse}
    }
  )

  def scenes(conn, _params) do
    case Server.Services.OBS.get_scene_list() do
      {:ok, scenes_data} ->
        json(conn, %{success: true, data: scenes_data})

      {:error, reason} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{success: false, error: reason})
    end
  end

  operation(:stream_status,
    summary: "Get OBS stream status",
    description: "Returns detailed streaming status including bitrate, duration, and connection info",
    responses: %{
      200 => {"Success", "application/json", Schemas.SuccessResponse},
      503 => {"Service Unavailable", "application/json", Schemas.ErrorResponse}
    }
  )

  def stream_status(conn, _params) do
    case Server.Services.OBS.get_stream_status() do
      {:ok, stream_data} ->
        json(conn, %{success: true, data: stream_data})

      {:error, reason} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{success: false, error: reason})
    end
  end

  operation(:record_status,
    summary: "Get OBS recording status",
    description: "Returns current recording status and information",
    responses: %{
      200 => {"Success", "application/json", Schemas.SuccessResponse},
      503 => {"Service Unavailable", "application/json", Schemas.ErrorResponse}
    }
  )

  def record_status(conn, _params) do
    case Server.Services.OBS.get_record_status() do
      {:ok, record_data} ->
        json(conn, %{success: true, data: record_data})

      {:error, reason} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{success: false, error: reason})
    end
  end

  operation(:stats,
    summary: "Get OBS statistics",
    description: "Returns comprehensive OBS performance statistics and metrics",
    responses: %{
      200 => {"Success", "application/json", Schemas.SuccessResponse},
      503 => {"Service Unavailable", "application/json", Schemas.ErrorResponse}
    }
  )

  def stats(conn, _params) do
    # This endpoint can combine GetStats with current state for comprehensive metrics
    with {:ok, obs_stats} <- Server.Services.OBS.get_status(),
         state when is_map(state) <- Server.Services.OBS.get_state() do
      combined_stats = %{
        service_state: state,
        obs_internal: obs_stats,
        timestamp: System.system_time(:second)
      }

      json(conn, %{success: true, data: combined_stats})
    else
      {:error, reason} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{success: false, error: reason})

      _ ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{success: false, error: "OBS service unavailable"})
    end
  end

  operation(:version,
    summary: "Get OBS version",
    description: "Returns OBS Studio version information",
    responses: %{
      200 => {"Success", "application/json", Schemas.SuccessResponse},
      503 => {"Service Unavailable", "application/json", Schemas.ErrorResponse}
    }
  )

  def version(conn, _params) do
    case Server.Services.OBS.get_version() do
      {:ok, version_data} ->
        json(conn, %{success: true, data: version_data})

      {:error, reason} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{success: false, error: reason})
    end
  end

  operation(:virtual_cam,
    summary: "Get OBS virtual camera status",
    description: "Returns virtual camera status and configuration",
    responses: %{
      200 => {"Success", "application/json", Schemas.SuccessResponse},
      503 => {"Service Unavailable", "application/json", Schemas.ErrorResponse}
    }
  )

  def virtual_cam(conn, _params) do
    case Server.Services.OBS.get_virtual_cam_status() do
      {:ok, virtual_cam_data} ->
        json(conn, %{success: true, data: virtual_cam_data})

      {:error, reason} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{success: false, error: reason})
    end
  end

  operation(:outputs,
    summary: "Get OBS outputs",
    description: "Returns information about all OBS outputs (streaming, recording, etc.)",
    responses: %{
      200 => {"Success", "application/json", Schemas.SuccessResponse},
      503 => {"Service Unavailable", "application/json", Schemas.ErrorResponse}
    }
  )

  def outputs(conn, _params) do
    case Server.Services.OBS.get_output_list() do
      {:ok, outputs_data} ->
        json(conn, %{success: true, data: outputs_data})

      {:error, reason} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{success: false, error: reason})
    end
  end
end
