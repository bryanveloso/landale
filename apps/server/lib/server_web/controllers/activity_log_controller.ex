defmodule ServerWeb.ActivityLogController do
  @moduledoc """
  REST API controller for Activity Log management.

  Handles retrieval of activity events and user metadata for the
  real-time Activity Log interface.
  """

  use ServerWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Server.ActivityLog
  alias ServerWeb.ResponseBuilder

  operation(:events,
    summary: "List recent events",
    description: "Retrieves recent activity events with optional filtering",
    parameters: [
      limit: [
        in: :query,
        type: :integer,
        description: "Maximum number of results (unbounded by default, max: 1000 when specified)"
      ],
      event_type: [
        in: :query,
        type: :string,
        description: "Filter by specific event type"
      ],
      user_id: [
        in: :query,
        type: :string,
        description: "Filter by specific user ID"
      ]
    ],
    responses: %{
      200 => {"Events list", "application/json", %OpenApiSpex.Schema{type: :object}}
    }
  )

  def events(conn, params) do
    opts = []
    # Only add limit if explicitly provided (no default = unbounded)
    opts = if params["limit"], do: Keyword.put(opts, :limit, String.to_integer(params["limit"])), else: opts
    opts = if params["event_type"], do: Keyword.put(opts, :event_type, params["event_type"]), else: opts
    opts = if params["user_id"], do: Keyword.put(opts, :user_id, params["user_id"]), else: opts

    events = ActivityLog.list_recent_events(opts)

    conn
    |> ResponseBuilder.send_success(%{
      events: Enum.map(events, &format_event/1),
      count: length(events)
    })
  rescue
    ArgumentError ->
      conn
      |> put_status(:bad_request)
      |> ResponseBuilder.send_error("invalid_parameters", "Invalid parameter format", 400)
  end

  operation(:stats,
    summary: "Activity statistics",
    description: "Retrieves activity statistics and analytics",
    parameters: [
      hours: [
        in: :query,
        type: :integer,
        description: "Time window in hours (default: 24)"
      ]
    ],
    responses: %{
      200 => {"Activity statistics", "application/json", %OpenApiSpex.Schema{type: :object}}
    }
  )

  def stats(conn, params) do
    hours = if params["hours"], do: String.to_integer(params["hours"]), else: 24

    stats = ActivityLog.get_activity_stats(hours)
    active_users = ActivityLog.get_most_active_users(hours, 10)

    conn
    |> ResponseBuilder.send_success(%{
      stats: stats,
      most_active_users: active_users,
      time_window_hours: hours
    })
  rescue
    ArgumentError ->
      conn
      |> put_status(:bad_request)
      |> ResponseBuilder.send_error("invalid_parameters", "Invalid parameter format", 400)
  end

  # Private helper functions
  defp format_event(event) do
    %{
      id: event.id,
      timestamp: event.timestamp,
      event_type: event.event_type,
      user_id: event.user_id,
      user_login: event.user_login,
      user_name: event.user_name,
      data: event.data,
      correlation_id: event.correlation_id
    }
  end
end
