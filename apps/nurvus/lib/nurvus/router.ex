defmodule Nurvus.Router do
  @moduledoc """
  HTTP router for the Nurvus process management API.

  Provides RESTful endpoints for process lifecycle management and monitoring.
  """

  use Plug.Router
  require Logger

  plug(Plug.Logger, log: :debug)
  plug(:match)

  plug(Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Jason
  )

  plug(:dispatch)

  # Health check endpoint
  get "/health" do
    response = %{
      status: "ok",
      service: "nurvus",
      version: "0.1.0",
      timestamp: DateTime.utc_now()
    }

    send_json_response(conn, 200, response)
  end

  # System status endpoint
  get "/api/system/status" do
    status = Nurvus.system_status()
    send_json_response(conn, 200, status)
  end

  # List all processes
  get "/api/processes" do
    processes = Nurvus.list_processes()
    send_json_response(conn, 200, %{processes: processes})
  end

  # Get specific process details
  get "/api/processes/:id" do
    case Nurvus.get_status(id) do
      {:ok, status} ->
        process_info = %{
          id: id,
          status: status
        }

        # Try to get metrics if available
        metrics =
          case Nurvus.get_metrics(id) do
            {:ok, m} -> m
            _ -> nil
          end

        response =
          if metrics do
            Map.put(process_info, :metrics, metrics)
          else
            process_info
          end

        send_json_response(conn, 200, response)

      {:error, :not_found} ->
        send_json_response(conn, 404, %{error: "Process not found"})
    end
  end

  # Add new process
  post "/api/processes" do
    case conn.body_params do
      %{"id" => _id} = config ->
        case Nurvus.add_process(config) do
          :ok ->
            send_json_response(conn, 201, %{status: "created", process_id: config["id"]})

          {:error, reason} ->
            send_json_response(conn, 400, %{error: inspect(reason)})
        end

      _ ->
        send_json_response(conn, 400, %{error: "Missing required fields"})
    end
  end

  # Start process
  post "/api/processes/:id/start" do
    case Nurvus.start_process(id) do
      :ok ->
        send_json_response(conn, 200, %{status: "started", process_id: id})

      {:error, :not_found} ->
        send_json_response(conn, 404, %{error: "Process not found"})

      {:error, reason} ->
        send_json_response(conn, 500, %{error: inspect(reason)})
    end
  end

  # Stop process
  post "/api/processes/:id/stop" do
    case Nurvus.stop_process(id) do
      :ok ->
        send_json_response(conn, 200, %{status: "stopped", process_id: id})

      {:error, :not_found} ->
        send_json_response(conn, 404, %{error: "Process not found"})

      {:error, reason} ->
        send_json_response(conn, 500, %{error: inspect(reason)})
    end
  end

  # Restart process
  post "/api/processes/:id/restart" do
    case Nurvus.restart_process(id) do
      :ok ->
        send_json_response(conn, 200, %{status: "restarted", process_id: id})

      {:error, :not_found} ->
        send_json_response(conn, 404, %{error: "Process not found"})

      {:error, reason} ->
        send_json_response(conn, 500, %{error: inspect(reason)})
    end
  end

  # Delete process
  delete "/api/processes/:id" do
    case Nurvus.remove_process(id) do
      :ok ->
        send_json_response(conn, 200, %{status: "removed", process_id: id})

      {:error, :not_found} ->
        send_json_response(conn, 404, %{error: "Process not found"})
    end
  end

  # Get process metrics
  get "/api/processes/:id/metrics" do
    case Nurvus.get_metrics(id) do
      {:ok, metrics} ->
        send_json_response(conn, 200, metrics)

      {:error, :not_found} ->
        send_json_response(conn, 404, %{error: "Process not found or no metrics available"})
    end
  end

  # Get all metrics
  get "/api/metrics" do
    metrics = Nurvus.get_all_metrics()
    send_json_response(conn, 200, metrics)
  end

  # Get alerts
  get "/api/alerts" do
    alerts = Nurvus.get_alerts()
    send_json_response(conn, 200, %{alerts: alerts})
  end

  # Clear alerts
  delete "/api/alerts" do
    :ok = Nurvus.clear_alerts()
    send_json_response(conn, 200, %{status: "cleared"})
  end

  # Catch-all for undefined routes
  match _ do
    send_json_response(conn, 404, %{error: "Not found"})
  end

  ## Private Functions

  defp send_json_response(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
