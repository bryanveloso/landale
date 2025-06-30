defmodule ServerWeb.OBSController do
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
end
