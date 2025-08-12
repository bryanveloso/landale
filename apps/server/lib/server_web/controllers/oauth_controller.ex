defmodule ServerWeb.OAuthController do
  @moduledoc """
  OAuth token management controller.

  Handles OAuth tokens for Twitch integration with two approaches:
  - Direct token upload for simple single-user setup (recommended)
  - Traditional OAuth flow with redirects (legacy, kept for compatibility)

  All endpoints secured by Tailscale network boundary.
  """

  use ServerWeb, :controller
  alias Server.OAuthService
  require Logger

  @doc """
  Get current OAuth token status
  """
  def status(conn, _params) do
    case OAuthService.get_token_info(:twitch) do
      {:ok, info} ->
        is_valid = DateTime.compare(info.expires_at, DateTime.utc_now()) == :gt

        json(conn, %{
          connected: is_valid,
          expires_at: info.expires_at,
          valid: is_valid
        })

      _ ->
        json(conn, %{connected: false})
    end
  end

  @doc """
  Manually refresh the OAuth token
  """
  def refresh(conn, _params) do
    case OAuthService.refresh_token(:twitch) do
      {:ok, _} ->
        json(conn, %{success: true})

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{success: false, error: inspect(reason)})
    end
  end

  @doc """
  Upload OAuth tokens directly (bypasses OAuth flow).
  Accepts complete token JSON from Mix CLI task.
  """
  def upload(conn, params) when is_map(params) do
    with {:ok, access} <- Map.fetch(params, "access_token"),
         {:ok, refresh} <- Map.fetch(params, "refresh_token") do
      # Calculate expiry from expires_in or use default
      expires_at =
        case Map.get(params, "expires_in") do
          nil -> DateTime.add(DateTime.utc_now(), 3600, :second)
          expires_in -> DateTime.add(DateTime.utc_now(), expires_in, :second)
        end

      # Parse scopes - handle both string and array formats
      scopes =
        case Map.get(params, "scope") || Map.get(params, "scopes") do
          nil -> []
          scopes when is_list(scopes) -> scopes
          scope_string when is_binary(scope_string) -> String.split(scope_string, " ")
          _ -> []
        end

      # Store the complete token information
      case OAuthService.store_tokens(:twitch, %{
             access_token: access,
             refresh_token: refresh,
             expires_at: expires_at,
             scopes: scopes
           }) do
        :ok ->
          Logger.info("OAuth tokens uploaded successfully")
          json(conn, %{success: true, message: "Tokens stored successfully"})

        {:error, reason} ->
          Logger.error("Failed to store uploaded tokens: #{inspect(reason)}")

          conn
          |> put_status(:bad_request)
          |> json(%{success: false, error: "Failed to store tokens"})
      end
    else
      :error ->
        conn
        |> put_status(:bad_request)
        |> json(%{success: false, error: "Missing required fields: access_token and refresh_token"})
    end
  end
end
