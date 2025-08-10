defmodule ServerWeb.TwitchController do
  @moduledoc "Controller for Twitch EventSub operations and subscription management."

  use ServerWeb, :controller
  use OpenApiSpex.ControllerSpecs
  require Logger

  alias ServerWeb.{ResponseBuilder, Schemas}

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
  def create_subscription(conn, %{"type" => event_type, "condition" => condition} = params) do
    opts = Map.get(params, "opts", [])

    case Server.Services.Twitch.create_subscription(event_type, condition, opts) do
      {:ok, subscription} ->
        ResponseBuilder.send_success(conn, subscription)

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> ResponseBuilder.send_error("subscription_failed", reason, 400)
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
    |> ResponseBuilder.send_error("missing_parameters", "Missing required parameters: event_type, condition", 400)
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
        ResponseBuilder.send_success(conn, %{operation: "subscription_deleted"})

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> ResponseBuilder.send_error("subscription_failed", reason, 400)
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

  @doc """
  Handle Twitch EventSub webhook notifications for CLI testing.

  Processes incoming EventSub events from Twitch CLI and forwards them
  to the existing event processing pipeline.

  Security measures:
  - Input validation and sanitization
  - Payload size limits
  - Event type allowlist validation
  """
  def webhook(conn, params) do
    # Validate payload structure and sanitize inputs
    with {:ok, validated_payload} <- validate_webhook_payload(params),
         {:ok, event_type} <- extract_event_type(validated_payload),
         {:ok, event_data} <- extract_event_data(validated_payload),
         :ok <- validate_event_type(event_type) do
      Logger.info("EventSub webhook received",
        event_type: event_type,
        event_id: get_safe_event_id(event_data),
        source: "twitch_cli",
        payload_size: byte_size(:erlang.term_to_binary(params))
      )

      case Server.Services.Twitch.EventHandler.process_event(event_type, event_data) do
        :ok ->
          json(conn, %{success: true, message: "Event processed"})

        {:error, reason} ->
          Logger.error("Event processing failed",
            event_type: event_type,
            reason: sanitize_error_reason(reason)
          )

          conn
          |> put_status(:bad_request)
          |> json(%{success: false, error: "Event processing failed"})
      end
    else
      {:error, reason} ->
        Logger.warning("Invalid EventSub webhook payload",
          reason: reason,
          remote_ip: get_client_ip(conn)
        )

        conn
        |> put_status(:bad_request)
        |> json(%{success: false, error: "Invalid EventSub payload format"})
    end
  end

  operation(:webhook,
    summary: "EventSub webhook endpoint for CLI testing",
    description: "Receives EventSub webhook notifications from Twitch CLI for testing purposes",
    request_body:
      {"EventSub notification", "application/json",
       %OpenApiSpex.Schema{
         type: :object,
         required: ["subscription", "event"],
         properties: %{
           subscription: %OpenApiSpex.Schema{
             type: :object,
             properties: %{
               type: %OpenApiSpex.Schema{type: :string, description: "Event type"}
             }
           },
           event: %OpenApiSpex.Schema{
             type: :object,
             description: "Event data"
           }
         }
       }},
    responses: %{
      200 => {"Success", "application/json", Schemas.SuccessResponse},
      400 => {"Bad Request", "application/json", Schemas.ErrorResponse}
    }
  )

  # Private helper functions for webhook validation

  # Maximum payload size: 1MB (Twitch EventSub payloads are typically < 10KB)
  @max_payload_size 1_048_576

  # Allowed EventSub event types (allowlist approach for security)
  @allowed_event_types [
    "stream.online",
    "stream.offline",
    "channel.follow",
    "channel.subscribe",
    "channel.subscription.gift",
    "channel.cheer",
    "channel.update",
    "channel.chat.message",
    "channel.chat.clear",
    "channel.chat.message_delete",
    "channel.goal.begin",
    "channel.goal.progress",
    "channel.goal.end",
    "channel.raid",
    "channel.channel_points_custom_reward_redemption.add",
    "channel.poll.begin",
    "channel.prediction.begin",
    "channel.hype_train.begin",
    "user.update",
    "user.whisper.message"
  ]

  defp validate_webhook_payload(params) when is_map(params) do
    payload_size = byte_size(:erlang.term_to_binary(params))

    if payload_size > @max_payload_size do
      {:error, "payload_too_large"}
    else
      # Basic structure validation
      if Map.has_key?(params, "subscription") and Map.has_key?(params, "event") do
        {:ok, params}
      else
        {:error, "missing_required_fields"}
      end
    end
  end

  defp validate_webhook_payload(_), do: {:error, "invalid_payload_type"}

  defp extract_event_type(payload) do
    case get_in(payload, ["subscription", "type"]) do
      type when is_binary(type) ->
        # Sanitize: remove null bytes and limit length
        sanitized_type =
          type
          |> String.replace(<<0>>, "")
          |> String.slice(0, 255)

        {:ok, sanitized_type}

      _ ->
        {:error, "invalid_event_type"}
    end
  end

  defp extract_event_data(payload) do
    case payload["event"] do
      data when is_map(data) ->
        {:ok, data}

      _ ->
        {:error, "invalid_event_data"}
    end
  end

  defp validate_event_type(event_type) do
    if event_type in @allowed_event_types do
      :ok
    else
      {:error, "unsupported_event_type"}
    end
  end

  defp get_safe_event_id(event_data) when is_map(event_data) do
    case event_data["id"] do
      id when is_binary(id) -> String.slice(id, 0, 255)
      _ -> "unknown"
    end
  end

  defp get_safe_event_id(_), do: "unknown"

  defp sanitize_error_reason(reason) when is_binary(reason) do
    reason
    |> String.replace(<<0>>, "")
    |> String.slice(0, 500)
  end

  defp sanitize_error_reason(_reason), do: "processing_error"

  defp get_client_ip(conn) do
    case Plug.Conn.get_peer_data(conn) do
      %{address: address} -> :inet.ntoa(address) |> to_string()
      _ -> "unknown"
    end
  end
end
