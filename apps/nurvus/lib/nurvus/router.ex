defmodule Nurvus.Router do
  @moduledoc """
  HTTP router for the Nurvus process management API.

  Provides RESTful endpoints for process lifecycle management and monitoring.
  """

  use Plug.Router
  require Logger

  alias Jason

  plug(Plug.Logger, log: :debug)
  plug(:telemetry_start)
  plug(:match)

  plug(Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Jason
  )

  plug(:dispatch)

  # Health check endpoint
  get "/health" do
    # Get process statuses to determine health
    {:ok, processes} = Nurvus.list_processes()

    # Count statuses
    running_count = Enum.count(processes, &(&1.status == :running))
    total_count = length(processes)

    # Get system status
    {:ok, system_status} = Nurvus.system_status()

    # Determine overall health
    health_status =
      cond do
        # No processes configured is OK
        total_count == 0 -> "healthy"
        # All processes down
        running_count == 0 -> "unhealthy"
        # Some processes down
        running_count < total_count -> "degraded"
        # All processes running
        true -> "healthy"
      end

    # Get uptime
    start_time = Application.get_env(:nurvus, :start_time, System.system_time(:second))
    uptime_seconds = System.system_time(:second) - start_time

    response = %{
      status: health_status,
      service: "nurvus",
      timestamp: System.system_time(:second),
      uptime_seconds: uptime_seconds,
      version: "0.1.0",
      processes: %{
        total: total_count,
        running: running_count,
        stopped: total_count - running_count
      },
      alerts: system_status.alerts
    }

    # Return appropriate status code
    status_code = if health_status == "healthy", do: 200, else: 503

    send_json_response(conn, status_code, response)
  end

  # System status endpoint
  get "/api/system/status" do
    {:ok, status_map} = Nurvus.system_status()

    platform_info = %{
      platform: Nurvus.Platform.current_platform(),
      hostname: System.get_env("HOSTNAME") || :inet.gethostname() |> elem(1) |> to_string()
    }

    enhanced_status = Map.merge(status_map, platform_info)
    send_json_response(conn, 200, enhanced_status)
  end

  # List all processes - FIXED implementation
  get "/api/processes" do
    # Extract processes list from tuple before encoding
    {:ok, processes} = Nurvus.list_processes()
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

  # Catch-all for undefined routes
  match _ do
    send_json_response(conn, 404, %{error: "Not found"})
  end

  ## Private Functions

  defp telemetry_start(conn, _opts) do
    start_time = System.monotonic_time()
    assign(conn, :telemetry_start_time, start_time)
  end

  defp send_json_response(conn, status, data) do
    if start_time = conn.assigns[:telemetry_start_time] do
      duration = System.monotonic_time() - start_time

      :telemetry.execute(
        [:nurvus, :http, :request],
        %{duration: duration},
        %{
          method: conn.method,
          path: conn.request_path,
          status: status
        }
      )
    end

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
