defmodule ServerWeb.OBSController do
  @moduledoc "Controller for OBS WebSocket operations and status monitoring."

  use ServerWeb, :controller

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
