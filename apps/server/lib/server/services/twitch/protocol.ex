defmodule Server.Services.Twitch.Protocol do
  @moduledoc """
  Twitch EventSub WebSocket protocol handling.

  This module handles encoding and decoding of Twitch EventSub messages,
  including session management messages and event notifications.

  ## Message Types

  - `session_welcome` - Initial message with session ID
  - `session_keepalive` - Periodic keepalive messages  
  - `notification` - Event notifications (follows, subs, etc.)
  - `session_reconnect` - Request to reconnect to new URL
  - `revocation` - Subscription revocation notice

  ## Message Structure

  All messages follow this structure:
  ```json
  {
    "metadata": {
      "message_id": "unique-id",
      "message_type": "notification",
      "message_timestamp": "2023-01-01T00:00:00Z",
      "subscription_type": "channel.follow",
      "subscription_version": "1"
    },
    "payload": {
      // Type-specific payload
    }
  }
  ```
  """

  require Logger

  @doc """
  Decodes a Twitch EventSub message from JSON.

  ## Returns
  - `{:ok, message}` - Successfully decoded message
  - `{:error, reason}` - Decoding failed
  """
  @spec decode_message(binary()) :: {:ok, map()} | {:error, term()}
  def decode_message(data) when is_binary(data) do
    case Jason.decode(data) do
      {:ok, message} ->
        validate_message(message)

      {:error, error} ->
        Logger.error("Failed to decode Twitch message",
          error: inspect(error),
          data: String.slice(data, 0..200)
        )

        {:error, {:decode_error, error}}
    end
  end

  @doc """
  Validates a decoded Twitch message has required fields.
  """
  @spec validate_message(map()) :: {:ok, map()} | {:error, term()}
  def validate_message(%{"metadata" => metadata} = message) when is_map(metadata) do
    required_metadata = ["message_id", "message_type", "message_timestamp"]

    if Enum.all?(required_metadata, &Map.has_key?(metadata, &1)) do
      {:ok, message}
    else
      {:error, {:invalid_message, "Missing required metadata fields"}}
    end
  end

  def validate_message(_) do
    {:error, {:invalid_message, "Message must have metadata"}}
  end

  @doc """
  Extracts the message type from a decoded message.
  """
  @spec get_message_type(map()) :: binary() | nil
  def get_message_type(%{"metadata" => %{"message_type" => type}}), do: type
  def get_message_type(_), do: nil

  @doc """
  Extracts the session ID from a session_welcome message.
  """
  @spec get_session_id(map()) :: binary() | nil
  def get_session_id(%{
        "metadata" => %{"message_type" => "session_welcome"},
        "payload" => %{"session" => %{"id" => session_id}}
      }) do
    session_id
  end

  def get_session_id(_), do: nil

  @doc """
  Extracts subscription info from a notification message.
  """
  @spec get_subscription_info(map()) :: map() | nil
  def get_subscription_info(%{
        "metadata" => %{
          "subscription_type" => type,
          "subscription_version" => version
        },
        "payload" => %{"subscription" => subscription}
      }) do
    %{
      type: type,
      version: version,
      id: subscription["id"],
      status: subscription["status"],
      created_at: subscription["created_at"],
      cost: subscription["cost"]
    }
  end

  def get_subscription_info(_), do: nil

  @doc """
  Extracts event data from a notification message.
  """
  @spec get_event_data(map()) :: map() | nil
  def get_event_data(%{
        "metadata" => %{"message_type" => "notification"},
        "payload" => %{"event" => event}
      }) do
    event
  end

  def get_event_data(_), do: nil

  @doc """
  Checks if a message is a keepalive message.
  """
  @spec keepalive?(map()) :: boolean()
  def keepalive?(%{"metadata" => %{"message_type" => "session_keepalive"}}), do: true
  def keepalive?(_), do: false

  @doc """
  Checks if a message requires a session.
  """
  @spec requires_session?(map()) :: boolean()
  def requires_session?(%{"metadata" => %{"message_type" => type}}) do
    type in ["notification", "session_keepalive", "revocation"]
  end

  def requires_session?(_), do: false

  @doc """
  Formats a message for logging (truncates large payloads).
  """
  @spec format_for_logging(map()) :: map()
  def format_for_logging(message) do
    case message do
      %{"payload" => %{"event" => event} = payload} = msg when is_map(event) ->
        # Truncate event data if too large
        truncated_event =
          if map_size(event) > 10 do
            event
            |> Enum.take(10)
            |> Enum.into(%{})
            |> Map.put("_truncated", true)
          else
            event
          end

        put_in(msg, ["payload", "event"], truncated_event)

      _ ->
        message
    end
  end
end
