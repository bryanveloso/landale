defmodule ServerWeb.TwitchController do
  @moduledoc "Controller for Twitch EventSub operations and subscription management."

  use ServerWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias ServerWeb.Schemas

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

  @doc """
  Get Twitch service status.

  Returns the current connection state, session information, and subscription metrics.
  """
  def status(conn, _params) do
    conn
    |> handle_service_result(Server.Services.Twitch.get_status())
  end

  operation(:status,
    summary: "Get Twitch service status",
    description: "Returns current Twitch EventSub connection status and metrics",
    responses: %{
      200 => {"Success", "application/json", Schemas.SuccessResponse},
      503 => {"Service Unavailable", "application/json", Schemas.ErrorResponse}
    }
  )

  operation(:subscriptions,
    summary: "List Twitch EventSub subscriptions",
    description: "Returns all active Twitch EventSub subscriptions",
    responses: %{
      200 => {"Success", "application/json", Schemas.SuccessResponse},
      503 => {"Service Unavailable", "application/json", Schemas.ErrorResponse}
    }
  )

  def subscriptions(conn, _params) do
    conn
    |> handle_service_result(Server.Services.Twitch.list_subscriptions())
  end

  @doc """
  Create a new Twitch EventSub subscription.

  Creates a subscription for the specified event type with the given conditions.
  """
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

  operation(:create_subscription,
    summary: "Create Twitch EventSub subscription",
    description: "Creates a new EventSub subscription for the specified event type",
    request_body: {"Subscription details", "application/json", Schemas.CreateTwitchSubscription, required: true},
    responses: %{
      200 => {"Success", "application/json", Schemas.SuccessResponse},
      400 => {"Bad Request", "application/json", Schemas.ErrorResponse}
    }
  )

  def create_subscription(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{success: false, error: "Missing required parameters: event_type, condition"})
  end

  operation(:delete_subscription,
    summary: "Delete Twitch EventSub subscription",
    description: "Deletes a specific EventSub subscription by ID",
    parameters: [
      id: [in: :path, description: "Subscription ID", type: :string, required: true]
    ],
    responses: %{
      200 => {"Success", "application/json", Schemas.SuccessResponse},
      400 => {"Bad Request", "application/json", Schemas.ErrorResponse}
    }
  )

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

  operation(:subscription_types,
    summary: "Get available EventSub subscription types",
    description: "Returns all available Twitch EventSub subscription types with descriptions and required scopes",
    responses: %{
      200 => {"Success", "application/json", Schemas.TwitchSubscriptionTypes}
    }
  )

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
