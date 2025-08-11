defmodule ServerWeb.OAuthController do
  @moduledoc """
  OAuth management controller for handling OAuth authorization flow.

  Provides endpoints for OAuth status, authorization, callback handling,
  and token refresh. Secured by Tailscale network - no application-level
  authentication required.
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
        json(conn, %{
          connected: true,
          expires_at: info.expires_at,
          valid: DateTime.compare(info.expires_at, DateTime.utc_now()) == :gt
        })

      _ ->
        json(conn, %{connected: false})
    end
  end

  @doc """
  Start OAuth authorization flow - redirects to Twitch
  """
  def authorize(conn, _params) do
    client_id = System.get_env("TWITCH_CLIENT_ID")
    redirect_uri = "http://saya:7175/api/oauth/callback"

    scopes =
      "channel:read:subscriptions channel:manage:broadcast channel:read:redemptions moderator:read:followers bits:read chat:read chat:edit"

    auth_url =
      "https://id.twitch.tv/oauth2/authorize?client_id=#{client_id}&redirect_uri=#{URI.encode_www_form(redirect_uri)}&response_type=code&scope=#{URI.encode_www_form(scopes)}"

    redirect(conn, external: auth_url)
  end

  @doc """
  Handle OAuth callback from Twitch
  """
  def callback(conn, %{"code" => code}) do
    client_id = System.get_env("TWITCH_CLIENT_ID")
    client_secret = System.get_env("TWITCH_CLIENT_SECRET")
    redirect_uri = "http://saya:7175/api/oauth/callback"

    # Exchange code for tokens
    case exchange_code_for_tokens(code, client_id, client_secret, redirect_uri) do
      {:ok, token_data} ->
        # Store tokens
        expires_at = DateTime.add(DateTime.utc_now(), token_data["expires_in"], :second)

        OAuthService.store_tokens(:twitch, %{
          access_token: token_data["access_token"],
          refresh_token: token_data["refresh_token"],
          expires_at: expires_at,
          scopes: String.split(token_data["scope"] || "", " ")
        })

        # Redirect to dashboard
        redirect(conn, external: "http://zelan:3000/oauth?success=true")

      {:error, reason} ->
        Logger.error("OAuth callback failed: #{inspect(reason)}")
        redirect(conn, external: "http://zelan:3000/oauth?error=#{URI.encode_www_form(inspect(reason))}")
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

  defp exchange_code_for_tokens(code, client_id, client_secret, redirect_uri) do
    url = "https://id.twitch.tv/oauth2/token"

    body =
      URI.encode_query(%{
        client_id: client_id,
        client_secret: client_secret,
        code: code,
        grant_type: "authorization_code",
        redirect_uri: redirect_uri
      })

    headers = [{"Content-Type", "application/x-www-form-urlencoded"}]

    case HTTPoison.post(url, body, headers) do
      {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
        {:ok, Jason.decode!(response_body)}

      {:ok, %HTTPoison.Response{body: response_body}} ->
        {:error, response_body}

      {:error, error} ->
        {:error, error}
    end
  end
end
