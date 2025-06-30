defmodule ServerWeb.TwitchController do
  @moduledoc "Controller for Twitch EventSub operations and subscription management."

  use ServerWeb, :controller

  @subscription_types %{
    stream: [
      %{type: "stream.online", description: "Stream goes live", scopes: [], version: "1"},
      %{type: "stream.offline", description: "Stream goes offline", scopes: [], version: "1"}
    ],
    channel: [
      %{type: "channel.update", description: "Channel information updates", scopes: [], version: "1"},
      %{type: "channel.follow", description: "New follower", scopes: ["moderator:read:followers"], version: "2"},
      %{type: "channel.subscribe", description: "New subscriber", scopes: ["channel:read:subscriptions"], version: "1"},
      %{type: "channel.cheer", description: "Bits cheered", scopes: ["bits:read"], version: "1"},
      %{type: "channel.raid", description: "Incoming raid", scopes: [], version: "1"},
      %{
        type: "channel.channel_points_custom_reward_redemption.add",
        description: "Channel points reward redeemed",
        scopes: ["channel:read:redemptions"],
        version: "1"
      },
      %{type: "channel.poll.begin", description: "Poll started", scopes: ["channel:read:polls"], version: "1"},
      %{
        type: "channel.prediction.begin",
        description: "Prediction started",
        scopes: ["channel:read:predictions"],
        version: "1"
      },
      %{
        type: "channel.hype_train.begin",
        description: "Hype train started",
        scopes: ["channel:read:hype_train"],
        version: "1"
      }
    ],
    user: [
      %{type: "user.update", description: "User information updated", scopes: [], version: "1"},
      %{
        type: "user.whisper.message",
        description: "Whisper message received",
        scopes: ["user:read:whispers"],
        version: "1"
      }
    ]
  }

  def status(conn, _params) do
    conn
    |> handle_service_result(Server.Services.Twitch.get_status())
  end

  def subscriptions(conn, _params) do
    conn
    |> handle_service_result(Server.Services.Twitch.list_subscriptions())
  end

  def create_subscription(conn, %{"event_type" => event_type, "condition" => condition} = params) do
    opts = Map.get(params, "opts", [])

    case Server.Services.Twitch.create_subscription(event_type, condition, opts) do
      {:ok, subscription} ->
        json(conn, %{success: true, data: subscription})

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{success: false, error: reason})
    end
  end

  def create_subscription(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{success: false, error: "Missing required parameters: event_type, condition"})
  end

  def delete_subscription(conn, %{"id" => subscription_id}) do
    case Server.Services.Twitch.delete_subscription(subscription_id) do
      :ok ->
        json(conn, %{success: true, message: "Subscription deleted"})

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{success: false, error: reason})
    end
  end

  def delete_subscription(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{success: false, error: "Missing required parameter: id"})
  end

  def subscription_types(conn, _params) do
    json(conn, %{success: true, data: @subscription_types})
  end

  # Helper function to reduce repetition in service result handling
  defp handle_service_result(conn, {:ok, data}) do
    json(conn, %{success: true, data: data})
  end

  defp handle_service_result(conn, {:error, reason}) do
    conn
    |> put_status(:service_unavailable)
    |> json(%{success: false, error: reason})
  end
end
