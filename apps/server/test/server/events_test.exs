defmodule Server.EventsTest do
  use ExUnit.Case, async: false

  alias Server.Events

  describe "Event publishing and subscription" do
    test "publishes and receives OBS events" do
      Events.subscribe_to_obs_events()

      Events.publish_obs_event("test_event", %{test: "data"}, batch: false)

      assert_receive {:obs_event, event}
      assert event.type == "test_event"
      assert event.data == %{test: "data"}
      assert Map.has_key?(event, :timestamp)
      assert Map.has_key?(event, :correlation_id)
    end

    test "publishes and receives Twitch events" do
      Events.subscribe_to_twitch_events()

      Events.publish_twitch_event("channel.update", %{broadcaster_user_name: "test"}, batch: false)

      assert_receive {:twitch_event, event}
      assert event.type == "channel.update"
      assert event.data == %{broadcaster_user_name: "test"}
      assert Map.has_key?(event, :timestamp)
      assert Map.has_key?(event, :correlation_id)
    end

    test "publishes and receives system events" do
      Events.subscribe_to_system_events()

      Events.publish_system_event("startup", %{version: "1.0.0"})

      assert_receive {:system_event, event}
      assert event.type == "startup"
      assert event.data == %{version: "1.0.0"}
    end

    test "publishes and receives health updates" do
      Events.subscribe_to_health_events()

      Events.publish_health_update("obs", "healthy", %{details: "connected"})

      assert_receive {:health_update, data}
      assert data.service == "obs"
      assert data.status == "healthy"
      assert data.details == %{details: "connected"}
      assert Map.has_key?(data, :timestamp)
    end

    test "publishes and receives performance updates" do
      Events.subscribe_to_performance_events()

      Events.publish_performance_update("cpu_usage", 45.2, %{core_count: 8})

      assert_receive {:performance_update, data}
      assert data.metric == "cpu_usage"
      assert data.value == 45.2
      assert data.metadata == %{core_count: 8}
      assert Map.has_key?(data, :timestamp)
    end

    test "unsubscribe works correctly" do
      Events.subscribe_to_obs_events()
      Events.unsubscribe_from_obs_events()

      Events.publish_obs_event("test_event", %{test: "data"}, batch: false)

      # Should not receive the event after unsubscribing
      refute_receive {:obs_event, _event}, 100
    end
  end
end
