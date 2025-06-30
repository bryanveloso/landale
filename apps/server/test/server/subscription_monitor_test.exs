defmodule Server.SubscriptionMonitorTest do
  use ExUnit.Case, async: false

  alias Server.SubscriptionMonitor

  setup do
    # Ensure clean state by stopping any existing monitor
    if Process.whereis(SubscriptionMonitor) do
      GenServer.stop(SubscriptionMonitor)
    end
    
    # Start fresh monitor for each test
    {:ok, monitor} = start_supervised(SubscriptionMonitor)
    
    %{monitor: monitor}
  end

  describe "subscription tracking" do
    test "tracks new subscription successfully" do
      subscription_id = "sub_123"
      event_type = "channel.follow"
      metadata = %{service: :twitch, user_id: "user_456"}

      assert :ok = SubscriptionMonitor.track_subscription(subscription_id, event_type, metadata)

      # Verify subscription is tracked
      {:ok, subscription} = SubscriptionMonitor.get_subscription_info(subscription_id)
      assert subscription.id == subscription_id
      assert subscription.event_type == event_type
      assert subscription.status == :enabled
      assert subscription.failure_count == 0
      assert subscription.metadata == metadata
      assert %DateTime{} = subscription.created_at
    end

    test "updates subscription status" do
      subscription_id = "sub_124"
      SubscriptionMonitor.track_subscription(subscription_id, "stream.online")

      assert :ok =
               SubscriptionMonitor.update_subscription_status(subscription_id, :webhook_callback_verification_pending)

      {:ok, subscription} = SubscriptionMonitor.get_subscription_info(subscription_id)
      assert subscription.status == :webhook_callback_verification_pending
    end

    test "records event reception" do
      subscription_id = "sub_125"
      SubscriptionMonitor.track_subscription(subscription_id, "stream.online")

      assert :ok = SubscriptionMonitor.record_event_received(subscription_id)

      {:ok, subscription} = SubscriptionMonitor.get_subscription_info(subscription_id)
      assert %DateTime{} = subscription.last_event_at
    end

    test "records subscription failures" do
      subscription_id = "sub_126"
      SubscriptionMonitor.track_subscription(subscription_id, "stream.online")

      assert :ok = SubscriptionMonitor.record_subscription_failure(subscription_id, "Rate limit exceeded")

      {:ok, subscription} = SubscriptionMonitor.get_subscription_info(subscription_id)
      assert subscription.failure_count == 1

      # Record another failure
      assert :ok = SubscriptionMonitor.record_subscription_failure(subscription_id, "Timeout")
      {:ok, subscription} = SubscriptionMonitor.get_subscription_info(subscription_id)
      assert subscription.failure_count == 2
    end

    test "untracks subscription" do
      subscription_id = "sub_127"
      SubscriptionMonitor.track_subscription(subscription_id, "stream.online")

      # Verify it exists
      {:ok, _subscription} = SubscriptionMonitor.get_subscription_info(subscription_id)

      # Untrack it
      assert :ok = SubscriptionMonitor.untrack_subscription(subscription_id)

      # Verify it's gone
      assert {:error, :not_found} = SubscriptionMonitor.get_subscription_info(subscription_id)
    end

    test "returns not found for non-existent subscription" do
      assert {:error, :not_found} = SubscriptionMonitor.get_subscription_info("nonexistent")
      assert {:error, :not_found} = SubscriptionMonitor.update_subscription_status("nonexistent", :enabled)
      assert {:error, :not_found} = SubscriptionMonitor.record_event_received("nonexistent")
      assert {:error, :not_found} = SubscriptionMonitor.record_subscription_failure("nonexistent", "error")
    end
  end

  describe "subscription listing and filtering" do
    setup do
      # Create multiple subscriptions for testing
      SubscriptionMonitor.track_subscription("sub_1", "stream.online", %{service: :twitch})
      SubscriptionMonitor.track_subscription("sub_2", "stream.offline", %{service: :twitch})
      SubscriptionMonitor.track_subscription("sub_3", "channel.follow", %{service: :twitch})

      # Update some statuses
      SubscriptionMonitor.update_subscription_status("sub_2", :webhook_callback_verification_failed)
      SubscriptionMonitor.update_subscription_status("sub_3", :authorization_revoked)

      :ok
    end

    test "lists all subscriptions" do
      subscriptions = SubscriptionMonitor.list_subscriptions()
      assert length(subscriptions) == 3

      subscription_ids = Enum.map(subscriptions, & &1.id)
      assert "sub_1" in subscription_ids
      assert "sub_2" in subscription_ids
      assert "sub_3" in subscription_ids
    end

    test "filters subscriptions by status" do
      enabled_subscriptions = SubscriptionMonitor.list_subscriptions(status: :enabled)
      assert length(enabled_subscriptions) == 1
      assert hd(enabled_subscriptions).id == "sub_1"

      failed_subscriptions = SubscriptionMonitor.list_subscriptions(status: :webhook_callback_verification_failed)
      assert length(failed_subscriptions) == 1
      assert hd(failed_subscriptions).id == "sub_2"
    end

    test "filters subscriptions by event type" do
      online_subscriptions = SubscriptionMonitor.list_subscriptions(event_type: "stream.online")
      assert length(online_subscriptions) == 1
      assert hd(online_subscriptions).id == "sub_1"

      follow_subscriptions = SubscriptionMonitor.list_subscriptions(event_type: "channel.follow")
      assert length(follow_subscriptions) == 1
      assert hd(follow_subscriptions).id == "sub_3"
    end
  end

  describe "health reporting" do
    setup do
      # Create subscriptions in different states
      SubscriptionMonitor.track_subscription("enabled_1", "stream.online")
      SubscriptionMonitor.track_subscription("enabled_2", "stream.offline")

      SubscriptionMonitor.track_subscription("failed_1", "channel.follow")
      SubscriptionMonitor.update_subscription_status("failed_1", :webhook_callback_verification_failed)

      SubscriptionMonitor.track_subscription("failed_2", "channel.subscribe")
      SubscriptionMonitor.update_subscription_status("failed_2", :authorization_revoked)

      :ok
    end

    test "generates comprehensive health report" do
      report = SubscriptionMonitor.get_health_report()

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
    test "identifies failed subscriptions for cleanup" do
      # Create a failed subscription
      SubscriptionMonitor.track_subscription("failed_sub", "channel.follow")
      SubscriptionMonitor.update_subscription_status("failed_sub", :webhook_callback_verification_failed)

      # Create a subscription with many failures
      SubscriptionMonitor.track_subscription("failure_prone", "stream.online")

      for _ <- 1..12 do
        SubscriptionMonitor.record_subscription_failure("failure_prone", "timeout")
      end

      # Trigger cleanup
      {:ok, cleaned_count} = SubscriptionMonitor.cleanup_orphaned_subscriptions()

      # Should clean up both subscriptions
      assert cleaned_count >= 2

      # Verify they're gone
      assert {:error, :not_found} = SubscriptionMonitor.get_subscription_info("failed_sub")
      assert {:error, :not_found} = SubscriptionMonitor.get_subscription_info("failure_prone")
    end

    test "preserves healthy subscriptions during cleanup" do
      # Create a healthy subscription
      SubscriptionMonitor.track_subscription("healthy_sub", "stream.online")
      SubscriptionMonitor.record_event_received("healthy_sub")

      # Trigger cleanup
      {:ok, _cleaned_count} = SubscriptionMonitor.cleanup_orphaned_subscriptions()

      # Healthy subscription should remain
      {:ok, subscription} = SubscriptionMonitor.get_subscription_info("healthy_sub")
      assert subscription.status == :enabled
    end
  end

  describe "edge cases and error handling" do
    test "handles multiple operations on same subscription" do
      subscription_id = "concurrent_sub"

      # Track subscription
      SubscriptionMonitor.track_subscription(subscription_id, "stream.online")

      # Perform multiple operations
      SubscriptionMonitor.record_event_received(subscription_id)
      SubscriptionMonitor.update_subscription_status(subscription_id, :webhook_callback_verification_pending)
      SubscriptionMonitor.record_subscription_failure(subscription_id, "network error")
      SubscriptionMonitor.record_event_received(subscription_id)

      # Verify final state
      {:ok, subscription} = SubscriptionMonitor.get_subscription_info(subscription_id)
      assert subscription.status == :webhook_callback_verification_pending
      assert subscription.failure_count == 1
      assert %DateTime{} = subscription.last_event_at
    end

    test "handles empty filter list correctly" do
      SubscriptionMonitor.track_subscription("test_sub", "stream.online")

      # Empty filters should return all subscriptions
      all_subs = SubscriptionMonitor.list_subscriptions([])
      filtered_subs = SubscriptionMonitor.list_subscriptions()

      assert length(all_subs) == length(filtered_subs)
    end

    test "ignores unknown filter keys" do
      SubscriptionMonitor.track_subscription("test_sub", "stream.online")

      # Unknown filter should be ignored
      subscriptions = SubscriptionMonitor.list_subscriptions(unknown_filter: "value")
      assert length(subscriptions) == 1
    end
  end

  describe "telemetry integration" do
    test "emits telemetry events for subscription operations" do
      # Set up telemetry handler
      _events = []
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
      SubscriptionMonitor.track_subscription("telemetry_sub", "stream.online", %{test: true})
      SubscriptionMonitor.record_event_received("telemetry_sub")
      SubscriptionMonitor.update_subscription_status("telemetry_sub", :webhook_callback_verification_pending)
      SubscriptionMonitor.record_subscription_failure("telemetry_sub", "test failure")

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
