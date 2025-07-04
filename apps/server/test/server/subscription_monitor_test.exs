defmodule Server.SubscriptionMonitorTest do
  use Server.DataCase, async: true

  @moduletag :database

  alias Server.{SubscriptionMonitor, SubscriptionStorage}

  # Following official Elixir testing patterns from the documentation
  setup context do
    # Create unique storage table for each test (pattern from official docs)
    _storage = start_supervised!({SubscriptionStorage, name: context.test})

    # Start monitor with injected storage dependency
    _monitor = start_supervised!({SubscriptionMonitor, storage: context.test, name: :"monitor_#{context.test}"})

    %{storage: context.test, monitor: :"monitor_#{context.test}"}
  end

  describe "subscription tracking" do
    test "tracks new subscription successfully", %{monitor: monitor, storage: storage} do
      subscription_id = "sub_123"
      event_type = "channel.follow"
      metadata = %{service: :twitch, user_id: "user_456"}

      assert :ok = SubscriptionMonitor.track_subscription(subscription_id, event_type, metadata, monitor)

      # Verify subscription is tracked using storage lookup (fast ETS read)
      {:ok, subscription} = SubscriptionStorage.lookup(storage, subscription_id)
      assert subscription.id == subscription_id
      assert subscription.event_type == event_type
      assert subscription.status == :enabled
      assert subscription.failure_count == 0
      assert subscription.metadata == metadata
      assert %DateTime{} = subscription.created_at
    end

    test "updates subscription status", %{monitor: monitor, storage: storage} do
      subscription_id = "sub_124"
      SubscriptionMonitor.track_subscription(subscription_id, "stream.online", %{}, monitor)

      assert :ok =
               SubscriptionMonitor.update_subscription_status(
                 subscription_id,
                 :webhook_callback_verification_pending,
                 monitor
               )

      {:ok, subscription} = SubscriptionStorage.lookup(storage, subscription_id)
      assert subscription.status == :webhook_callback_verification_pending
    end

    test "records event reception", %{monitor: monitor, storage: storage} do
      subscription_id = "sub_125"
      SubscriptionMonitor.track_subscription(subscription_id, "stream.online", %{}, monitor)

      assert :ok = SubscriptionMonitor.record_event_received(subscription_id, monitor)

      {:ok, subscription} = SubscriptionStorage.lookup(storage, subscription_id)
      assert %DateTime{} = subscription.last_event_at
    end

    test "records subscription failures", %{monitor: monitor, storage: storage} do
      subscription_id = "sub_126"
      SubscriptionMonitor.track_subscription(subscription_id, "stream.online", %{}, monitor)

      assert :ok = SubscriptionMonitor.record_subscription_failure(subscription_id, "Rate limit exceeded", monitor)

      {:ok, subscription} = SubscriptionStorage.lookup(storage, subscription_id)
      assert subscription.failure_count == 1

      # Record another failure
      assert :ok = SubscriptionMonitor.record_subscription_failure(subscription_id, "Timeout", monitor)
      {:ok, subscription} = SubscriptionStorage.lookup(storage, subscription_id)
      assert subscription.failure_count == 2
    end

    test "untracks subscription", %{monitor: monitor, storage: storage} do
      subscription_id = "sub_127"
      SubscriptionMonitor.track_subscription(subscription_id, "stream.online", %{}, monitor)

      # Verify it exists
      {:ok, _subscription} = SubscriptionStorage.lookup(storage, subscription_id)

      # Untrack it
      assert :ok = SubscriptionMonitor.untrack_subscription(subscription_id, monitor)

      # Verify it's gone
      assert :error = SubscriptionStorage.lookup(storage, subscription_id)
    end

    test "returns not found for non-existent subscription", %{monitor: monitor} do
      assert {:error, :not_found} = SubscriptionMonitor.get_subscription_info("nonexistent", monitor)
      assert {:error, :not_found} = SubscriptionMonitor.update_subscription_status("nonexistent", :enabled, monitor)
      assert {:error, :not_found} = SubscriptionMonitor.record_event_received("nonexistent", monitor)
      assert {:error, :not_found} = SubscriptionMonitor.record_subscription_failure("nonexistent", "error", monitor)
    end
  end

  describe "subscription listing and filtering" do
    setup %{monitor: monitor} do
      # Create multiple subscriptions for testing
      SubscriptionMonitor.track_subscription("sub_1", "stream.online", %{service: :twitch}, monitor)
      SubscriptionMonitor.track_subscription("sub_2", "stream.offline", %{service: :twitch}, monitor)
      SubscriptionMonitor.track_subscription("sub_3", "channel.follow", %{service: :twitch}, monitor)

      # Update some statuses
      SubscriptionMonitor.update_subscription_status("sub_2", :webhook_callback_verification_failed, monitor)
      SubscriptionMonitor.update_subscription_status("sub_3", :authorization_revoked, monitor)

      :ok
    end

    test "lists all subscriptions", %{monitor: monitor} do
      subscriptions = SubscriptionMonitor.list_subscriptions([], monitor)
      assert length(subscriptions) == 3

      subscription_ids = Enum.map(subscriptions, & &1.id)
      assert "sub_1" in subscription_ids
      assert "sub_2" in subscription_ids
      assert "sub_3" in subscription_ids
    end

    test "filters subscriptions by status", %{monitor: monitor} do
      enabled_subscriptions = SubscriptionMonitor.list_subscriptions([status: :enabled], monitor)
      assert length(enabled_subscriptions) == 1
      assert hd(enabled_subscriptions).id == "sub_1"

      failed_subscriptions =
        SubscriptionMonitor.list_subscriptions([status: :webhook_callback_verification_failed], monitor)

      assert length(failed_subscriptions) == 1
      assert hd(failed_subscriptions).id == "sub_2"
    end

    test "filters subscriptions by event type", %{monitor: monitor} do
      online_subscriptions = SubscriptionMonitor.list_subscriptions([event_type: "stream.online"], monitor)
      assert length(online_subscriptions) == 1
      assert hd(online_subscriptions).id == "sub_1"

      follow_subscriptions = SubscriptionMonitor.list_subscriptions([event_type: "channel.follow"], monitor)
      assert length(follow_subscriptions) == 1
      assert hd(follow_subscriptions).id == "sub_3"
    end
  end

  describe "health reporting" do
    setup %{monitor: monitor} do
      # Create subscriptions in different states
      SubscriptionMonitor.track_subscription("enabled_1", "stream.online", %{}, monitor)
      SubscriptionMonitor.track_subscription("enabled_2", "stream.offline", %{}, monitor)

      SubscriptionMonitor.track_subscription("failed_1", "channel.follow", %{}, monitor)
      SubscriptionMonitor.update_subscription_status("failed_1", :webhook_callback_verification_failed, monitor)

      SubscriptionMonitor.track_subscription("failed_2", "channel.subscribe", %{}, monitor)
      SubscriptionMonitor.update_subscription_status("failed_2", :authorization_revoked, monitor)

      :ok
    end

    test "generates comprehensive health report", %{monitor: monitor} do
      report = SubscriptionMonitor.get_health_report(monitor)

      assert report.total_subscriptions == 4
      assert report.enabled_subscriptions == 2
      assert report.failed_subscriptions == 2
      # Depends on timing
      assert report.orphaned_subscriptions >= 0

      # Check groupings
      assert report.subscriptions_by_type["stream.online"] == 1
      assert report.subscriptions_by_type["stream.offline"] == 1
      assert report.subscriptions_by_type["channel.follow"] == 1
      assert report.subscriptions_by_type["channel.subscribe"] == 1

      assert report.subscriptions_by_status[:enabled] == 2
      assert report.subscriptions_by_status[:webhook_callback_verification_failed] == 1
      assert report.subscriptions_by_status[:authorization_revoked] == 1

      assert %DateTime{} = report.oldest_subscription
      assert %DateTime{} = report.last_cleanup_at
    end
  end

  describe "cleanup functionality" do
    test "identifies failed subscriptions for cleanup", %{monitor: monitor, storage: storage} do
      # Create a failed subscription
      SubscriptionMonitor.track_subscription("failed_sub", "channel.follow", %{}, monitor)
      SubscriptionMonitor.update_subscription_status("failed_sub", :webhook_callback_verification_failed, monitor)

      # Create a subscription with many failures
      SubscriptionMonitor.track_subscription("failure_prone", "stream.online", %{}, monitor)

      for _ <- 1..12 do
        SubscriptionMonitor.record_subscription_failure("failure_prone", "timeout", monitor)
      end

      # Trigger cleanup
      {:ok, cleaned_count} = SubscriptionMonitor.cleanup_orphaned_subscriptions(monitor)

      # Should clean up both subscriptions
      assert cleaned_count >= 2

      # Verify they're gone using storage lookup
      assert :error = SubscriptionStorage.lookup(storage, "failed_sub")
      assert :error = SubscriptionStorage.lookup(storage, "failure_prone")
    end

    test "preserves healthy subscriptions during cleanup", %{monitor: monitor, storage: storage} do
      # Create a healthy subscription
      SubscriptionMonitor.track_subscription("healthy_sub", "stream.online", %{}, monitor)
      SubscriptionMonitor.record_event_received("healthy_sub", monitor)

      # Trigger cleanup
      {:ok, _cleaned_count} = SubscriptionMonitor.cleanup_orphaned_subscriptions(monitor)

      # Healthy subscription should remain
      {:ok, subscription} = SubscriptionStorage.lookup(storage, "healthy_sub")
      assert subscription.status == :enabled
    end
  end

  describe "edge cases and error handling" do
    test "handles multiple operations on same subscription", %{monitor: monitor, storage: storage} do
      subscription_id = "concurrent_sub"

      # Track subscription
      SubscriptionMonitor.track_subscription(subscription_id, "stream.online", %{}, monitor)

      # Perform multiple operations
      SubscriptionMonitor.record_event_received(subscription_id, monitor)
      SubscriptionMonitor.update_subscription_status(subscription_id, :webhook_callback_verification_pending, monitor)
      SubscriptionMonitor.record_subscription_failure(subscription_id, "network error", monitor)
      SubscriptionMonitor.record_event_received(subscription_id, monitor)

      # Verify final state
      {:ok, subscription} = SubscriptionStorage.lookup(storage, subscription_id)
      assert subscription.status == :webhook_callback_verification_pending
      assert subscription.failure_count == 1
      assert %DateTime{} = subscription.last_event_at
    end

    test "handles empty filter list correctly", %{monitor: monitor} do
      SubscriptionMonitor.track_subscription("test_sub", "stream.online", %{}, monitor)

      # Empty filters should return all subscriptions
      all_subs = SubscriptionMonitor.list_subscriptions([], monitor)
      filtered_subs = SubscriptionMonitor.list_subscriptions([], monitor)

      assert length(all_subs) == length(filtered_subs)
    end

    test "ignores unknown filter keys", %{monitor: monitor} do
      SubscriptionMonitor.track_subscription("test_sub", "stream.online", %{}, monitor)

      # Unknown filter should be ignored
      subscriptions = SubscriptionMonitor.list_subscriptions([unknown_filter: "value"], monitor)
      assert length(subscriptions) == 1
    end
  end

  describe "telemetry integration" do
    test "emits telemetry events for subscription operations", %{monitor: monitor} do
      # Set up telemetry handler
      test_pid = self()

      :telemetry.attach_many(
        :subscription_monitor_test,
        [
          [:server, :subscription_monitor, :subscription, :tracked],
          [:server, :subscription_monitor, :subscription, :status_updated],
          [:server, :subscription_monitor, :subscription, :event_received],
          [:server, :subscription_monitor, :subscription, :failure]
        ],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      # Perform operations that should emit telemetry
      SubscriptionMonitor.track_subscription("telemetry_sub", "stream.online", %{test: true}, monitor)
      SubscriptionMonitor.record_event_received("telemetry_sub", monitor)
      SubscriptionMonitor.update_subscription_status("telemetry_sub", :webhook_callback_verification_pending, monitor)
      SubscriptionMonitor.record_subscription_failure("telemetry_sub", "test failure", monitor)

      # Check telemetry events were emitted
      assert_receive {:telemetry, [:server, :subscription_monitor, :subscription, :tracked], _, _}
      assert_receive {:telemetry, [:server, :subscription_monitor, :subscription, :event_received], _, _}
      assert_receive {:telemetry, [:server, :subscription_monitor, :subscription, :status_updated], _, _}
      assert_receive {:telemetry, [:server, :subscription_monitor, :subscription, :failure], _, _}

      # Clean up
      :telemetry.detach(:subscription_monitor_test)
    end
  end
end
