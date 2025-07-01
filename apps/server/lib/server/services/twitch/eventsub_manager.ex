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

  ### Stream Events
  - `stream.online` / `stream.offline` - Stream state changes

  ### Channel Events
  - `channel.update` - Channel information updates
  - `channel.follow` - New followers (requires moderator scope)
  - `channel.ad_break.begin` - Ad break start
  - `channel.chat.clear` - Chat cleared
  - `channel.chat.clear_user_messages` - User messages cleared
  - `channel.chat.message` - Chat messages
  - `channel.chat.message_delete` - Message deletions
  - `channel.chat.notification` - Chat notifications
  - `channel.chat_settings.update` - Chat settings updates
  - `channel.subscribe` - New subscribers
  - `channel.subscription.end` - Subscription end
  - `channel.subscription.gift` - Gift subscriptions
  - `channel.subscription.message` - Subscription messages
  - `channel.cheer` - Bits cheered
  - `channel.raid` - Incoming raids
  - `channel.ban` / `channel.unban` - User bans/unbans
  - `channel.moderator.add` / `channel.moderator.remove` - Moderator changes
  - `channel.guest_star_session.begin` / `channel.guest_star_session.end` - Guest star sessions
  - `channel.guest_star_guest.update` - Guest star updates
  - `channel.channel_points_custom_reward.add` - Custom reward creation
  - `channel.channel_points_custom_reward.update` - Custom reward updates
  - `channel.channel_points_custom_reward.remove` - Custom reward removal
  - `channel.channel_points_custom_reward_redemption.add` - Reward redemptions
  - `channel.channel_points_custom_reward_redemption.update` - Redemption updates
  - `channel.poll.begin` / `channel.poll.progress` / `channel.poll.end` - Polls
  - `channel.prediction.begin` / `channel.prediction.progress` / `channel.prediction.lock` / `channel.prediction.end` - Predictions
  - `channel.charity_campaign.donate` / `channel.charity_campaign.progress` - Charity campaigns
  - `channel.hype_train.begin` / `channel.hype_train.progress` / `channel.hype_train.end` - Hype trains
  - `channel.shield_mode.begin` / `channel.shield_mode.end` - Shield mode
  - `channel.shoutout.create` / `channel.shoutout.receive` - Shoutouts
  - `channel.suspicious_user.message` / `channel.suspicious_user.update` - Suspicious users
  - `channel.vip.add` / `channel.vip.remove` - VIP changes
  - `channel.warning.acknowledge` / `channel.warning.send` - Warnings
  - `channel.goal.begin` / `channel.goal.progress` / `channel.goal.end` - Goals

  ### User Events
  - `user.authorization.grant` / `user.authorization.revoke` - Authorization changes
  - `user.update` - User information updates
  - `user.whisper.message` - Whisper messages

  ### Drop Events
  - `drop.entitlement.grant` - Drop entitlements

  ### Extension Events
  - `extension.bits_transaction.create` - Extension bits transactions
  """

  require Logger

  @default_subscriptions [
    # Stream events (no scopes required)
    {"stream.online", [], []},
    {"stream.offline", [], []},

    # Channel information updates
    {"channel.update", [], []},

    # Follow events (requires moderator scope)
    {"channel.follow", ["moderator:read:followers"], []},

    # Subscription events
    {"channel.subscribe", ["channel:read:subscriptions"], []},
    {"channel.subscription.end", ["channel:read:subscriptions"], []},
    {"channel.subscription.gift", ["channel:read:subscriptions"], []},
    {"channel.subscription.message", ["channel:read:subscriptions"], []},

    # Bits/Cheer events
    {"channel.cheer", ["bits:read"], []},

    # Raid events
    {"channel.raid", [], []},

    # Moderation events
    {"channel.ban", ["channel:moderate"], []},
    {"channel.unban", ["channel:moderate"], []},
    {"channel.moderator.add", ["moderation:read"], []},
    {"channel.moderator.remove", ["moderation:read"], []},

    # Chat events
    {"channel.chat.clear", ["moderator:read:chat_settings"], []},
    {"channel.chat.clear_user_messages", ["moderator:read:chat_settings"], []},
    {"channel.chat.message", ["user:read:chat"], []},
    {"channel.chat.message_delete", ["moderator:read:chat_settings"], []},
    {"channel.chat.notification", ["user:read:chat"], []},
    {"channel.chat_settings.update", ["moderator:read:chat_settings"], []},

    # Channel Points events
    {"channel.channel_points_custom_reward.add", ["channel:read:redemptions"], []},
    {"channel.channel_points_custom_reward.update", ["channel:read:redemptions"], []},
    {"channel.channel_points_custom_reward.remove", ["channel:read:redemptions"], []},
    {"channel.channel_points_custom_reward_redemption.add", ["channel:read:redemptions"], []},
    {"channel.channel_points_custom_reward_redemption.update", ["channel:read:redemptions"], []},

    # Poll events
    {"channel.poll.begin", ["channel:read:polls"], []},
    {"channel.poll.progress", ["channel:read:polls"], []},
    {"channel.poll.end", ["channel:read:polls"], []},

    # Prediction events
    {"channel.prediction.begin", ["channel:read:predictions"], []},
    {"channel.prediction.progress", ["channel:read:predictions"], []},
    {"channel.prediction.lock", ["channel:read:predictions"], []},
    {"channel.prediction.end", ["channel:read:predictions"], []},

    # Charity events
    {"channel.charity_campaign.donate", ["channel:read:charity"], []},
    {"channel.charity_campaign.progress", ["channel:read:charity"], []},

    # Hype Train events
    {"channel.hype_train.begin", ["channel:read:hype_train"], []},
    {"channel.hype_train.progress", ["channel:read:hype_train"], []},
    {"channel.hype_train.end", ["channel:read:hype_train"], []},

    # Goal events
    {"channel.goal.begin", ["channel:read:goals"], []},
    {"channel.goal.progress", ["channel:read:goals"], []},
    {"channel.goal.end", ["channel:read:goals"], []},

    # Shield mode events
    {"channel.shield_mode.begin", ["moderator:read:shield_mode"], []},
    {"channel.shield_mode.end", ["moderator:read:shield_mode"], []},

    # Shoutout events
    {"channel.shoutout.create", ["moderator:read:shoutouts"], []},
    {"channel.shoutout.receive", ["moderator:read:shoutouts"], []},

    # VIP events
    {"channel.vip.add", ["channel:read:vips"], []},
    {"channel.vip.remove", ["channel:read:vips"], []},

    # Warning events
    {"channel.warning.acknowledge", ["moderator:read:warnings"], []},
    {"channel.warning.send", ["moderator:read:warnings"], []},

    # Suspicious user events
    {"channel.suspicious_user.message", ["moderator:read:suspicious_users"], []},
    {"channel.suspicious_user.update", ["moderator:read:suspicious_users"], []},

    # Guest star events
    {"channel.guest_star_session.begin", ["channel:read:guest_star"], []},
    {"channel.guest_star_session.end", ["channel:read:guest_star"], []},
    {"channel.guest_star_guest.update", ["channel:read:guest_star"], []},

    # Ad break events
    {"channel.ad_break.begin", ["channel:read:ads"], []},

    # User events
    {"user.authorization.grant", ["user:read:subscriptions"], []},
    {"user.authorization.revoke", ["user:read:subscriptions"], []},
    {"user.update", [], []},

    # Whisper events
    {"user.whisper.message", ["user:read:whispers"], []},

    # Drop events
    {"drop.entitlement.grant", ["user:read:subscriptions"], []},

    # Extension events
    {"extension.bits_transaction.create", ["user:read:subscriptions"], []}
  ]

  @doc """
  Creates a Twitch EventSub subscription via HTTP API.

  ## Parameters
  - `state` - Twitch service state containing session_id and oauth2_client
  - `event_type` - EventSub event type (e.g. "channel.update")
  - `condition` - Subscription condition map (e.g. %{"broadcaster_user_id" => "123"})
  - `opts` - Additional options (currently unused)

  ## Returns
  - `{:ok, subscription}` - Subscription created successfully
  - `{:error, reason}` - Creation failed
  """
  @spec create_subscription(map(), binary(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def create_subscription(state, event_type, condition, opts \\ []) do
    token_manager_module = Keyword.get(opts, :token_manager_module, Server.OAuthTokenManager)

    # Get access token from token manager
    case token_manager_module.get_valid_token(state.token_manager) do
      {:ok, access_token, _updated_manager} ->
        url = "https://api.twitch.tv/helix/eventsub/subscriptions"

        headers = [
          {"authorization", "Bearer #{access_token}"},
          {"client-id", state.oauth2_client.client_id},
          {"content-type", "application/json"}
        ]

        create_subscription_with_headers(state, event_type, condition, headers, url)

      {:error, reason} ->
        {:error, {:token_unavailable, reason}}
    end
  end

  @spec create_subscription_with_headers(map(), binary(), map(), list(), binary()) :: {:ok, map()} | {:error, term()}
  defp create_subscription_with_headers(state, event_type, condition, headers, url) do
    transport = %{
      "method" => "websocket",
      "session_id" => state.session_id
    }

    # Determine API version based on event type
    version = get_api_version_for_event_type(event_type)

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

            {:error, :unexpected_response_format}

          {:error, reason} ->
            Logger.error("Failed to parse EventSub subscription response",
              event_type: event_type,
              reason: inspect(reason),
              body: List.to_string(response_body)
            )

            {:error, {:json_decode_error, reason}}
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
  @spec make_subscription_request(binary(), list(), binary()) :: {:ok, binary()} | {:error, term()}
  defp make_subscription_request(url, headers, json_body) do
    uri = URI.parse(url)
    http_config = Server.NetworkConfig.http_config()

    gun_headers = Enum.map(headers, fn {k, v} -> {String.to_charlist(k), String.to_charlist(v)} end)

    with {:ok, conn_pid} <- :gun.open(String.to_charlist(uri.host), uri.port, gun_opts(uri)),
         {:ok, protocol} when protocol in [:http, :http2] <- :gun.await_up(conn_pid, http_config.timeout),
         stream_ref <- :gun.post(conn_pid, String.to_charlist(uri.path), gun_headers, json_body),
         {:ok, response} <- await_response(conn_pid, stream_ref, http_config.timeout) do
      :gun.close(conn_pid)
      parse_subscription_response(response)
    else
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
  @spec delete_subscription(map(), binary(), keyword()) :: :ok | {:error, term()}
  def delete_subscription(state, subscription_id, opts \\ []) do
    token_manager_module = Keyword.get(opts, :token_manager_module, Server.OAuthTokenManager)

    # Get access token from token manager
    case token_manager_module.get_valid_token(state.token_manager) do
      {:ok, access_token, _updated_manager} ->
        url = "https://api.twitch.tv/helix/eventsub/subscriptions?id=#{subscription_id}"

        headers = [
          {"authorization", "Bearer #{access_token}"},
          {"client-id", state.oauth2_client.client_id}
        ]

        delete_subscription_with_headers(url, headers, subscription_id)

      {:error, reason} ->
        {:error, {:token_unavailable, reason}}
    end
  end

  @spec delete_subscription_with_headers(binary(), list(), binary()) :: :ok | {:error, term()}
  defp delete_subscription_with_headers(url, headers, subscription_id) do
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
  @spec make_delete_request(binary(), list()) :: {:ok, atom()} | {:error, term()}
  defp make_delete_request(url, headers) do
    uri = URI.parse(url)
    http_config = Server.NetworkConfig.http_config()

    gun_headers = Enum.map(headers, fn {k, v} -> {String.to_charlist(k), String.to_charlist(v)} end)

    with {:ok, conn_pid} <- :gun.open(String.to_charlist(uri.host), uri.port, gun_opts(uri)),
         {:ok, protocol} when protocol in [:http, :http2] <- :gun.await_up(conn_pid, http_config.timeout),
         stream_ref <- :gun.delete(conn_pid, String.to_charlist("#{uri.path}?#{uri.query}"), gun_headers),
         {:ok, response} <- await_response(conn_pid, stream_ref, http_config.timeout) do
      :gun.close(conn_pid)
      parse_delete_response(response)
    else
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
  @spec create_default_subscriptions(map(), keyword()) :: {integer(), integer()}
  def create_default_subscriptions(state, opts \\ []) do
    if state.user_id do
      subscriptions_with_conditions = prepare_default_subscriptions(state.user_id)
      process_subscription_list(state, subscriptions_with_conditions, opts)
    else
      Logger.error("Cannot create subscriptions: user_id not available")
      {0, 1}
    end
  end

  # Prepares the default subscriptions with conditions
  defp prepare_default_subscriptions(user_id) do
    Enum.map(@default_subscriptions, fn {event_type, required_scopes, opts} ->
      condition = build_condition_for_event_type(event_type, user_id)
      {event_type, condition, required_scopes, opts}
    end)
  end

  # Processes the subscription list and creates subscriptions
  defp process_subscription_list(state, subscriptions, opts) do
    Enum.reduce(subscriptions, {0, 0}, fn subscription, acc ->
      create_single_subscription(state, subscription, acc, opts)
    end)
  end

  # Creates a single subscription and handles the result
  defp create_single_subscription(state, {event_type, condition, required_scopes, _sub_opts}, {success, failed}, opts) do
    if validate_scopes_for_subscription(state.scopes, required_scopes) do
      case create_subscription(state, event_type, condition, opts) do
        {:ok, subscription} ->
          log_successful_subscription(event_type, subscription)
          {success + 1, failed}

        {:error, reason} ->
          log_failed_subscription(state, event_type, condition, reason)
          {success, failed + 1}
      end
    else
      log_skipped_subscription(event_type, required_scopes, state.scopes)
      {success, failed + 1}
    end
  end

  # Logs successful subscription creation
  defp log_successful_subscription(event_type, subscription) do
    Logger.info("Created default EventSub subscription",
      event_type: event_type,
      subscription_id: subscription["id"],
      status: subscription["status"],
      cost: subscription["cost"] || 1
    )
  end

  # Logs failed subscription creation with specific guidance
  defp log_failed_subscription(state, event_type, condition, reason) do
    Logger.warning("Failed to create default EventSub subscription",
      event_type: event_type,
      reason: reason
    )

    log_subscription_failure_guidance(state, event_type, condition, reason)
  end

  # Provides specific guidance for known subscription failures
  defp log_subscription_failure_guidance(state, "channel.follow", condition, reason) do
    cond do
      String.contains?(to_string(reason), "Forbidden") ->
        Logger.info("Channel follow subscription failed",
          reason: "Forbidden - broadcaster may need explicit moderator verification",
          note: "This is common when using broadcaster token for moderator-required subscriptions"
        )

      String.contains?(to_string(reason), "unauthorized") ->
        Logger.info("Channel follow subscription failed",
          reason: "Unauthorized - token may need additional verification",
          scope_present: MapSet.member?(state.scopes || MapSet.new(), "moderator:read:followers")
        )

      true ->
        Logger.info("Channel follow subscription failed",
          reason: reason,
          condition: inspect(condition),
          user_id: state.user_id
        )
    end
  end

  defp log_subscription_failure_guidance(_state, event_type, _condition, reason) do
    Logger.debug("Subscription failed for #{event_type}", reason: reason)
  end

  # Logs skipped subscription due to missing scopes
  defp log_skipped_subscription(event_type, required_scopes, user_scopes) do
    Logger.info("Skipping EventSub subscription due to missing scopes",
      event_type: event_type,
      required_scopes: required_scopes,
      user_scopes: MapSet.to_list(user_scopes || MapSet.new())
    )
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

  # Builds the appropriate condition map for different EventSub event types.
  # Parameters: event_type (binary), user_id (binary)
  # Returns: Map containing the appropriate condition for the event type
  @spec build_condition_for_event_type(binary(), binary()) :: map()
  defp build_condition_for_event_type(event_type, user_id) do
    case event_type do
      # Events that require both broadcaster_user_id and moderator_user_id
      "channel.follow" ->
        %{"broadcaster_user_id" => user_id, "moderator_user_id" => user_id}

      # Chat events that require user_id instead of broadcaster_user_id
      "user.authorization.grant" ->
        %{"client_id" => get_client_id()}

      "user.authorization.revoke" ->
        %{"client_id" => get_client_id()}

      "user.update" ->
        %{"user_id" => user_id}

      "user.whisper.message" ->
        %{"user_id" => user_id}

      # Drop events that require organization_id and category_id (would need to be configured)
      "drop.entitlement.grant" ->
        %{
          "organization_id" => get_organization_id(),
          "category_id" => get_category_id()
        }

      # Extension events that require extension_client_id
      "extension.bits_transaction.create" ->
        %{"extension_client_id" => get_extension_client_id()}

      # All other events use broadcaster_user_id
      _ ->
        %{"broadcaster_user_id" => user_id}
    end
  end

  # Helper functions for configuration values (these would need to be configured in environment)
  defp get_client_id do
    System.get_env("TWITCH_CLIENT_ID") || ""
  end

  defp get_organization_id do
    System.get_env("TWITCH_ORGANIZATION_ID") || ""
  end

  defp get_category_id do
    System.get_env("TWITCH_CATEGORY_ID") || ""
  end

  defp get_extension_client_id do
    System.get_env("TWITCH_EXTENSION_CLIENT_ID") || ""
  end

  # Helper function to determine the correct API version for each event type
  defp get_api_version_for_event_type("channel.follow"), do: "2"
  defp get_api_version_for_event_type(_event_type), do: "1"

  # Gun HTTP client helper functions
  defp gun_opts(%URI{scheme: "https"}), do: %{transport: :tls}
  defp gun_opts(_), do: %{}

  defp await_response(_conn_pid, stream_ref, timeout) do
    case :gun.await(stream_ref, timeout) do
      {:response, :fin, status, headers} ->
        {:ok, {status, headers, ""}}

      {:response, :nofin, status, headers} ->
        case :gun.await_body(stream_ref, timeout) do
          {:ok, body} -> {:ok, {status, headers, body}}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_subscription_response({202, _headers, response_body}) do
    {:ok, response_body}
  end

  defp parse_subscription_response({429, _headers, response_body}) do
    {:error, {:http_error, 429, response_body}}
  end

  defp parse_subscription_response({status, _headers, response_body}) when status >= 500 do
    {:error, {:http_error, status, response_body}}
  end

  defp parse_subscription_response({status, _headers, response_body}) do
    case Jason.decode(response_body) do
      {:ok, %{"message" => message}} -> {:error, message}
      {:ok, %{"error" => error}} -> {:error, error}
      _ -> {:error, {:http_error, status, response_body}}
    end
  end

  defp parse_delete_response({204, _headers, _body}) do
    {:ok, :success}
  end

  defp parse_delete_response({429, _headers, response_body}) do
    {:error, {:http_error, 429, response_body}}
  end

  defp parse_delete_response({status, _headers, response_body}) when status >= 500 do
    {:error, {:http_error, status, response_body}}
  end

  defp parse_delete_response({status, _headers, response_body}) do
    {:error, {:http_error, status, response_body}}
  end
end
