defmodule ServerWeb.CommunityController do
  @moduledoc """
  REST API controller for community management.

  Provides endpoints for managing community members, pronunciation overrides,
  username aliases, and community vocabulary.
  """

  use ServerWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Server.Community
  alias ServerWeb.ResponseBuilder

  ## Community Members

  operation(:list_members,
    summary: "List community members",
    description: "Retrieves active community members with optional filtering",
    parameters: [
      limit: [
        in: :query,
        type: :integer,
        description: "Maximum number of results (default: 50, max: 500)"
      ]
    ],
    responses: %{
      200 => {"Community members list", "application/json", %OpenApiSpex.Schema{type: :object}}
    }
  )

  def list_members(conn, params) do
    limit = params |> Map.get("limit", "50") |> String.to_integer() |> min(500)
    members = Community.list_active_community_members(limit)

    conn
    |> ResponseBuilder.send_success(%{
      data: Enum.map(members, &format_member/1),
      count: length(members)
    })
  end

  operation(:update_member_activity,
    summary: "Update member activity",
    description: "Updates community member activity from chat events",
    request_body:
      {"Member activity data", "application/json",
       %OpenApiSpex.Schema{
         type: :object,
         required: [:username],
         properties: %{
           username: %OpenApiSpex.Schema{type: :string, description: "Username"},
           display_name: %OpenApiSpex.Schema{type: :string, description: "Display name"}
         }
       }},
    responses: %{
      200 => {"Activity updated", "application/json", %OpenApiSpex.Schema{type: :object}},
      201 => {"Member created", "application/json", %OpenApiSpex.Schema{type: :object}}
    }
  )

  def update_member_activity(conn, %{"username" => username} = params) do
    display_name = Map.get(params, "display_name")

    case Community.upsert_community_member(username, display_name) do
      {:ok, member} ->
        status = if member.message_count == 1, do: 201, else: 200

        conn
        |> ResponseBuilder.send_success(
          %{
            username: member.username,
            display_name: member.display_name,
            message_count: member.message_count,
            last_seen: member.last_seen
          },
          %{},
          status
        )

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> ResponseBuilder.send_error(
          "validation_failed",
          "Member validation failed",
          %{errors: format_changeset_errors(changeset)},
          422
        )
    end
  end

  def update_member_activity(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> ResponseBuilder.send_error("missing_parameter", "Username is required", 400)
  end

  operation(:get_community_stats,
    summary: "Get community statistics",
    description: "Retrieves community engagement statistics",
    responses: %{
      200 => {"Community statistics", "application/json", %OpenApiSpex.Schema{type: :object}}
    }
  )

  def get_community_stats(conn, _params) do
    stats = Community.get_community_stats()

    conn
    |> ResponseBuilder.send_success(%{data: stats})
  end

  ## Pronunciation Overrides

  operation(:list_pronunciations,
    summary: "List pronunciation overrides",
    description: "Retrieves all active pronunciation overrides",
    responses: %{
      200 => {"Pronunciation overrides list", "application/json", %OpenApiSpex.Schema{type: :object}}
    }
  )

  def list_pronunciations(conn, _params) do
    overrides = Community.list_pronunciation_overrides()

    conn
    |> ResponseBuilder.send_success(%{
      data: Enum.map(overrides, &format_pronunciation/1)
    })
  end

  operation(:create_pronunciation,
    summary: "Create pronunciation override",
    description: "Creates a new pronunciation override for a username",
    request_body:
      {"Pronunciation data", "application/json",
       %OpenApiSpex.Schema{
         type: :object,
         required: [:username, :phonetic],
         properties: %{
           username: %OpenApiSpex.Schema{type: :string, description: "Username"},
           phonetic: %OpenApiSpex.Schema{type: :string, description: "Phonetic pronunciation"},
           confidence: %OpenApiSpex.Schema{type: :number, description: "Confidence level (0.0-1.0)"},
           created_by: %OpenApiSpex.Schema{type: :string, description: "Creator"}
         }
       }},
    responses: %{
      201 => {"Pronunciation created", "application/json", %OpenApiSpex.Schema{type: :object}},
      422 => {"Validation error", "application/json", %OpenApiSpex.Schema{type: :object}}
    }
  )

  def create_pronunciation(conn, params) do
    case Community.create_pronunciation_override(params) do
      {:ok, override} ->
        conn
        |> ResponseBuilder.send_success(
          %{
            username: override.username,
            phonetic: override.phonetic,
            confidence: override.confidence,
            created_by: override.created_by
          },
          %{},
          201
        )

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> ResponseBuilder.send_error(
          "validation_failed",
          "Pronunciation validation failed",
          %{errors: format_changeset_errors(changeset)},
          422
        )
    end
  end

  operation(:get_pronunciation,
    summary: "Get pronunciation for username",
    description: "Gets pronunciation guide for a specific username",
    parameters: [
      username: [
        in: :path,
        type: :string,
        required: true,
        description: "Username to get pronunciation for"
      ]
    ],
    responses: %{
      200 => {"Pronunciation found", "application/json", %OpenApiSpex.Schema{type: :object}},
      404 => {"Pronunciation not found", "application/json", %OpenApiSpex.Schema{type: :object}}
    }
  )

  def get_pronunciation(conn, %{"username" => username}) do
    case Community.get_pronunciation_guide(username) do
      nil ->
        conn
        |> put_status(:not_found)
        |> ResponseBuilder.send_error("not_found", "Pronunciation not found", 404)

      phonetic ->
        conn
        |> ResponseBuilder.send_success(%{
          username: username,
          phonetic: phonetic
        })
    end
  end

  ## Community Vocabulary

  operation(:list_vocabulary,
    summary: "List community vocabulary",
    description: "Retrieves community vocabulary with optional filtering",
    parameters: [
      category: [
        in: :query,
        type: :string,
        description: "Filter by category"
      ],
      limit: [
        in: :query,
        type: :integer,
        description: "Maximum number of results (default: 50)"
      ]
    ],
    responses: %{
      200 => {"Vocabulary list", "application/json", %OpenApiSpex.Schema{type: :object}}
    }
  )

  def list_vocabulary(conn, params) do
    vocabulary =
      case params["category"] do
        nil ->
          limit = params |> Map.get("limit", "50") |> String.to_integer()
          Community.get_popular_vocabulary(limit)

        category ->
          limit = params |> Map.get("limit", "50") |> String.to_integer()
          Community.list_vocabulary_by_category(category, limit)
      end

    conn
    |> ResponseBuilder.send_success(%{
      data: Enum.map(vocabulary, &format_vocabulary/1)
    })
  end

  operation(:create_vocabulary,
    summary: "Create vocabulary entry",
    description: "Creates a new community vocabulary entry",
    request_body:
      {"Vocabulary data", "application/json",
       %OpenApiSpex.Schema{
         type: :object,
         required: [:phrase, :category],
         properties: %{
           phrase: %OpenApiSpex.Schema{type: :string, description: "Vocabulary phrase"},
           category: %OpenApiSpex.Schema{type: :string, description: "Category"},
           definition: %OpenApiSpex.Schema{type: :string, description: "Definition"},
           context: %OpenApiSpex.Schema{type: :string, description: "Usage context"},
           tags: %OpenApiSpex.Schema{
             type: :array,
             items: %OpenApiSpex.Schema{type: :string},
             description: "Tags"
           }
         }
       }},
    responses: %{
      201 => {"Vocabulary created", "application/json", %OpenApiSpex.Schema{type: :object}},
      422 => {"Validation error", "application/json", %OpenApiSpex.Schema{type: :object}}
    }
  )

  def create_vocabulary(conn, params) do
    case Community.create_vocabulary_entry(params) do
      {:ok, vocabulary} ->
        conn
        |> ResponseBuilder.send_success(format_vocabulary(vocabulary), %{}, 201)

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> ResponseBuilder.send_error(
          "validation_failed",
          "Vocabulary validation failed",
          %{errors: format_changeset_errors(changeset)},
          422
        )
    end
  end

  operation(:search_vocabulary,
    summary: "Search vocabulary",
    description: "Searches community vocabulary by phrase or definition",
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
        description: "Maximum results (default: 25)"
      ]
    ],
    responses: %{
      200 => {"Search results", "application/json", %OpenApiSpex.Schema{type: :object}}
    }
  )

  def search_vocabulary(conn, %{"q" => query} = params) do
    limit = params |> Map.get("limit", "25") |> String.to_integer()
    vocabulary = Community.search_vocabulary(query, limit)

    conn
    |> ResponseBuilder.send_success(%{
      data: Enum.map(vocabulary, &format_vocabulary/1),
      query: query
    })
  end

  def search_vocabulary(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> ResponseBuilder.send_error("missing_parameter", "Search query 'q' is required", 400)
  end

  # Private helper functions

  defp format_member(member) do
    %{
      username: member.username,
      display_name: member.display_name,
      first_seen: member.first_seen,
      last_seen: member.last_seen,
      message_count: member.message_count,
      pronunciation_guide: member.pronunciation_guide,
      preferred_name: member.preferred_name
    }
  end

  defp format_pronunciation(override) do
    %{
      username: override.username,
      phonetic: override.phonetic,
      confidence: override.confidence,
      created_by: override.created_by,
      created_at: override.inserted_at
    }
  end

  defp format_vocabulary(vocabulary) do
    %{
      phrase: vocabulary.phrase,
      category: vocabulary.category,
      definition: vocabulary.definition,
      context: vocabulary.context,
      usage_count: vocabulary.usage_count,
      tags: vocabulary.tags,
      first_used: vocabulary.first_used
    }
  end

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
