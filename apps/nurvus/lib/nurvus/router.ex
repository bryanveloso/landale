defmodule Nurvus.Router do
  @moduledoc """
  HTTP router for the Nurvus process management API.

  Provides RESTful endpoints for process lifecycle management and monitoring.
  """

  use Plug.Router
  require Logger

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
    {:ok, status_map} = Nurvus.system_status()

    platform_info = %{
      platform: Nurvus.Platform.current_platform(),
      hostname: System.get_env("HOSTNAME") || :inet.gethostname() |> elem(1) |> to_string()
    }

    enhanced_status = Map.merge(status_map, platform_info)
    send_json_response(conn, 200, enhanced_status)
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

  # Platform detection endpoints
  get "/api/platform" do
    {os_family, os_name} = :os.type()
    os_version = :os.version() |> Tuple.to_list()

    platform_info = %{
      platform: Nurvus.Platform.current_platform(),
      hostname: System.get_env("HOSTNAME") || :inet.gethostname() |> elem(1) |> to_string(),
      os_info: %{
        family: os_family,
        name: os_name,
        version: os_version
      }
    }

    send_json_response(conn, 200, platform_info)
  end

  # Get system process list (for debugging/monitoring)
  get "/api/platform/processes" do
    case Nurvus.Platform.get_process_list() do
      {:ok, processes} ->
        send_json_response(conn, 200, %{processes: processes})

      {:error, reason} ->
        send_json_response(conn, 500, %{error: "Failed to get process list: #{inspect(reason)}"})
    end
  end

  # Check if a specific process is running on the system
  get "/api/platform/processes/:name" do
    process_name = URI.decode(name)

    case Nurvus.Platform.get_process_info(process_name) do
      {:ok, process_info} ->
        send_json_response(conn, 200, process_info)

      {:error, :not_found} ->
        send_json_response(conn, 404, %{error: "Process not found", process_name: process_name})

      {:error, reason} ->
        send_json_response(conn, 500, %{error: "Failed to get process info: #{inspect(reason)}"})
    end
  end

  # Load configuration for specific machine
  post "/api/config/load" do
    machine_name = Map.get(conn.body_params, "machine", "default")
    config_file = "config/#{machine_name}.json"

    case Nurvus.Config.load_config(config_file) do
      {:ok, processes} ->
        # Add each process to the manager
        results = Enum.map(processes, &Nurvus.add_process/1)

        case Enum.find(results, fn result -> result != :ok end) do
          nil ->
            send_json_response(conn, 200, %{
              status: "loaded",
              machine: machine_name,
              processes_count: length(processes)
            })

          {:error, reason} ->
            send_json_response(conn, 400, %{
              error: "Failed to load some processes: #{inspect(reason)}"
            })
        end

      {:error, reason} ->
        send_json_response(conn, 400, %{
          error: "Failed to load configuration: #{inspect(reason)}"
        })
    end
  end

  # Cross-machine health check
  get "/api/health/detailed" do
    {:ok, system_status} = Nurvus.system_status()
    processes = Nurvus.list_processes()

    platform_info = %{
      platform: Nurvus.Platform.current_platform(),
      hostname: System.get_env("HOSTNAME") || :inet.gethostname() |> elem(1) |> to_string()
    }

    detailed_health = %{
      service: "nurvus",
      version: "0.1.0",
      timestamp: DateTime.utc_now(),
      platform: platform_info,
      system: system_status,
      processes: %{
        total: length(processes),
        running: Enum.count(processes, fn {_id, status} -> status == :running end),
        stopped: Enum.count(processes, fn {_id, status} -> status == :stopped end)
      }
    }

    send_json_response(conn, 200, detailed_health)
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
    # Emit telemetry for response timing
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
