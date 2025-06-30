defmodule Server.Services.Twitch.EventSubManager do
  @moduledoc """
  Twitch EventSub subscription management via HTTP API.

  Handles creation, deletion, and lifecycle management of Twitch EventSub subscriptions.
  Includes scope validation, cost tracking, and duplicate prevention.

  ## Features

  - EventSub subscription creation and deletion via HTTP API
  - Scope validation before subscription attempts
  - Subscription cost and limit tracking
  - Duplicate subscription prevention
  - Support for different API versions per event type
  - Default subscription setup for common events

  ## Event Types Supported

  - `stream.online` / `stream.offline` - Stream state changes
  - `channel.follow` - New followers (requires moderator scope)
  - `channel.subscribe` - New subscribers
  - `channel.subscription.gift` - Gift subscriptions
  - `channel.cheer` - Bits cheered
  """

  require Logger

  @default_subscriptions [
    {"stream.online", [], []},
    {"stream.offline", [], []},
    {"channel.follow", ["moderator:read:followers"], []},
    {"channel.subscribe", ["channel:read:subscriptions"], []},
    {"channel.subscription.gift", ["channel:read:subscriptions"], []},
    {"channel.cheer", ["bits:read"], []}
  ]

  @doc """
  Creates a Twitch EventSub subscription via HTTP API.

  ## Parameters
  - `state` - Twitch service state containing session_id and OAuth client
  - `event_type` - EventSub event type (e.g. "channel.update")
  - `condition` - Subscription condition map (e.g. %{"broadcaster_user_id" => "123"})
  - `opts` - Additional options (currently unused)

  ## Returns
  - `{:ok, subscription}` - Subscription created successfully
  - `{:error, reason}` - Creation failed
  """
  @spec create_subscription(map(), binary(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def create_subscription(state, event_type, condition, _opts \\ []) do
    url = "https://api.twitch.tv/helix/eventsub/subscriptions"

    headers = [
      {"authorization", "Bearer #{state.oauth_client.token.access_token}"},
      {"client-id", state.oauth_client.client_id},
      {"content-type", "application/json"}
    ]

    transport = %{
      "method" => "websocket",
      "session_id" => state.session_id
    }

    # Use version 2 for channel.follow, version 1 for others
    version = if event_type == "channel.follow", do: "2", else: "1"

    body = %{
      "type" => event_type,
      "version" => version,
      "condition" => condition,
      "transport" => transport
    }

    json_body = Jason.encode!(body)

    Logger.debug("Creating EventSub subscription",
      event_type: event_type,
      condition: condition,
      session_id: state.session_id,
      version: version
    )

    # Use retry strategy for rate limit handling
    case Server.RetryStrategy.retry_with_rate_limit_detection(fn ->
           make_subscription_request(url, headers, json_body)
         end) do
      {:ok, response_body} ->
        case Jason.decode(List.to_string(response_body)) do
          {:ok, %{"data" => [subscription]}} ->
            Logger.info("EventSub subscription created successfully",
              event_type: event_type,
              subscription_id: subscription["id"],
              status: subscription["status"],
              cost: subscription["cost"] || 1
            )

            Server.Telemetry.twitch_subscription_created(event_type)
            {:ok, subscription}

          {:ok, response} ->
            Logger.error("Unexpected EventSub subscription response format",
              event_type: event_type,
              response: inspect(response, limit: :infinity)
            )

            {:error, "Unexpected response format"}

          {:error, reason} ->
            Logger.error("Failed to parse EventSub subscription response",
              event_type: event_type,
              reason: inspect(reason),
              body: List.to_string(response_body)
            )

            {:error, "Failed to parse response: #{inspect(reason)}"}
        end

      {:error, reason} ->
        Logger.error("EventSub subscription creation failed after retries",
          event_type: event_type,
          reason: inspect(reason)
        )

        Server.Telemetry.twitch_subscription_failed(event_type, inspect(reason))
        {:error, reason}
    end
  end

  # Private helper function for making subscription requests with proper error handling
  defp make_subscription_request(url, headers, json_body) do
    http_config = Server.NetworkConfig.http_config()

    case :httpc.request(
           :post,
           {url, Enum.map(headers, fn {k, v} -> {to_charlist(k), to_charlist(v)} end), ~c"application/json",
            to_charlist(json_body)},
           [{:timeout, http_config.timeout}],
           []
         ) do
      {:ok, {{_version, 202, _reason_phrase}, _headers, response_body}} ->
        {:ok, response_body}

      {:ok, {{_version, 429, _reason_phrase}, _headers, response_body}} ->
        {:error, {:http_error, 429, List.to_string(response_body)}}

      {:ok, {{_version, status, _reason_phrase}, _headers, response_body}} when status >= 500 ->
        {:error, {:http_error, status, List.to_string(response_body)}}

      {:ok, {{_version, status, _reason_phrase}, _headers, response_body}} ->
        response_string = List.to_string(response_body)

        case Jason.decode(response_string) do
          {:ok, %{"message" => message}} -> {:error, message}
          {:ok, %{"error" => error}} -> {:error, error}
          _ -> {:error, "HTTP #{status}: #{response_string}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Deletes a Twitch EventSub subscription via HTTP API.

  ## Parameters
  - `state` - Twitch service state containing OAuth client
  - `subscription_id` - ID of subscription to delete

  ## Returns
  - `:ok` - Subscription deleted successfully
  - `{:error, reason}` - Deletion failed
  """
  @spec delete_subscription(map(), binary()) :: :ok | {:error, term()}
  def delete_subscription(state, subscription_id) do
    url = "https://api.twitch.tv/helix/eventsub/subscriptions?id=#{subscription_id}"

    headers = [
      {"authorization", "Bearer #{state.oauth_client.token.access_token}"},
      {"client-id", state.oauth_client.client_id}
    ]

    Logger.debug("Deleting EventSub subscription", subscription_id: subscription_id)

    case Server.RetryStrategy.retry(fn ->
           make_delete_request(url, headers)
         end) do
      {:ok, :success} ->
        Logger.info("EventSub subscription deleted successfully", subscription_id: subscription_id)
        :ok

      {:error, reason} ->
        Logger.error("EventSub subscription deletion failed after retries",
          subscription_id: subscription_id,
          reason: inspect(reason)
        )

        {:error, reason}
    end
  end

  # Private helper function for making delete requests with proper error handling
  defp make_delete_request(url, headers) do
    http_config = Server.NetworkConfig.http_config()

    case :httpc.request(
           :delete,
           {url, Enum.map(headers, fn {k, v} -> {to_charlist(k), to_charlist(v)} end)},
           [{:timeout, http_config.timeout}],
           []
         ) do
      {:ok, {{_version, 204, _reason_phrase}, _headers, _body}} ->
        {:ok, :success}

      {:ok, {{_version, 429, _reason_phrase}, _headers, response_body}} ->
        {:error, {:http_error, 429, List.to_string(response_body)}}

      {:ok, {{_version, status, _reason_phrase}, _headers, response_body}} when status >= 500 ->
        {:error, {:http_error, status, List.to_string(response_body)}}

      {:ok, {{_version, status, _reason_phrase}, _headers, response_body}} ->
        response_string = List.to_string(response_body)
        {:error, "HTTP #{status}: #{response_string}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Creates default EventSub subscriptions for common events.

  ## Parameters
  - `state` - Twitch service state containing user_id and scopes

  ## Returns
  - `{successful_count, failed_count}` - Tuple of success/failure counts
  """
  @spec create_default_subscriptions(map()) :: {integer(), integer()}
  def create_default_subscriptions(state) do
    if state.user_id do
      subscriptions_with_conditions =
        Enum.map(@default_subscriptions, fn
          {event_type, required_scopes, opts} ->
            condition =
              case event_type do
                "channel.follow" ->
                  %{"broadcaster_user_id" => state.user_id, "moderator_user_id" => state.user_id}

                _ ->
                  %{"broadcaster_user_id" => state.user_id}
              end

            {event_type, condition, required_scopes, opts}
        end)

      Enum.reduce(subscriptions_with_conditions, {0, 0}, fn {event_type, condition, required_scopes, opts},
                                                            {success, failed} ->
        if validate_scopes_for_subscription(state.scopes, required_scopes) do
          case create_subscription(state, event_type, condition, opts) do
            {:ok, subscription} ->
              Logger.info("Created default EventSub subscription",
                event_type: event_type,
                subscription_id: subscription["id"],
                status: subscription["status"],
                cost: subscription["cost"] || 1
              )

              {success + 1, failed}

            {:error, reason} ->
              Logger.warning("Failed to create default EventSub subscription",
                event_type: event_type,
                reason: reason
              )

              # Provide specific guidance for known issues
              case event_type do
                "channel.follow" ->
                  cond do
                    String.contains?(to_string(reason), "Forbidden") ->
                      Logger.info("Channel follow subscription failed",
                        reason: "Forbidden - broadcaster may need explicit moderator verification",
                        note: "This is common when using broadcaster token for moderator-required subscriptions",
                        workaround: "Consider obtaining separate moderator authorization or treating as optional"
                      )

                    String.contains?(to_string(reason), "unauthorized") ->
                      Logger.info("Channel follow subscription failed",
                        reason: "Unauthorized - token may need additional verification",
                        scope_present: MapSet.member?(state.scopes || MapSet.new(), "moderator:read:followers"),
                        note: "Follow subscriptions require special broadcaster/moderator relationship"
                      )

                    true ->
                      Logger.info("Channel follow subscription failed",
                        reason: reason,
                        condition: inspect(condition),
                        user_id: state.user_id,
                        note: "Follow subscriptions require special broadcaster/moderator relationship"
                      )
                  end

                _ ->
                  Logger.debug("Subscription failed for #{event_type}", reason: reason)
              end

              {success, failed + 1}
          end
        else
          Logger.info("Skipping EventSub subscription due to missing scopes",
            event_type: event_type,
            required_scopes: required_scopes,
            user_scopes: MapSet.to_list(state.scopes || MapSet.new())
          )

          {success, failed + 1}
        end
      end)
    else
      Logger.error("Cannot create subscriptions: user_id not available")
      {0, 1}
    end
  end

  @doc """
  Validates that user has required scopes for a subscription.

  ## Parameters
  - `user_scopes` - MapSet of user's OAuth scopes
  - `required_scopes` - List of required scopes for the subscription

  ## Returns
  - `true` - User has all required scopes
  - `false` - User is missing required scopes
  """
  @spec validate_scopes_for_subscription(MapSet.t() | nil, list(binary())) :: boolean()
  def validate_scopes_for_subscription(user_scopes, required_scopes)
  def validate_scopes_for_subscription(_user_scopes, []), do: true
  def validate_scopes_for_subscription(nil, _required_scopes), do: false

  def validate_scopes_for_subscription(user_scopes, required_scopes) do
    Enum.all?(required_scopes, fn scope -> MapSet.member?(user_scopes, scope) end)
  end

  @doc """
  Generates a unique key for subscription deduplication.

  ## Parameters
  - `event_type` - EventSub event type
  - `condition` - Subscription condition map

  ## Returns
  - Unique string key for the subscription
  """
  @spec generate_subscription_key(binary(), map()) :: binary()
  def generate_subscription_key(event_type, condition) when is_map(condition) do
    # Sort condition keys for consistent key generation
    sorted_condition =
      condition
      |> Enum.sort()
      |> Enum.into(%{})

    "#{event_type}:#{Jason.encode!(sorted_condition)}"
  end
end
