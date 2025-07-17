defmodule ServerWeb.ContextController do
  @moduledoc """
  REST API controller for SEED context management.

  Handles creation and retrieval of AI memory contexts from the SEED service.
  """

  use ServerWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Server.Context
  alias ServerWeb.{ResponseBuilder, Schemas}

  operation(:create,
    summary: "Create context",
    description: "Creates a new memory context entry from the SEED service",
    request_body:
      {"Context data", "application/json",
       %OpenApiSpex.Schema{
         type: :object,
         required: [:started, :ended, :session, :transcript, :duration],
         properties: %{
           started: %OpenApiSpex.Schema{type: :string, format: :datetime, description: "Context start time"},
           ended: %OpenApiSpex.Schema{type: :string, format: :datetime, description: "Context end time"},
           session: %OpenApiSpex.Schema{type: :string, description: "Stream session ID"},
           transcript: %OpenApiSpex.Schema{type: :string, description: "Aggregated transcript text"},
           duration: %OpenApiSpex.Schema{type: :number, description: "Context duration in seconds"},
           chat: %OpenApiSpex.Schema{
             type: :object,
             description: "Chat activity summary",
             properties: %{
               message_count: %OpenApiSpex.Schema{type: :integer},
               velocity: %OpenApiSpex.Schema{type: :number},
               participants: %OpenApiSpex.Schema{type: :array, items: %OpenApiSpex.Schema{type: :string}}
             }
           },
           interactions: %OpenApiSpex.Schema{
             type: :object,
             description: "Viewer interaction events",
             properties: %{
               follows: %OpenApiSpex.Schema{type: :integer},
               subscriptions: %OpenApiSpex.Schema{type: :integer},
               cheers: %OpenApiSpex.Schema{type: :integer},
               raids: %OpenApiSpex.Schema{type: :integer}
             }
           },
           emotes: %OpenApiSpex.Schema{
             type: :object,
             description: "Emote usage statistics",
             properties: %{
               total_count: %OpenApiSpex.Schema{type: :integer},
               unique_emotes: %OpenApiSpex.Schema{type: :integer},
               top_emotes: %OpenApiSpex.Schema{
                 type: :object,
                 additionalProperties: %OpenApiSpex.Schema{type: :integer}
               }
             }
           },
           patterns: %OpenApiSpex.Schema{
             type: :object,
             description: "AI-detected patterns and insights"
           },
           sentiment: %OpenApiSpex.Schema{
             type: :string,
             enum: ["positive", "negative", "neutral"],
             description: "Overall sentiment"
           },
           topics: %OpenApiSpex.Schema{
             type: :array,
             items: %OpenApiSpex.Schema{type: :string},
             description: "Extracted topics"
           }
         }
       }},
    responses: %{
      201 => {"Context created", "application/json", Schemas.ContextResponse},
      400 => {"Bad request", "application/json", Schemas.ErrorResponse},
      422 => {"Validation error", "application/json", Schemas.ValidationErrorResponse}
    }
  )

  def create(conn, params) do
    case Context.create_context(params) do
      {:ok, context} ->
        conn
        |> ResponseBuilder.send_success(
          %{
            started: context.started,
            ended: context.ended,
            session: context.session,
            duration: context.duration,
            sentiment: context.sentiment,
            topics: context.topics || []
          },
          %{},
          201
        )

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> ResponseBuilder.send_error(
          "validation_failed",
          "Context validation failed",
          %{errors: format_changeset_errors(changeset)},
          422
        )

      _ ->
        conn
        |> put_status(:internal_server_error)
        |> ResponseBuilder.send_error("internal_error", "Unexpected error occurred", 500)
    end
  end

  operation(:index,
    summary: "List contexts",
    description: "Retrieves a list of memory contexts with optional filtering",
    parameters: [
      limit: [
        in: :query,
        type: :integer,
        description: "Maximum number of results (default: 50, max: 500)"
      ],
      session: [
        in: :query,
        type: :string,
        description: "Filter by session ID"
      ]
    ],
    responses: %{
      200 => {"Contexts list", "application/json", Schemas.ContextListResponse}
    }
  )

  def index(conn, params) do
    try do
      opts = []
      opts = if params["limit"], do: Keyword.put(opts, :limit, String.to_integer(params["limit"])), else: opts
      opts = if params["session"], do: Keyword.put(opts, :session, params["session"]), else: opts

      contexts = Context.list_contexts(opts)

      conn
      |> ResponseBuilder.send_success(%{
        contexts: Enum.map(contexts, &format_context/1)
      })
    rescue
      ArgumentError ->
        conn
        |> put_status(:bad_request)
        |> ResponseBuilder.send_error("invalid_parameters", "Invalid parameter format", 400)
    end
  end

  operation(:search,
    summary: "Search contexts",
    description: "Searches contexts by transcript content",
    parameters: [
      q: [
        in: :query,
        type: :string,
        required: true,
        description: "Search query"
      ],
      limit: [
        in: :query,
        type: :integer,
        description: "Maximum number of results (default: 25, max: 100)"
      ],
      session: [
        in: :query,
        type: :string,
        description: "Filter by session ID"
      ]
    ],
    responses: %{
      200 => {"Search results", "application/json", Schemas.ContextListResponse},
      400 => {"Bad request", "application/json", Schemas.ErrorResponse}
    }
  )

  def search(conn, %{"q" => query} = params) when is_binary(query) and query != "" do
    try do
      opts = []
      opts = if params["limit"], do: Keyword.put(opts, :limit, String.to_integer(params["limit"])), else: opts
      opts = if params["session"], do: Keyword.put(opts, :session, params["session"]), else: opts

      contexts = Context.search_contexts(query, opts)

      conn
      |> ResponseBuilder.send_success(%{
        contexts: Enum.map(contexts, &format_context/1)
      })
    rescue
      ArgumentError ->
        conn
        |> put_status(:bad_request)
        |> ResponseBuilder.send_error("invalid_parameters", "Invalid parameter format", 400)
    end
  end

  def search(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> ResponseBuilder.send_error("missing_parameter", "Search query 'q' parameter is required", 400)
  end

  operation(:stats,
    summary: "Context statistics",
    description: "Retrieves context analytics and statistics",
    parameters: [
      hours: [
        in: :query,
        type: :integer,
        description: "Time window in hours (default: 24)"
      ]
    ],
    responses: %{
      200 => {"Context statistics", "application/json", Schemas.ContextStatsResponse}
    }
  )

  def stats(conn, params) do
    try do
      hours = if params["hours"], do: String.to_integer(params["hours"]), else: 24

      stats = Context.get_context_stats(hours)
      sentiment_dist = Context.get_sentiment_distribution(hours)
      popular_topics = Context.get_popular_topics(hours)

      conn
      |> json(%{
        status: "success",
        data: %{
          overall: stats,
          sentiment_distribution: sentiment_dist,
          popular_topics: popular_topics,
          time_window_hours: hours
        }
      })
    rescue
      ArgumentError ->
        conn
        |> put_status(:bad_request)
        |> ResponseBuilder.send_error("invalid_parameters", "Invalid parameter format", 400)
    end
  end

  # Private helper functions

  defp format_context(context) do
    %{
      started: context.started,
      ended: context.ended,
      session: context.session,
      transcript: context.transcript,
      duration: context.duration,
      sentiment: context.sentiment,
      topics: context.topics || [],
      chat_summary: format_summary(context.chat),
      interactions_summary: format_summary(context.interactions),
      emotes_summary: format_summary(context.emotes)
    }
  end

  defp format_summary(nil), do: nil
  defp format_summary(map) when is_map(map), do: map

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
