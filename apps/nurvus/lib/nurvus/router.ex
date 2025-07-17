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
    response = %{
      status: "ok",
      service: "nurvus",
      version: "0.1.0",
      timestamp: DateTime.utc_now()
    }

    send_json_response(conn, 200, response)
  end

  # List all processes - TDD implementation
  get "/api/processes" do
    # Get processes from Nurvus and extract from tuple
    {:ok, processes} = Nurvus.list_processes()
    send_json_response(conn, 200, %{processes: processes})
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
