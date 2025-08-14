defmodule Server.Services.Twitch.SubscriptionCoordinator do
  @moduledoc """
  Manages Twitch EventSub subscriptions with OAuth scope validation.

  Single source of truth for subscription definitions and their required scopes.
  Handles subscription lifecycle, retry logic, and cost tracking.
  """

  require Logger

  # Complete list of default subscriptions with their required OAuth scopes
  # Format: {event_type, required_scopes, options}
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

    # Shoutout events
    {"channel.shoutout.create", ["moderator:read:shoutouts"], []},
    {"channel.shoutout.receive", ["moderator:read:shoutouts"], []},

    # VIP events
    {"channel.vip.add", ["channel:read:vips"], []},
    {"channel.vip.remove", ["channel:read:vips"], []},

    # Ad break events
    {"channel.ad_break.begin", ["channel:read:ads"], []},

    # User events
    {"user.update", [], []}
  ]

  @doc """
  Creates default subscriptions for the configured user.

  This function:
  1. Validates that user has required OAuth scopes for each subscription
  2. Skips subscriptions without proper authorization
  3. Creates subscriptions with proper condition mapping
  4. Tracks success/failure metrics
  """
  def create_default_subscriptions(state, session_id) when not is_nil(session_id) do
    if state.default_subscriptions_created do
      Logger.debug("Default subscriptions already created for this session")
      state
    else
      Logger.info("Creating default Twitch EventSub subscriptions",
        session_id: session_id,
        user_id: state.user_id
      )

      case state.user_id do
        nil ->
          Logger.warning("Cannot create subscriptions: user_id not available yet")
          schedule_retry(state, session_id)

        user_id ->
          create_subscriptions_for_user(state, user_id, session_id)
      end
    end
  end

  def create_default_subscriptions(state, nil) do
    Logger.warning("Cannot create subscriptions without session_id")
    state
  end

  @doc """
  Creates a single subscription with scope validation.
  Returns {:ok, subscription, updated_state} or {:error, reason, state}
  """
  def create_subscription(event_type, condition, opts, state) do
    cond do
      not (state.connected && state.session_id) ->
        {:error, "WebSocket not connected", state}

      state.subscription_count >= state.subscription_max_count ->
        {:error, "Subscription count limit exceeded (#{state.subscription_max_count})", state}

      duplicate_subscription?(event_type, condition, state) ->
        Logger.debug("Subscription already exists for #{event_type}")
        {:error, :duplicate_subscription, state}

      true ->
        # Get required scopes for this event type
        required_scopes = get_required_scopes(event_type)

        # Validate scopes before attempting creation
        if validate_scopes_for_subscription(state.scopes, required_scopes) do
          case create_subscription_via_api(event_type, condition, opts, state) do
            {:ok, subscription} ->
              new_state = add_subscription_to_state(subscription, event_type, condition, state)
              {:ok, subscription, new_state}

            {:error, reason} ->
              {:error, reason, state}
          end
        else
          user_scope_list = MapSet.to_list(state.scopes || MapSet.new())
          missing_scopes = required_scopes -- user_scope_list

          Logger.warning("Missing required scopes for #{event_type}",
            required_scopes: required_scopes,
            missing_scopes: missing_scopes
          )

          {:error, {:missing_scopes, missing_scopes}, state}
        end
    end
  end

  @doc """
  Deletes a subscription by ID via HTTP API.
  Returns {:ok, updated_state} or {:error, reason, state}
  """
  def delete_subscription(subscription_id, state) do
    case Map.get(state.subscriptions, subscription_id) do
      nil ->
        {:error, :not_found, state}

      subscription ->
        case delete_subscription_via_api(subscription_id, state) do
          :ok ->
            new_state = remove_subscription_from_state(subscription_id, subscription, state)
            {:ok, new_state}

          {:error, reason} ->
            Logger.error("Failed to delete subscription: #{inspect(reason)}")
            {:error, reason, state}
        end
    end
  end

  @doc """
  Lists all active subscriptions.
  """
  def list_subscriptions(state) do
    Map.values(state.subscriptions)
  end

  @doc """
  Cleans up all subscriptions in parallel with controlled concurrency.
  """
  def cleanup_subscriptions(subscriptions, state) do
    # Process deletions in parallel with max concurrency of 10
    max_concurrency = 10

    subscriptions
    |> Enum.map(fn {id, _} -> id end)
    |> Task.async_stream(
      fn id ->
        case delete_subscription_via_api(id, state) do
          :ok ->
            Logger.debug("Subscription deleted", subscription_id: id)
            {:ok, id}

          {:error, reason} ->
            Logger.warning("Failed to delete subscription",
              subscription_id: id,
              reason: inspect(reason)
            )

            {:error, id, reason}
        end
      end,
      max_concurrency: max_concurrency,
      timeout: 10_000,
      on_timeout: :kill_task
    )
    |> Enum.reduce({[], []}, fn
      {:ok, {:ok, id}}, {success, failed} ->
        {[id | success], failed}

      {:ok, {:error, id, _reason}}, {success, failed} ->
        {success, [id | failed]}

      {:exit, :timeout}, {success, failed} ->
        Logger.error("Subscription deletion timed out")
        {success, ["timeout" | failed]}
    end)
    |> then(fn {success, failed} ->
      Logger.info("Subscription cleanup completed",
        successful: length(success),
        failed: length(failed),
        total: map_size(subscriptions)
      )

      {success, failed}
    end)
  end

  @doc """
  Gets the required OAuth scopes for a given event type.
  """
  def get_required_scopes(event_type) do
    case Enum.find(@default_subscriptions, fn {type, _scopes, _opts} -> type == event_type end) do
      {_, scopes, _} -> scopes
      nil -> []
    end
  end

  @doc """
  Validates that user has required scopes for a subscription.

  ## Parameters
  - `user_scopes` - MapSet or List of user's OAuth scopes
  - `required_scopes` - List of required scopes for the subscription

  ## Returns
  - `true` - User has all required scopes
  - `false` - User is missing required scopes
  """
  def validate_scopes_for_subscription(user_scopes, required_scopes)
  def validate_scopes_for_subscription(_user_scopes, []), do: true
  def validate_scopes_for_subscription(nil, _required_scopes), do: false

  def validate_scopes_for_subscription(user_scopes, required_scopes) when is_list(user_scopes) do
    # Convert list to MapSet for efficient lookup
    validate_scopes_for_subscription(MapSet.new(user_scopes), required_scopes)
  end

  def validate_scopes_for_subscription(user_scopes, required_scopes) when is_struct(user_scopes, MapSet) do
    Enum.all?(required_scopes, fn scope -> MapSet.member?(user_scopes, scope) end)
  end

  # Private functions

  defp create_subscriptions_for_user(state, user_id, session_id) do
    # Prepare subscriptions with conditions
    subscriptions_with_conditions = prepare_default_subscriptions(user_id)

    # Process subscription list and collect results
    results = process_subscription_list_batch(state, subscriptions_with_conditions, session_id)

    # Log single summary
    log_subscription_batch_summary(results)

    # Update state with successful subscriptions
    new_state =
      Enum.reduce(results.successful_subscriptions, state, fn subscription, acc ->
        add_subscription_to_state(subscription, nil, nil, acc)
      end)

    %{new_state | default_subscriptions_created: true}
  end

  defp prepare_default_subscriptions(user_id) do
    Enum.map(@default_subscriptions, fn {event_type, required_scopes, opts} ->
      condition = build_condition_for_event_type(event_type, user_id)
      {event_type, condition, required_scopes, opts}
    end)
  end

  defp process_subscription_list_batch(state, subscriptions, session_id) do
    # Group subscriptions by criticality for prioritized processing
    {critical, standard} =
      Enum.split_with(subscriptions, fn {event_type, _, _, _} ->
        event_type in ["stream.online", "stream.offline", "channel.update", "channel.follow", "channel.chat.message"]
      end)

    # Process critical subscriptions first with higher concurrency
    critical_results = process_subscription_group(state, critical, session_id, 5)

    # Then process standard subscriptions with normal concurrency
    standard_results = process_subscription_group(state, standard, session_id, 10)

    # Combine results
    %{
      successful: critical_results.successful ++ standard_results.successful,
      failed: critical_results.failed ++ standard_results.failed,
      skipped: critical_results.skipped ++ standard_results.skipped,
      successful_count: critical_results.successful_count + standard_results.successful_count,
      failed_count: critical_results.failed_count + standard_results.failed_count,
      total_cost: critical_results.total_cost + standard_results.total_cost,
      successful_subscriptions: critical_results.successful_subscriptions ++ standard_results.successful_subscriptions
    }
  end

  defp process_subscription_group(state, subscriptions, session_id, max_concurrency) do
    results =
      subscriptions
      |> Task.async_stream(
        fn subscription ->
          process_single_subscription_async(state, subscription, session_id)
        end,
        max_concurrency: max_concurrency,
        timeout: 15_000,
        on_timeout: :kill_task
      )
      |> Enum.reduce(
        %{
          successful: [],
          failed: [],
          skipped: [],
          successful_count: 0,
          failed_count: 0,
          total_cost: 0,
          successful_subscriptions: []
        },
        fn
          {:ok, {:success, event_type, subscription}}, acc ->
            cost = subscription["cost"] || 1

            %{
              acc
              | successful: [{event_type, subscription["id"]} | acc.successful],
                successful_count: acc.successful_count + 1,
                total_cost: acc.total_cost + cost,
                successful_subscriptions: [subscription | acc.successful_subscriptions]
            }

          {:ok, {:failed, event_type, reason}}, acc ->
            %{acc | failed: [{event_type, inspect(reason)} | acc.failed], failed_count: acc.failed_count + 1}

          {:ok, {:skipped, event_type, missing_scopes}}, acc ->
            %{acc | skipped: [{event_type, missing_scopes} | acc.skipped], failed_count: acc.failed_count + 1}

          {:exit, :timeout}, acc ->
            Logger.error("Subscription creation timed out")
            %{acc | failed: [{"unknown", "timeout"} | acc.failed], failed_count: acc.failed_count + 1}
        end
      )

    results
  end

  defp process_single_subscription_async(state, {event_type, condition, required_scopes, _opts}, session_id) do
    if validate_scopes_for_subscription(state.scopes, required_scopes) do
      case create_subscription_with_retry(state, event_type, condition, session_id) do
        {:ok, subscription} ->
          {:success, event_type, subscription}

        {:retry, _delay, _event_type, _condition, _session_id, _attempt} ->
          # For async processing, we can't schedule retries the same way
          # Mark as failed for now
          {:failed, event_type, "retry_needed"}

        {:error, reason} ->
          if event_type == "channel.chat.message" do
            Logger.error("Chat subscription failed - critical feature",
              event_type: event_type,
              reason: inspect(reason)
            )
          end

          {:failed, event_type, reason}
      end
    else
      user_scope_list = MapSet.to_list(state.scopes || MapSet.new())
      missing_scopes = required_scopes -- user_scope_list

      if event_type == "channel.chat.message" do
        Logger.error("Chat subscription skipped - missing scopes",
          event_type: event_type,
          missing_scopes: missing_scopes
        )
      end

      {:skipped, event_type, missing_scopes}
    end
  end

  defp create_subscription_with_retry(state, event_type, condition, session_id) do
    # Critical events that should be retried more aggressively
    critical_events = ["stream.online", "stream.offline", "channel.update", "channel.follow"]

    max_retries = if event_type in critical_events, do: 3, else: 1

    create_subscription_with_retry(state, event_type, condition, session_id, 0, max_retries)
  end

  defp create_subscription_with_retry(state, event_type, condition, session_id, attempt, max_retries)
       when attempt < max_retries do
    case create_subscription_via_api(event_type, condition, [], %{state | session_id: session_id}) do
      {:ok, subscription} ->
        if attempt > 0 do
          Logger.debug("Subscription created after retry",
            event_type: event_type,
            attempt: attempt + 1,
            subscription_id: subscription["id"]
          )
        end

        {:ok, subscription}

      {:error, reason} ->
        if attempt + 1 < max_retries do
          # Return retry instruction for non-blocking delayed retry
          delay = min(1000 * :math.pow(2, attempt), 5000) |> round()

          Logger.debug("Scheduling subscription retry",
            event_type: event_type,
            attempt: attempt + 1,
            max_retries: max_retries,
            delay: delay
          )

          {:retry, delay, event_type, condition, session_id, attempt + 1}
        else
          {:error, reason}
        end
    end
  end

  defp create_subscription_with_retry(_state, _event_type, _condition, _session_id, attempt, max_retries)
       when attempt >= max_retries do
    {:error, :max_retries_exceeded}
  end

  defp log_subscription_batch_summary(results) do
    total_attempted = results.successful_count + results.failed_count

    Logger.info("EventSub subscription batch completed",
      successful: results.successful_count,
      failed: results.failed_count,
      total_cost: results.total_cost,
      total_attempted: total_attempted
    )

    # Log failures at debug level with details
    if length(results.failed) > 0 do
      Logger.debug("Failed subscriptions",
        failed_events:
          Enum.map(results.failed, fn {event, reason} ->
            %{event: event, reason: reason}
          end)
      )
    end

    # Log skipped at debug level
    if length(results.skipped) > 0 do
      Logger.debug("Skipped subscriptions due to missing scopes",
        skipped_events:
          Enum.map(results.skipped, fn {event, scopes} ->
            %{event: event, missing_scopes: scopes}
          end)
      )
    end
  end

  # HTTP API functions

  defp create_subscription_via_api(event_type, condition, _opts, state) do
    # Use circuit breaker for external API calls
    case Server.CircuitBreakerServer.call(
           :twitch_api,
           fn ->
             # Get access token from OAuth service
             case Server.OAuthService.get_valid_token(:twitch) do
               {:ok, %{access_token: access_token}} ->
                 url = "https://api.twitch.tv/helix/eventsub/subscriptions"
                 client_id = get_client_id(state)

                 headers = [
                   {"authorization", "Bearer #{access_token}"},
                   {"client-id", client_id},
                   {"content-type", "application/json"}
                 ]

                 create_subscription_with_headers(state, event_type, condition, headers, url)

               {:error, reason} ->
                 {:error, {:token_unavailable, reason}}
             end
           end
         ) do
      {:error, :circuit_open} ->
        Logger.error("Circuit breaker is open for Twitch API",
          event_type: event_type
        )

        {:error, :circuit_breaker_open}

      result ->
        result
    end
  end

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

    json_body = JSON.encode!(body)

    Logger.debug("Subscription creation started",
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
        case JSON.decode(response_body) do
          {:ok, %{"data" => [subscription]}} ->
            Logger.debug("Subscription created",
              event_type: event_type,
              subscription_id: subscription["id"],
              status: subscription["status"],
              cost: subscription["cost"] || 1
            )

            {:ok, subscription}

          {:ok, response} ->
            Logger.error("Subscription creation failed",
              error: "unexpected response format",
              event_type: event_type,
              response: inspect(response, limit: :infinity)
            )

            {:error, :unexpected_response_format}

          {:error, reason} ->
            Logger.error("Subscription response parse failed",
              error: inspect(reason),
              event_type: event_type,
              body: response_body
            )

            {:error, {:json_decode_error, reason}}
        end

      {:error, reason} ->
        Logger.error("Subscription creation failed after retries",
          error: inspect(reason),
          event_type: event_type
        )

        {:error, reason}
    end
  end

  defp make_subscription_request(url, headers, json_body) do
    uri = URI.parse(url)
    timeout_ms = Server.NetworkConfig.http_timeout_ms()

    gun_headers = Enum.map(headers, fn {k, v} -> {String.to_charlist(k), String.to_charlist(v)} end)

    # Ensure port is set correctly
    port = uri.port || if uri.scheme == "https", do: 443, else: 80
    host = String.to_charlist(uri.host)
    path = String.to_charlist(uri.path || "/")

    with {:ok, conn_pid} <- :gun.open(host, port, gun_opts(uri)),
         {:ok, protocol} when protocol in [:http, :http2] <- :gun.await_up(conn_pid, timeout_ms),
         stream_ref <- :gun.post(conn_pid, path, gun_headers, json_body),
         {:ok, response} <- await_response(conn_pid, stream_ref, timeout_ms) do
      :gun.close(conn_pid)
      parse_subscription_response(response)
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp delete_subscription_via_api(subscription_id, state) do
    # Get access token from OAuth service
    case Server.OAuthService.get_valid_token(:twitch) do
      {:ok, %{access_token: access_token}} ->
        # Properly encode the subscription ID to handle UTF-8 characters
        encoded_id = URI.encode_www_form(subscription_id)
        url = "https://api.twitch.tv/helix/eventsub/subscriptions?id=#{encoded_id}"

        headers = [
          {"authorization", "Bearer #{access_token}"},
          {"client-id", get_client_id(state)}
        ]

        delete_subscription_with_headers(url, headers, subscription_id)

      {:error, reason} ->
        {:error, {:token_unavailable, reason}}
    end
  end

  defp delete_subscription_with_headers(url, headers, subscription_id) do
    Logger.debug("Subscription deletion started", subscription_id: subscription_id)

    case Server.RetryStrategy.retry(fn ->
           make_delete_request(url, headers)
         end) do
      {:ok, :success} ->
        Logger.info("Subscription deleted", subscription_id: subscription_id)
        :ok

      {:error, reason} ->
        Logger.error("Subscription deletion failed after retries",
          error: inspect(reason),
          subscription_id: subscription_id
        )

        {:error, reason}
    end
  end

  defp make_delete_request(url, headers) do
    uri = URI.parse(url)
    timeout_ms = Server.NetworkConfig.http_timeout_ms()

    gun_headers = Enum.map(headers, fn {k, v} -> {String.to_charlist(k), String.to_charlist(v)} end)

    # Ensure port is set correctly
    port = uri.port || if uri.scheme == "https", do: 443, else: 80
    host = String.to_charlist(uri.host)
    path_with_query = String.to_charlist("#{uri.path || "/"}#{if uri.query, do: "?#{uri.query}", else: ""}")

    with {:ok, conn_pid} <- :gun.open(host, port, gun_opts(uri)),
         {:ok, protocol} when protocol in [:http, :http2] <- :gun.await_up(conn_pid, timeout_ms),
         stream_ref <- :gun.delete(conn_pid, path_with_query, gun_headers),
         {:ok, response} <- await_response(conn_pid, stream_ref, timeout_ms) do
      :gun.close(conn_pid)
      parse_delete_response(response)
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  # Helper functions for conditions and API versions

  defp build_condition_for_event_type(event_type, user_id) do
    cond do
      event_type in moderator_events() ->
        %{"broadcaster_user_id" => user_id, "moderator_user_id" => user_id}

      event_type in chat_events() ->
        %{"broadcaster_user_id" => user_id, "user_id" => user_id}

      event_type == "user.update" ->
        %{"user_id" => user_id}

      event_type == "channel.raid" ->
        %{"to_broadcaster_user_id" => user_id}

      true ->
        %{"broadcaster_user_id" => user_id}
    end
  end

  defp moderator_events do
    ["channel.follow", "channel.shoutout.create", "channel.shoutout.receive"]
  end

  defp chat_events do
    [
      "channel.chat.clear",
      "channel.chat.clear_user_messages",
      "channel.chat.message",
      "channel.chat.message_delete",
      "channel.chat.notification",
      "channel.chat_settings.update"
    ]
  end

  defp get_api_version_for_event_type("channel.follow"), do: "2"
  defp get_api_version_for_event_type("channel.update"), do: "2"
  defp get_api_version_for_event_type(_event_type), do: "1"

  # Gun HTTP client helper functions

  defp gun_opts(%URI{scheme: "https"}), do: %{transport: :tls}
  defp gun_opts(_), do: %{}

  defp await_response(conn_pid, stream_ref, timeout) do
    case :gun.await(conn_pid, stream_ref, timeout) do
      {:response, :fin, status, headers} ->
        {:ok, {status, headers, ""}}

      {:response, :nofin, status, headers} ->
        case :gun.await_body(conn_pid, stream_ref, timeout) do
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
    case JSON.decode(response_body) do
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

  # State management helpers

  defp duplicate_subscription?(event_type, condition, state) do
    Enum.any?(state.subscriptions, fn {_, sub} ->
      sub["type"] == event_type &&
        maps_equal_ignoring_order?(sub["condition"], condition)
    end)
  end

  defp maps_equal_ignoring_order?(map1, map2) do
    Map.equal?(
      stringify_map(map1),
      stringify_map(map2)
    )
  end

  defp stringify_map(map) do
    Enum.map(map, fn {k, v} -> {to_string(k), to_string(v)} end)
    |> Enum.into(%{})
  end

  defp add_subscription_to_state(subscription, _event_type, _condition, state) do
    sub_id = subscription["id"]
    cost = subscription["cost"] || 1

    # Limit subscription map size to prevent unbounded growth
    max_subscriptions = 1000
    current_count = map_size(state.subscriptions)

    new_subscriptions =
      if current_count >= max_subscriptions do
        # Remove oldest subscription if at limit (FIFO)
        {oldest_id, _} =
          Enum.min_by(state.subscriptions, fn {_id, sub} ->
            sub["created_at"] || ""
          end)

        Logger.warning("Subscription limit reached, removing oldest",
          removed_id: oldest_id,
          max_subscriptions: max_subscriptions
        )

        state.subscriptions
        |> Map.delete(oldest_id)
        |> Map.put(sub_id, subscription)
      else
        Map.put(state.subscriptions, sub_id, subscription)
      end

    %{
      state
      | subscriptions: new_subscriptions,
        subscription_count: map_size(new_subscriptions),
        subscription_total_cost: state.subscription_total_cost + cost
    }
  end

  defp remove_subscription_from_state(subscription_id, subscription, state) do
    cost = subscription["cost"] || 1
    new_subscriptions = Map.delete(state.subscriptions, subscription_id)

    %{
      state
      | subscriptions: new_subscriptions,
        subscription_count: map_size(new_subscriptions),
        subscription_total_cost: max(0, state.subscription_total_cost - cost)
    }
  end

  defp schedule_retry(state, session_id) do
    if state.retry_subscription_timer do
      Process.cancel_timer(state.retry_subscription_timer)
    end

    timer_ref = Process.send_after(self(), {:retry_default_subscriptions, session_id}, 5000)
    %{state | retry_subscription_timer: timer_ref}
  end

  defp get_client_id(state) do
    # The Twitch service passes its client_id in the state
    cond do
      # First check if client_id is directly in state (from Twitch service)
      Map.has_key?(state, :client_id) && is_binary(state.client_id) ->
        state.client_id

      # Then check oauth2_client for backwards compatibility
      get_in(state, [:oauth2_client, :client_id]) != nil ->
        get_in(state, [:oauth2_client, :client_id])

      # Last resort: use fail-fast config (raises clear error if missing)
      true ->
        Server.Config.twitch_client_id()
    end
  end

  @doc """
  Generates a unique key for subscription deduplication.

  ## Parameters
  - `event_type` - EventSub event type
  - `condition` - Subscription condition map

  ## Returns
  - Unique string key for the subscription
  """
  def generate_subscription_key(event_type, condition) when is_non_struct_map(condition) do
    # Sort condition keys for consistent key generation
    sorted_condition =
      condition
      |> Enum.sort()
      |> Enum.into(%{})

    "#{event_type}:#{JSON.encode!(sorted_condition)}"
  end

  # Service configuration helpers
  defp oauth_service, do: Application.get_env(:server, :services, [])[:oauth] || Server.OAuthService
end
