defmodule Server.SubscriptionMonitor do
  @moduledoc """
  Monitors EventSub subscription health and manages subscription lifecycle.

  Provides centralized monitoring of EventSub subscriptions across different services,
  tracks subscription status, handles cleanup of orphaned subscriptions, and provides
  health reporting for monitoring dashboards.

  This module follows Elixir best practices:
  - Uses dependency injection for storage (testable)
  - Separates business logic from data storage  
  - Supports multiple instances for testing
  - Proper supervision and fault tolerance

  ## Features

  - Subscription health monitoring and status tracking
  - Automatic cleanup of failed or orphaned subscriptions
  - Subscription lifecycle management (creation, update, deletion)
  - Health metrics and reporting for monitoring systems
  - Integration with telemetry for observability
  - Support for multiple service subscription tracking

  ## Usage

      # Start monitoring a subscription
      :ok = SubscriptionMonitor.track_subscription(
        "subscription_123",
        "channel.follow",
        %{service: :twitch, user_id: "123456"}
      )

      # Update subscription status
      :ok = SubscriptionMonitor.update_subscription_status(
        "subscription_123",
        :enabled
      )

      # Get subscription health report
      report = SubscriptionMonitor.get_health_report()

      # Cleanup orphaned subscriptions
      {:ok, cleaned_count} = SubscriptionMonitor.cleanup_orphaned_subscriptions()
  """

  use GenServer
  require Logger

  alias Server.SubscriptionStorage

  @type subscription_id :: binary()
  @type event_type :: binary()
  @type subscription_status ::
          :enabled
          | :webhook_callback_verification_pending
          | :webhook_callback_verification_failed
          | :notification_failures_exceeded
          | :authorization_revoked
          | :moderator_removed
          | :user_removed
          | :version_removed

  @type subscription_info :: %{
          id: subscription_id(),
          event_type: event_type(),
          status: subscription_status(),
          created_at: DateTime.t(),
          last_updated: DateTime.t(),
          last_event_at: DateTime.t() | nil,
          failure_count: integer(),
          metadata: map()
        }

  @type health_report :: %{
          total_subscriptions: integer(),
          enabled_subscriptions: integer(),
          failed_subscriptions: integer(),
          orphaned_subscriptions: integer(),
          subscriptions_by_type: map(),
          subscriptions_by_status: map(),
          oldest_subscription: DateTime.t() | nil,
          last_cleanup_at: DateTime.t() | nil
        }

  # Cleanup interval: every 30 minutes
  @cleanup_interval_ms 30 * 60 * 1000

  # Consider subscription orphaned if no events for 2 hours
  @orphan_threshold_ms 2 * 60 * 60 * 1000

  # Health check interval: every 5 minutes
  @health_check_interval_ms 5 * 60 * 1000

  ## Public API

  @doc """
  Starts the subscription monitor GenServer.

  ## Options

  - `:storage` - Storage table name or GenServer (default: :subscriptions)
  - `:name` - GenServer registration name (default: __MODULE__)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    storage = Keyword.get(opts, :storage, :subscriptions)
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{storage: storage}, name: name)
  end

  @doc """
  Tracks a new subscription in the monitoring system.

  ## Parameters
  - `subscription_id` - Unique subscription identifier
  - `event_type` - Type of event being subscribed to
  - `metadata` - Additional metadata about the subscription
  - `server` - GenServer to call (default: __MODULE__)

  ## Returns
  - `:ok` - Subscription tracked successfully
  """
  @spec track_subscription(subscription_id(), event_type(), map(), GenServer.server()) :: :ok
  def track_subscription(subscription_id, event_type, metadata \\ %{}, server \\ __MODULE__) do
    GenServer.call(server, {:track_subscription, subscription_id, event_type, metadata})
  end

  @doc """
  Updates the status of a tracked subscription.

  ## Parameters
  - `subscription_id` - Subscription identifier
  - `status` - New subscription status
  - `server` - GenServer to call (default: __MODULE__)

  ## Returns
  - `:ok` - Status updated successfully
  - `{:error, :not_found}` - Subscription not found
  """
  @spec update_subscription_status(subscription_id(), subscription_status(), GenServer.server()) ::
          :ok | {:error, :not_found}
  def update_subscription_status(subscription_id, status, server \\ __MODULE__) do
    GenServer.call(server, {:update_status, subscription_id, status})
  end

  @doc """
  Records that an event was received for a subscription.

  ## Parameters
  - `subscription_id` - Subscription identifier
  - `server` - GenServer to call (default: __MODULE__)

  ## Returns
  - `:ok` - Event recorded successfully
  - `{:error, :not_found}` - Subscription not found
  """
  @spec record_event_received(subscription_id(), GenServer.server()) :: :ok | {:error, :not_found}
  def record_event_received(subscription_id, server \\ __MODULE__) do
    GenServer.call(server, {:record_event, subscription_id})
  end

  @doc """
  Records a failure for a subscription.

  ## Parameters
  - `subscription_id` - Subscription identifier
  - `reason` - Failure reason
  - `server` - GenServer to call (default: __MODULE__)

  ## Returns
  - `:ok` - Failure recorded successfully
  - `{:error, :not_found}` - Subscription not found
  """
  @spec record_subscription_failure(subscription_id(), term(), GenServer.server()) :: :ok | {:error, :not_found}
  def record_subscription_failure(subscription_id, reason, server \\ __MODULE__) do
    GenServer.call(server, {:record_failure, subscription_id, reason})
  end

  @doc """
  Removes a subscription from monitoring.

  ## Parameters
  - `subscription_id` - Subscription identifier
  - `server` - GenServer to call (default: __MODULE__)

  ## Returns
  - `:ok` - Subscription removed successfully
  """
  @spec untrack_subscription(subscription_id(), GenServer.server()) :: :ok
  def untrack_subscription(subscription_id, server \\ __MODULE__) do
    GenServer.call(server, {:untrack_subscription, subscription_id})
  end

  @doc """
  Gets current health report for all monitored subscriptions.

  ## Parameters
  - `server` - GenServer to call (default: __MODULE__)

  ## Returns
  - Health report map with subscription statistics
  """
  @spec get_health_report(GenServer.server()) :: health_report()
  def get_health_report(server \\ __MODULE__) do
    GenServer.call(server, :get_health_report)
  end

  @doc """
  Gets detailed information about a specific subscription.

  ## Parameters
  - `subscription_id` - Subscription identifier
  - `server` - GenServer to call (default: __MODULE__)

  ## Returns
  - `{:ok, subscription_info}` - Subscription found
  - `{:error, :not_found}` - Subscription not found
  """
  @spec get_subscription_info(subscription_id(), GenServer.server()) ::
          {:ok, subscription_info()} | {:error, :not_found}
  def get_subscription_info(subscription_id, server \\ __MODULE__) do
    GenServer.call(server, {:get_subscription, subscription_id})
  end

  @doc """
  Lists all monitored subscriptions with optional filtering.

  ## Parameters
  - `filters` - Optional filters (status, event_type, etc.)
  - `server` - GenServer to call (default: __MODULE__)

  ## Returns
  - List of subscription information maps
  """
  @spec list_subscriptions(keyword(), GenServer.server()) :: [subscription_info()]
  def list_subscriptions(filters \\ [], server \\ __MODULE__) do
    GenServer.call(server, {:list_subscriptions, filters})
  end

  @doc """
  Triggers cleanup of orphaned and failed subscriptions.

  ## Parameters
  - `server` - GenServer to call (default: __MODULE__)

  ## Returns
  - `{:ok, cleaned_count}` - Number of subscriptions cleaned up
  """
  @spec cleanup_orphaned_subscriptions(GenServer.server()) :: {:ok, integer()}
  def cleanup_orphaned_subscriptions(server \\ __MODULE__) do
    GenServer.call(server, :cleanup_orphaned_subscriptions)
  end

  ## GenServer Implementation

  defstruct [
    :storage,
    :last_cleanup_at,
    :cleanup_timer,
    :health_timer
  ]

  @impl true
  def init(%{storage: storage}) do
    # Schedule periodic cleanup and health checks
    cleanup_timer = Process.send_after(self(), :cleanup_subscriptions, @cleanup_interval_ms)
    health_timer = Process.send_after(self(), :emit_health_metrics, @health_check_interval_ms)

    state = %__MODULE__{
      storage: storage,
      last_cleanup_at: DateTime.utc_now(),
      cleanup_timer: cleanup_timer,
      health_timer: health_timer
    }

    Logger.info("Subscription monitor started with storage: #{inspect(storage)}")
    {:ok, state}
  end

  @impl true
  def handle_call({:track_subscription, subscription_id, event_type, metadata}, _from, state) do
    subscription = %{
      id: subscription_id,
      event_type: event_type,
      status: :enabled,
      created_at: DateTime.utc_now(),
      last_updated: DateTime.utc_now(),
      last_event_at: nil,
      failure_count: 0,
      metadata: metadata
    }

    SubscriptionStorage.put(state.storage, subscription_id, subscription)

    Logger.debug("Tracking subscription",
      subscription_id: subscription_id,
      event_type: event_type
    )

    emit_telemetry([:subscription, :tracked], %{}, %{
      subscription_id: subscription_id,
      event_type: event_type
    })

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:update_status, subscription_id, status}, _from, state) do
    case SubscriptionStorage.lookup(state.storage, subscription_id) do
      {:ok, subscription} ->
        updated_subscription = %{subscription | status: status, last_updated: DateTime.utc_now()}

        SubscriptionStorage.put(state.storage, subscription_id, updated_subscription)

        Logger.debug("Updated subscription status",
          subscription_id: subscription_id,
          status: status
        )

        emit_telemetry([:subscription, :status_updated], %{}, %{
          subscription_id: subscription_id,
          status: status
        })

        {:reply, :ok, state}

      :error ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:record_event, subscription_id}, _from, state) do
    case SubscriptionStorage.lookup(state.storage, subscription_id) do
      {:ok, subscription} ->
        updated_subscription = %{subscription | last_event_at: DateTime.utc_now(), last_updated: DateTime.utc_now()}

        SubscriptionStorage.put(state.storage, subscription_id, updated_subscription)

        emit_telemetry([:subscription, :event_received], %{}, %{
          subscription_id: subscription_id
        })

        {:reply, :ok, state}

      :error ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:record_failure, subscription_id, reason}, _from, state) do
    case SubscriptionStorage.lookup(state.storage, subscription_id) do
      {:ok, subscription} ->
        updated_subscription = %{
          subscription
          | failure_count: subscription.failure_count + 1,
            last_updated: DateTime.utc_now()
        }

        SubscriptionStorage.put(state.storage, subscription_id, updated_subscription)

        Logger.warning("Subscription failure recorded",
          subscription_id: subscription_id,
          failure_count: updated_subscription.failure_count,
          reason: inspect(reason)
        )

        emit_telemetry([:subscription, :failure], %{count: 1}, %{
          subscription_id: subscription_id,
          failure_count: updated_subscription.failure_count,
          reason: inspect(reason)
        })

        {:reply, :ok, state}

      :error ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:untrack_subscription, subscription_id}, _from, state) do
    SubscriptionStorage.delete(state.storage, subscription_id)

    Logger.debug("Untracked subscription", subscription_id: subscription_id)

    emit_telemetry([:subscription, :untracked], %{}, %{
      subscription_id: subscription_id
    })

    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:get_health_report, _from, state) do
    report = generate_health_report(state)
    {:reply, report, state}
  end

  @impl true
  def handle_call({:get_subscription, subscription_id}, _from, state) do
    case SubscriptionStorage.lookup(state.storage, subscription_id) do
      {:ok, subscription} ->
        {:reply, {:ok, subscription}, state}

      :error ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:list_subscriptions, filters}, _from, state) do
    subscriptions =
      state.storage
      |> SubscriptionStorage.list_all()
      |> apply_filters(filters)

    {:reply, subscriptions, state}
  end

  @impl true
  def handle_call(:cleanup_orphaned_subscriptions, _from, state) do
    {cleaned_count, updated_state} = perform_cleanup(state)
    {:reply, {:ok, cleaned_count}, updated_state}
  end

  @impl true
  def handle_info(:cleanup_subscriptions, state) do
    Logger.debug("Running scheduled subscription cleanup")
    {cleaned_count, updated_state} = perform_cleanup(state)

    if cleaned_count > 0 do
      Logger.info("Cleaned up orphaned subscriptions", count: cleaned_count)
    end

    # Schedule next cleanup
    cleanup_timer = Process.send_after(self(), :cleanup_subscriptions, @cleanup_interval_ms)
    updated_state = %{updated_state | cleanup_timer: cleanup_timer}

    {:noreply, updated_state}
  end

  @impl true
  def handle_info(:emit_health_metrics, state) do
    report = generate_health_report(state)

    emit_telemetry([:health], %{
      total_subscriptions: report.total_subscriptions,
      enabled_subscriptions: report.enabled_subscriptions,
      failed_subscriptions: report.failed_subscriptions,
      orphaned_subscriptions: report.orphaned_subscriptions
    })

    # Schedule next health check
    health_timer = Process.send_after(self(), :emit_health_metrics, @health_check_interval_ms)
    updated_state = %{state | health_timer: health_timer}

    {:noreply, updated_state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("SubscriptionMonitor terminating", reason: reason)

    # Cancel timers
    if state.cleanup_timer, do: Process.cancel_timer(state.cleanup_timer)
    if state.health_timer, do: Process.cancel_timer(state.health_timer)

    :ok
  end

  ## Private Functions

  defp generate_health_report(state) do
    all_subscriptions = SubscriptionStorage.list_all(state.storage)

    total_count = length(all_subscriptions)
    enabled_count = Enum.count(all_subscriptions, &(&1.status == :enabled))

    failed_statuses = [
      :webhook_callback_verification_failed,
      :notification_failures_exceeded,
      :authorization_revoked,
      :moderator_removed,
      :user_removed,
      :version_removed
    ]

    failed_count = Enum.count(all_subscriptions, &(&1.status in failed_statuses))

    # Count orphaned subscriptions (no events for a long time)
    now = DateTime.utc_now()

    orphaned_count =
      Enum.count(all_subscriptions, fn sub ->
        case sub.last_event_at do
          nil ->
            # No events ever received, consider orphaned if created more than threshold ago
            DateTime.diff(now, sub.created_at, :millisecond) > @orphan_threshold_ms

          last_event ->
            DateTime.diff(now, last_event, :millisecond) > @orphan_threshold_ms
        end
      end)

    # Group by event type
    by_type = Enum.group_by(all_subscriptions, & &1.event_type)
    subscriptions_by_type = Map.new(by_type, fn {type, subs} -> {type, length(subs)} end)

    # Group by status
    by_status = Enum.group_by(all_subscriptions, & &1.status)
    subscriptions_by_status = Map.new(by_status, fn {status, subs} -> {status, length(subs)} end)

    # Find oldest subscription
    oldest_subscription =
      all_subscriptions
      |> Enum.map(& &1.created_at)
      |> Enum.min(DateTime, fn -> nil end)

    %{
      total_subscriptions: total_count,
      enabled_subscriptions: enabled_count,
      failed_subscriptions: failed_count,
      orphaned_subscriptions: orphaned_count,
      subscriptions_by_type: subscriptions_by_type,
      subscriptions_by_status: subscriptions_by_status,
      oldest_subscription: oldest_subscription,
      last_cleanup_at: state.last_cleanup_at
    }
  end

  defp perform_cleanup(state) do
    all_subscriptions = SubscriptionStorage.list_all(state.storage)
    now = DateTime.utc_now()

    # Find subscriptions that should be cleaned up
    to_cleanup =
      Enum.filter(all_subscriptions, fn subscription ->
        should_cleanup_subscription?(subscription, now)
      end)

    # Remove them from tracking
    Enum.each(to_cleanup, fn subscription ->
      SubscriptionStorage.delete(state.storage, subscription.id)

      Logger.info("Cleaned up subscription",
        subscription_id: subscription.id,
        event_type: subscription.event_type,
        status: subscription.status,
        reason: get_cleanup_reason(subscription, now)
      )

      emit_telemetry([:subscription, :cleaned_up], %{}, %{
        subscription_id: subscription.id,
        event_type: subscription.event_type,
        status: subscription.status
      })
    end)

    cleaned_count = length(to_cleanup)
    updated_state = %{state | last_cleanup_at: now}

    {cleaned_count, updated_state}
  end

  defp should_cleanup_subscription?(subscription, now) do
    # Cleanup failed subscriptions
    failed_statuses = [
      :webhook_callback_verification_failed,
      :notification_failures_exceeded,
      :authorization_revoked,
      :moderator_removed,
      :user_removed,
      :version_removed
    ]

    cond do
      subscription.status in failed_statuses ->
        true

      # Cleanup subscriptions with too many failures
      subscription.failure_count >= 10 ->
        true

      # Cleanup orphaned subscriptions
      orphaned_subscription?(subscription, now) ->
        true

      true ->
        false
    end
  end

  defp orphaned_subscription?(subscription, now) do
    case subscription.last_event_at do
      nil ->
        # No events ever received, consider orphaned if created more than threshold ago
        DateTime.diff(now, subscription.created_at, :millisecond) > @orphan_threshold_ms

      last_event ->
        DateTime.diff(now, last_event, :millisecond) > @orphan_threshold_ms
    end
  end

  defp get_cleanup_reason(subscription, now) do
    failed_statuses = [
      :webhook_callback_verification_failed,
      :notification_failures_exceeded,
      :authorization_revoked,
      :moderator_removed,
      :user_removed,
      :version_removed
    ]

    cond do
      subscription.status in failed_statuses ->
        "failed_status: #{subscription.status}"

      subscription.failure_count >= 10 ->
        "too_many_failures: #{subscription.failure_count}"

      orphaned_subscription?(subscription, now) ->
        "orphaned"

      true ->
        "unknown"
    end
  end

  defp apply_filters(subscriptions, []), do: subscriptions

  defp apply_filters(subscriptions, [{:status, status} | rest]) do
    subscriptions
    |> Enum.filter(&(&1.status == status))
    |> apply_filters(rest)
  end

  defp apply_filters(subscriptions, [{:event_type, event_type} | rest]) do
    subscriptions
    |> Enum.filter(&(&1.event_type == event_type))
    |> apply_filters(rest)
  end

  defp apply_filters(subscriptions, [_unknown_filter | rest]) do
    apply_filters(subscriptions, rest)
  end

  defp emit_telemetry(event_suffix, measurements, metadata \\ %{}) do
    event = [:server, :subscription_monitor] ++ event_suffix
    :telemetry.execute(event, measurements, metadata)
  end
end
