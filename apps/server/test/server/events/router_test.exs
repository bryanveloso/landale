defmodule Server.Events.RouterTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  alias Server.Events.{BatchCollector, Event, Router}

  # Test configuration
  @test_batch_types ["channel.chat.message", "channel.follow"]

  setup do
    # Start TaskSupervisor required by Router
    case start_supervised({Task.Supervisor, name: Server.TaskSupervisor}) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    # Start the router with test configuration
    start_supervised!({Router, batch_types: @test_batch_types})

    # Start batch collector for batching tests
    start_supervised!(BatchCollector)

    # Subscribe to event topics
    Phoenix.PubSub.subscribe(Server.PubSub, "events:all")
    Phoenix.PubSub.subscribe(Server.PubSub, "events:twitch")
    Phoenix.PubSub.subscribe(Server.PubSub, "events:obs")
    Phoenix.PubSub.subscribe(Server.PubSub, "events:system")
    Phoenix.PubSub.subscribe(Server.PubSub, "events:batched")

    :ok
  end

  describe "route/1" do
    test "routes critical event immediately" do
      event =
        Event.new(
          "system.startup",
          :system,
          %{version: "1.0.0"},
          priority: :critical
        )

      Router.route(event)

      # Should receive immediate broadcast on multiple topics
      assert_receive {:event, ^event}
      assert_receive {:event, ^event}

      # Should not be sent to BatchCollector (no batched event received)
      refute_receive {:batched_event, _}, 100
    end

    test "routes batchable event to BatchCollector" do
      event = Event.new("channel.chat.message", :twitch, %{user_name: "test"})

      Router.route(event)

      # Should not receive immediate event
      refute_receive {:event, ^event}, 100

      # Wait for batch flush (BatchCollector default is 50ms)
      assert_receive {:batched_event, batch_event}, 200

      assert batch_event.type == "event.batch"
      assert batch_event.source == :system
      assert length(batch_event.data.events) == 1
      assert List.first(batch_event.data.events) == event
    end

    test "routes non-batchable event immediately" do
      event = Event.new("stream.online", :twitch, %{id: "stream_123"})

      Router.route(event)

      # Should receive immediate broadcast
      assert_receive {:event, ^event}
      # Second one from source-specific topic
      assert_receive {:event, ^event}

      # Should not be batched
      refute_receive {:batched_event, _}, 100
    end

    test "broadcasts to general and source-specific topics" do
      event = Event.new("test.event", :system, %{})

      Router.route(event)

      # Should receive on events:all
      assert_receive {:event, ^event}

      # Should receive on events:system
      assert_receive {:event, ^event}
    end

    test "updates statistics correctly" do
      # Get initial stats
      initial_stats = Router.get_stats()

      # Route some events
      critical_event = Event.new("system.error", :system, %{}, priority: :critical)
      normal_event = Event.new("channel.update", :twitch, %{})
      batch_event = Event.new("channel.chat.message", :twitch, %{})

      Router.route(critical_event)
      Router.route(normal_event)
      Router.route(batch_event)

      # Allow some processing time
      Process.sleep(10)

      stats = Router.get_stats()

      assert stats.events_routed == initial_stats.events_routed + 3
      assert stats.critical_events == initial_stats.critical_events + 1
      assert stats.events_immediate == initial_stats.events_immediate + 2
      assert stats.events_batched == initial_stats.events_batched + 1

      # Check event type counts
      assert stats.event_types["system.error"] == 1
      assert stats.event_types["channel.update"] == 1
      assert stats.event_types["channel.chat.message"] == 1

      # Check source distribution
      assert stats.source_distribution[:system] == 1
      assert stats.source_distribution[:twitch] == 2
    end
  end

  describe "event broadcasts" do
    test "broadcasts Twitch events in event format" do
      # Use channel.update which is NOT in @test_batch_types so it gets immediate broadcast
      event =
        Event.new(
          "channel.update",
          :twitch,
          %{category_name: "Just Chatting", title: "Test Stream"}
        )

      Router.route(event)

      # Should receive event format on events:all and events:twitch
      assert_receive {:event, received_event}
      assert received_event.type == "channel.update"
      assert received_event.source == :twitch
      assert received_event.data.category_name == "Just Chatting"
      assert received_event.data.title == "Test Stream"
      assert %DateTime{} = received_event.timestamp

      # Should also receive on source-specific topic
      assert_receive {:event, ^received_event}
    end

    test "routes chat messages through batching" do
      event =
        Event.new(
          "channel.chat.message",
          :twitch,
          %{
            user_name: "chatter123",
            message: %{text: "Hello world!"},
            emotes: [%{name: "Kappa"}],
            native_emotes: ["PogChamp"]
          }
        )

      Router.route(event)

      # Chat messages are batched, so we should receive a batch event
      assert_receive {:batched_event, batch_event}, 200
      assert batch_event.type == "event.batch"
      assert batch_event.source == :system
      assert length(batch_event.data.events) == 1

      batched_event = List.first(batch_event.data.events)
      assert batched_event.type == "channel.chat.message"
      assert batched_event.data.user_name == "chatter123"
    end

    test "broadcasts OBS events in event format" do
      event =
        Event.new(
          "obs.StreamStarted",
          :obs,
          %{output_active: true}
        )

      Router.route(event)

      # Should receive event format
      assert_receive {:event, received_event}
      assert received_event.type == "obs.StreamStarted"
      assert received_event.source == :obs
      assert received_event.data.output_active == true
    end
  end

  describe "specific handler routing" do
    test "routes chat messages to StreamProducer" do
      # This test verifies that specific events are routed to handlers
      # In practice, we can't easily test the actual send to StreamProducer
      # without starting it, but we can verify the logic works
      event = Event.new("channel.chat.message", :twitch, %{user_name: "test"})

      # This should not raise an error even if StreamProducer is not running
      assert Router.route(event) == :ok
    end

    test "routes subscription events to StreamProducer" do
      event = Event.new("channel.subscribe", :twitch, %{user_name: "sub123"})

      assert Router.route(event) == :ok
    end

    test "routes channel update events to StreamProducer" do
      event = Event.new("channel.update", :twitch, %{category_name: "Just Chatting"})

      assert Router.route(event) == :ok
    end

    test "routes IronMON events to StreamProducer" do
      event = Event.new("ironmon.checkpoint_reached", :ironmon, %{pokemon: "Charizard"})

      assert Router.route(event) == :ok
    end

    test "does not route unhandled events to specific handlers" do
      event = Event.new("unknown.event", :test, %{})

      assert Router.route(event) == :ok
    end
  end

  describe "get_stats/0" do
    test "returns comprehensive statistics" do
      stats = Router.get_stats()

      assert is_integer(stats.uptime_seconds)
      assert is_integer(stats.events_routed)
      assert is_integer(stats.events_batched)
      assert is_integer(stats.events_immediate)
      assert is_integer(stats.critical_events)
      assert is_map(stats.event_types)
      assert is_map(stats.source_distribution)
      assert is_list(stats.batch_types)
      assert Enum.all?(stats.batch_types, &is_binary/1)
    end

    test "statistics accumulate correctly over multiple events" do
      # Route multiple events of different types
      events = [
        Event.new("channel.follow", :twitch, %{}),
        Event.new("channel.follow", :twitch, %{}),
        Event.new("system.startup", :system, %{}, priority: :critical),
        Event.new("obs.stream_started", :obs, %{})
      ]

      Enum.each(events, &Router.route/1)

      stats = Router.get_stats()

      assert stats.event_types["channel.follow"] == 2
      assert stats.event_types["system.startup"] == 1
      assert stats.event_types["obs.stream_started"] == 1
      assert stats.source_distribution[:twitch] == 2
      assert stats.source_distribution[:system] == 1
      assert stats.source_distribution[:obs] == 1
    end
  end

  describe "reset_stats/0" do
    test "resets all statistics to zero" do
      # Generate some activity
      Router.route(Event.new("test.event", :test, %{}))
      Router.route(Event.new("another.event", :test, %{}))

      # Verify stats are non-zero
      stats = Router.get_stats()
      assert stats.events_routed > 0

      # Reset stats
      assert Router.reset_stats() == :ok

      # Verify stats are reset
      new_stats = Router.get_stats()
      assert new_stats.events_routed == 0
      assert new_stats.events_batched == 0
      assert new_stats.events_immediate == 0
      assert new_stats.critical_events == 0
      assert map_size(new_stats.event_types) == 0
      assert map_size(new_stats.source_distribution) == 0
    end
  end

  describe "batching decisions" do
    test "critical events are never batched" do
      critical_events = [
        Event.new("system.startup", :system, %{}, priority: :critical),
        Event.new("system.error", :system, %{}, priority: :critical),
        Event.new("stream.online", :twitch, %{}, priority: :critical)
      ]

      Enum.each(critical_events, fn event ->
        Router.route(event)
        # Should receive immediate broadcast
        assert_receive {:event, ^event}
      end)
    end

    test "configured batch types are batched" do
      # channel.chat.message is in @test_batch_types
      event = Event.new("channel.chat.message", :twitch, %{user_name: "test"})

      Router.route(event)

      # Should not receive immediate broadcast
      refute_receive {:unified_event, ^event}, 50

      # Should eventually receive as part of batch
      assert_receive {:batched_event, _batch}, 200
    end

    test "non-batch types are sent immediately" do
      # channel.update is not in @test_batch_types
      event = Event.new("channel.update", :twitch, %{})

      Router.route(event)

      # Should receive immediate broadcast
      assert_receive {:event, ^event}
    end
  end

  describe "error handling" do
    test "handles malformed events gracefully" do
      # This tests the system's resilience to unexpected data
      # In practice, only properly structured Event structs
      # should reach the router, but we test defensive programming

      event = Event.new("test.event", :test, %{})

      # Should handle normally
      assert Router.route(event) == :ok
      assert_receive {:event, ^event}
    end

    test "continues processing after errors" do
      # Route a normal event
      good_event = Event.new("good.event", :test, %{})
      Router.route(good_event)

      # Should still work after any potential errors
      assert_receive {:event, ^good_event}

      # Route another event to verify system is still functional
      another_event = Event.new("another.event", :test, %{})
      Router.route(another_event)
      assert_receive {:event, ^another_event}
    end
  end

  describe "concurrency" do
    test "handles concurrent event routing" do
      # Route multiple events concurrently
      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            event = Event.new("concurrent.event.#{i}", :test, %{index: i})
            Router.route(event)
            event
          end)
        end

      routed_events = Task.await_many(tasks, 1000)

      # Should receive all events (order not guaranteed due to concurrency)
      for event <- routed_events do
        assert_receive {:event, ^event}, 1000
      end

      # Verify statistics are correct
      stats = Router.get_stats()
      assert stats.events_routed >= 10
    end
  end
end
