defmodule ServerWeb.TranscriptionController do
  @moduledoc """
  API endpoints for transcription data and real-time events.
  """

  use ServerWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Server.Transcription
  alias ServerWeb.Schemas

  operation(:index,
    summary: "List recent transcriptions",
    description: "Returns recent transcriptions with optional filtering",
    parameters: [
      limit: [in: :query, description: "Number of results to return (max 100)", type: :integer, required: false],
      stream_session_id: [in: :query, description: "Filter by stream session", type: :string, required: false]
    ],
    responses: %{
      200 => {"Success", "application/json", Schemas.SuccessResponse}
    }
  )

  def index(conn, params) do
    limit = parse_limit(params["limit"], 50)
    opts = [limit: limit]

    opts =
      if params["stream_session_id"] do
        Keyword.put(opts, :stream_session_id, params["stream_session_id"])
      else
        opts
      end

    transcriptions = Transcription.list_transcriptions(opts)
    json(conn, %{success: true, data: transcriptions})
  end

  operation(:search,
    summary: "Search transcriptions",
    description: "Search transcription text with optional filters",
    parameters: [
      q: [in: :query, description: "Search query", type: :string, required: true],
      limit: [in: :query, description: "Number of results to return (max 50)", type: :integer, required: false],
      stream_session_id: [in: :query, description: "Filter by stream session", type: :string, required: false],
      full_text: [in: :query, description: "Use full-text search with similarity", type: :boolean, required: false]
    ],
    responses: %{
      200 => {"Success", "application/json", Schemas.SuccessResponse},
      400 => {"Bad Request", "application/json", Schemas.ErrorResponse}
    }
  )

  def search(conn, params) do
    case params["q"] do
      nil ->
        conn
        |> put_status(:bad_request)
        |> json(%{success: false, error: "Search query (q) is required"})

      "" ->
        conn
        |> put_status(:bad_request)
        |> json(%{success: false, error: "Search query cannot be empty"})

      query ->
        limit = parse_limit(params["limit"], 25)
        use_full_text = params["full_text"] == "true"

        opts = [limit: limit]

        opts =
          if params["stream_session_id"] do
            Keyword.put(opts, :stream_session_id, params["stream_session_id"])
          else
            opts
          end

        transcriptions =
          if use_full_text do
            Transcription.search_transcriptions_full_text(query, opts)
          else
            Transcription.search_transcriptions(query, opts)
          end

        json(conn, %{success: true, data: transcriptions, query: query})
    end
  end

  operation(:by_time_range,
    summary: "Get transcriptions by time range",
    description: "Returns transcriptions within a specific time range",
    parameters: [
      start_time: [in: :query, description: "Start time (ISO 8601)", type: :string, required: true],
      end_time: [in: :query, description: "End time (ISO 8601)", type: :string, required: true],
      limit: [in: :query, description: "Number of results to return (max 200)", type: :integer, required: false],
      stream_session_id: [in: :query, description: "Filter by stream session", type: :string, required: false]
    ],
    responses: %{
      200 => {"Success", "application/json", Schemas.SuccessResponse},
      400 => {"Bad Request", "application/json", Schemas.ErrorResponse}
    }
  )

  def by_time_range(conn, params) do
    with {:ok, start_time} <- parse_datetime(params["start_time"]),
         {:ok, end_time} <- parse_datetime(params["end_time"]) do
      limit = parse_limit(params["limit"], 100)
      opts = [limit: limit]

      opts =
        if params["stream_session_id"] do
          Keyword.put(opts, :stream_session_id, params["stream_session_id"])
        else
          opts
        end

      transcriptions = Transcription.list_transcriptions_by_time_range(start_time, end_time, opts)
      json(conn, %{success: true, data: transcriptions})
    else
      {:error, :invalid_start_time} ->
        conn
        |> put_status(:bad_request)
        |> json(%{success: false, error: "Invalid start_time format. Use ISO 8601."})

      {:error, :invalid_end_time} ->
        conn
        |> put_status(:bad_request)
        |> json(%{success: false, error: "Invalid end_time format. Use ISO 8601."})
    end
  end

  operation(:recent,
    summary: "Get recent transcriptions",
    description: "Returns transcriptions from the last N minutes",
    parameters: [
      minutes: [in: :query, description: "Number of minutes to look back (default: 5)", type: :integer, required: false]
    ],
    responses: %{
      200 => {"Success", "application/json", Schemas.SuccessResponse}
    }
  )

  def recent(conn, params) do
    minutes = parse_integer(params["minutes"], 5)
    transcriptions = Transcription.get_recent_transcriptions(minutes)
    json(conn, %{success: true, data: transcriptions})
  end

  operation(:session,
    summary: "Get session transcriptions",
    description: "Returns all transcriptions for a specific stream session",
    parameters: [
      session_id: [in: :path, description: "Stream session ID", type: :string, required: true],
      limit: [in: :query, description: "Number of results to return (max 1000)", type: :integer, required: false]
    ],
    responses: %{
      200 => {"Success", "application/json", Schemas.SuccessResponse}
    }
  )

  def session(conn, %{"session_id" => session_id} = params) do
    limit = parse_limit(params["limit"], 500)
    opts = [limit: limit]

    transcriptions = Transcription.get_session_transcriptions(session_id, opts)
    json(conn, %{success: true, data: transcriptions, session_id: session_id})
  end

  operation(:stats,
    summary: "Get transcription statistics",
    description: "Returns aggregate statistics for transcriptions",
    parameters: [
      hours: [in: :query, description: "Number of hours to look back (default: 24)", type: :integer, required: false]
    ],
    responses: %{
      200 => {"Success", "application/json", Schemas.SuccessResponse}
    }
  )

  def stats(conn, params) do
    hours = parse_integer(params["hours"], 24)
    stats = Transcription.get_transcription_stats(hours: hours)
    json(conn, %{success: true, data: stats})
  end

  # Private helper functions

  defp parse_limit(nil, default), do: default
  defp parse_limit("", default), do: default

  defp parse_limit(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {num, ""} when num > 0 and num <= 1000 -> num
      _ -> default
    end
  end

  defp parse_limit(_, default), do: default

  defp parse_integer(nil, default), do: default
  defp parse_integer("", default), do: default

  defp parse_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {num, ""} when num > 0 -> num
      _ -> default
    end
  end

  defp parse_integer(_, default), do: default

  defp parse_datetime(nil), do: {:error, :invalid_start_time}
  defp parse_datetime(""), do: {:error, :invalid_start_time}

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      {:error, _} -> {:error, :invalid_start_time}
    end
  end

  defp parse_datetime(_), do: {:error, :invalid_start_time}
end
