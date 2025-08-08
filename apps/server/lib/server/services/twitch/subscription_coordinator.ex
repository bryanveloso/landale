defmodule Server.Services.Twitch.SubscriptionCoordinator do
  @moduledoc """
  Coordinates subscription creation and management for Twitch EventSub.

  Handles:
  - Default subscription creation after connection
  - Subscription retry logic
  - Subscription state management
  - Cost tracking for rate limiting
  """

  require Logger
  alias Server.Services.Twitch.EventSubManager

  @default_subscriptions [
    {"stream.online", %{"broadcaster_user_id" => nil}},
    {"stream.offline", %{"broadcaster_user_id" => nil}},
    {"channel.update", %{"broadcaster_user_id" => nil}},
    {"channel.follow", %{"broadcaster_user_id" => nil, "moderator_user_id" => nil}},
    {"channel.subscribe", %{"broadcaster_user_id" => nil}},
    {"channel.subscription.gift", %{"broadcaster_user_id" => nil}},
    {"channel.subscription.message", %{"broadcaster_user_id" => nil}},
    {"channel.cheer", %{"broadcaster_user_id" => nil}},
    {"channel.raid", %{"to_broadcaster_user_id" => nil}},
    {"channel.ban", %{"broadcaster_user_id" => nil}},
    {"channel.unban", %{"broadcaster_user_id" => nil}},
    {"channel.moderator.add", %{"broadcaster_user_id" => nil}},
    {"channel.moderator.remove", %{"broadcaster_user_id" => nil}},
    {"channel.channel_points_custom_reward_redemption.add", %{"broadcaster_user_id" => nil}},
    {"channel.channel_points_custom_reward_redemption.update", %{"broadcaster_user_id" => nil}},
    {"channel.poll.begin", %{"broadcaster_user_id" => nil}},
    {"channel.poll.progress", %{"broadcaster_user_id" => nil}},
    {"channel.poll.end", %{"broadcaster_user_id" => nil}},
    {"channel.prediction.begin", %{"broadcaster_user_id" => nil}},
    {"channel.prediction.progress", %{"broadcaster_user_id" => nil}},
    {"channel.prediction.lock", %{"broadcaster_user_id" => nil}},
    {"channel.prediction.end", %{"broadcaster_user_id" => nil}},
    {"channel.hype_train.begin", %{"broadcaster_user_id" => nil}},
    {"channel.hype_train.progress", %{"broadcaster_user_id" => nil}},
    {"channel.hype_train.end", %{"broadcaster_user_id" => nil}},
    {"channel.charity_campaign.donate", %{"broadcaster_user_id" => nil}},
    {"channel.charity_campaign.start", %{"broadcaster_user_id" => nil}},
    {"channel.charity_campaign.progress", %{"broadcaster_user_id" => nil}},
    {"channel.charity_campaign.stop", %{"broadcaster_user_id" => nil}},
    {"channel.shield_mode.begin", %{"broadcaster_user_id" => nil, "moderator_user_id" => nil}},
    {"channel.shield_mode.end", %{"broadcaster_user_id" => nil, "moderator_user_id" => nil}},
    {"channel.shoutout.create", %{"broadcaster_user_id" => nil, "moderator_user_id" => nil}},
    {"channel.shoutout.receive", %{"broadcaster_user_id" => nil, "moderator_user_id" => nil}}
  ]

  @doc """
  Creates default subscriptions for the configured user.
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
  Creates a single subscription and updates state.
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
        case create_new_subscription(event_type, condition, opts, state) do
          {:ok, subscription} ->
            new_state = add_subscription_to_state(subscription, event_type, condition, state)
            {:ok, subscription, new_state}

          {:error, reason} ->
            {:error, reason, state}
        end
    end
  end

  @doc """
  Deletes a subscription by ID.
  Returns {:ok, updated_state} or {:error, reason, state}
  """
  def delete_subscription(subscription_id, state) do
    case Map.get(state.subscriptions, subscription_id) do
      nil ->
        {:error, :not_found, state}

      subscription ->
        # Create proper manager state for EventSubManager
        manager_state = %{
          service_name: :twitch,
          session_id: state.session_id,
          user_id: state.user_id,
          scopes: state.scopes
        }

        case EventSubManager.delete_subscription(manager_state, subscription_id, []) do
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
  Cleans up all subscriptions.
  Note: Requires state to be passed to EventSubManager
  """
  def cleanup_subscriptions(subscriptions, state) do
    # Create proper manager state for EventSubManager
    manager_state = %{
      service_name: :twitch,
      session_id: state.session_id,
      user_id: state.user_id,
      scopes: state.scopes
    }

    Enum.each(subscriptions, fn {id, _} ->
      EventSubManager.delete_subscription(manager_state, id, [])
    end)
  end

  # Private functions

  defp create_subscriptions_for_user(state, user_id, session_id) do
    results =
      Enum.map(@default_subscriptions, fn {event_type, condition_template} ->
        condition = fill_condition_template(condition_template, user_id)

        case EventSubManager.create_subscription(event_type, condition,
               session_id: session_id,
               user_id: user_id
             ) do
          {:ok, subscription} ->
            Logger.debug("Created subscription for #{event_type}")
            {:ok, subscription}

          {:error, reason} ->
            Logger.warning("Failed to create subscription for #{event_type}: #{inspect(reason)}")
            {:error, {event_type, reason}}
        end
      end)

    successful = Enum.count(results, &match?({:ok, _}, &1))
    failed = Enum.count(results, &match?({:error, _}, &1))

    Logger.info("Subscription creation complete",
      successful: successful,
      failed: failed,
      total: length(@default_subscriptions)
    )

    # Update state with successful subscriptions
    new_state =
      Enum.reduce(results, state, fn
        {:ok, subscription}, acc ->
          add_subscription_to_state(subscription, nil, nil, acc)

        _, acc ->
          acc
      end)

    %{new_state | default_subscriptions_created: true}
  end

  defp fill_condition_template(template, user_id) do
    Enum.map(template, fn
      {key, nil} when key in ["broadcaster_user_id", "moderator_user_id", "to_broadcaster_user_id"] ->
        {key, user_id}

      {key, value} ->
        {key, value}
    end)
    |> Enum.into(%{})
  end

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

  defp create_new_subscription(event_type, condition, opts, state) do
    full_opts =
      Keyword.merge(opts,
        session_id: state.session_id,
        user_id: state.user_id
      )

    EventSubManager.create_subscription(event_type, condition, full_opts)
  end

  defp add_subscription_to_state(subscription, _event_type, _condition, state) do
    sub_id = subscription["id"]
    cost = subscription["cost"] || 1

    new_subscriptions = Map.put(state.subscriptions, sub_id, subscription)

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
end
