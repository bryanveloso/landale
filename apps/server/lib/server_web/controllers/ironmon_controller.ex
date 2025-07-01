defmodule ServerWeb.IronmonController do
  @moduledoc """
  API endpoints for IronMON challenge data and statistics.
  """

  use ServerWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Server.Ironmon
  alias ServerWeb.Schemas

  operation(:list_challenges,
    summary: "List IronMON challenges",
    description: "Returns all available IronMON challenges",
    responses: %{
      200 => {"Success", "application/json", Schemas.SuccessResponse}
    }
  )

  def list_challenges(conn, _params) do
    challenges = Ironmon.list_challenges()
    json(conn, %{success: true, data: challenges})
  end

  operation(:list_checkpoints,
    summary: "List challenge checkpoints",
    description: "Returns all checkpoints for a specific challenge",
    parameters: [
      id: [in: :path, description: "Challenge ID", type: :integer, required: true]
    ],
    responses: %{
      200 => {"Success", "application/json", Schemas.SuccessResponse},
      400 => {"Bad Request", "application/json", Schemas.ErrorResponse}
    }
  )

  def list_checkpoints(conn, %{"id" => challenge_id}) do
    case Integer.parse(challenge_id) do
      {id, ""} ->
        checkpoints = Ironmon.list_checkpoints_for_challenge(id)
        json(conn, %{success: true, data: checkpoints})

      _ ->
        conn
        |> put_status(:bad_request)
        |> json(%{success: false, error: "Invalid challenge ID"})
    end
  end

  operation(:checkpoint_stats,
    summary: "Get checkpoint statistics",
    description: "Returns statistics for a specific checkpoint",
    parameters: [
      id: [in: :path, description: "Checkpoint ID", type: :integer, required: true]
    ],
    responses: %{
      200 => {"Success", "application/json", Schemas.SuccessResponse},
      400 => {"Bad Request", "application/json", Schemas.ErrorResponse}
    }
  )

  def checkpoint_stats(conn, %{"id" => checkpoint_id}) do
    case Integer.parse(checkpoint_id) do
      {id, ""} ->
        stats = Ironmon.get_checkpoint_stats(id)
        json(conn, %{success: true, data: stats})

      _ ->
        conn
        |> put_status(:bad_request)
        |> json(%{success: false, error: "Invalid checkpoint ID"})
    end
  end

  operation(:recent_results,
    summary: "Get recent IronMON results",
    description: "Returns recent challenge results with optional pagination",
    parameters: [
      limit: [in: :query, description: "Number of results to return", type: :integer, required: false],
      cursor: [in: :query, description: "Pagination cursor", type: :integer, required: false]
    ],
    responses: %{
      200 => {"Success", "application/json", Schemas.SuccessResponse}
    }
  )

  def recent_results(conn, params) do
    limit = Map.get(params, "limit", "10") |> parse_integer(10)
    cursor = Map.get(params, "cursor") |> parse_optional_integer()

    results = Ironmon.get_recent_results(limit, cursor)
    json(conn, %{success: true, data: results})
  end

  operation(:active_challenge,
    summary: "Get active challenge for seed",
    description: "Returns the active challenge associated with a specific seed ID",
    parameters: [
      id: [in: :path, description: "Seed ID", type: :integer, required: true]
    ],
    responses: %{
      200 => {"Success", "application/json", Schemas.SuccessResponse},
      400 => {"Bad Request", "application/json", Schemas.ErrorResponse},
      404 => {"Not Found", "application/json", Schemas.ErrorResponse}
    }
  )

  def active_challenge(conn, %{"id" => seed_id}) do
    case Integer.parse(seed_id) do
      {id, ""} ->
        case Ironmon.get_active_challenge(id) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(%{success: false, error: "Seed not found"})

          challenge ->
            json(conn, %{success: true, data: challenge})
        end

      _ ->
        conn
        |> put_status(:bad_request)
        |> json(%{success: false, error: "Invalid seed ID"})
    end
  end

  defp parse_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {num, ""} -> num
      _ -> default
    end
  end

  defp parse_integer(_, default), do: default

  defp parse_optional_integer(nil), do: nil

  defp parse_optional_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {num, ""} -> num
      _ -> nil
    end
  end
end
