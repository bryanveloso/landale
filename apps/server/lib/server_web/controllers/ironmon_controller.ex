defmodule ServerWeb.IronmonController do
  @moduledoc """
  API endpoints for IronMON challenge data and statistics.
  """

  use ServerWeb, :controller

  alias Server.Ironmon

  def list_challenges(conn, _params) do
    challenges = Ironmon.list_challenges()
    json(conn, challenges)
  end

  def list_checkpoints(conn, %{"id" => challenge_id}) do
    case Integer.parse(challenge_id) do
      {id, ""} ->
        checkpoints = Ironmon.list_checkpoints_for_challenge(id)
        json(conn, checkpoints)

      _ ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Invalid challenge ID"})
    end
  end

  def checkpoint_stats(conn, %{"id" => checkpoint_id}) do
    case Integer.parse(checkpoint_id) do
      {id, ""} ->
        stats = Ironmon.get_checkpoint_stats(id)
        json(conn, stats)

      _ ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Invalid checkpoint ID"})
    end
  end

  def recent_results(conn, params) do
    limit = Map.get(params, "limit", "10") |> parse_integer(10)
    cursor = Map.get(params, "cursor") |> parse_optional_integer()

    results = Ironmon.get_recent_results(limit, cursor)
    json(conn, results)
  end

  def active_challenge(conn, %{"id" => seed_id}) do
    case Integer.parse(seed_id) do
      {id, ""} ->
        case Ironmon.get_active_challenge(id) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Seed not found"})

          challenge ->
            json(conn, challenge)
        end

      _ ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Invalid seed ID"})
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
