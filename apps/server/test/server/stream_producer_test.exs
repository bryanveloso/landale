defmodule Server.StreamProducerTest do
  use ExUnit.Case, async: false

  alias Server.StreamProducer

  setup do
    # Start a fresh StreamProducer for each test
    {:ok, pid} = GenServer.start_link(StreamProducer, [])
    {:ok, producer: pid}
  end

  describe "state management" do
    test "starts with default state", %{producer: producer} do
      state = GenServer.call(producer, :get_state)

      assert state.current_show == :variety
      assert state.active_content == nil
      assert state.interrupt_stack == []
      assert state.ticker_rotation != []
      assert state.version == 0
    end

    test "show changes update ticker content", %{producer: producer} do
      GenServer.cast(producer, {:change_show, :ironmon, %{}})

      state = GenServer.call(producer, :get_state)
      assert state.current_show == :ironmon
      assert :ironmon_run_stats in state.ticker_rotation
      assert state.version == 1
    end
  end

  describe "interrupt management" do
    test "adds interrupt with correct priority", %{producer: producer} do
      GenServer.cast(producer, {:add_interrupt, :alert, %{message: "Test alert"}, []})

      state = GenServer.call(producer, :get_state)
      assert Enum.count(state.interrupt_stack) == 1

      interrupt = List.first(state.interrupt_stack)
      assert interrupt.type == :alert
      assert interrupt.priority == 100
      assert interrupt.data.message == "Test alert"
    end

    test "prioritizes interrupts correctly", %{producer: producer} do
      # Add lower priority interrupt first
      GenServer.cast(producer, {:add_interrupt, :sub_train, %{count: 1}, []})
      # Add higher priority interrupt
      GenServer.cast(producer, {:add_interrupt, :alert, %{message: "Breaking"}, []})

      state = GenServer.call(producer, :get_state)
      assert Enum.count(state.interrupt_stack) == 2

      # Alert should be first (higher priority)
      [first, second] = state.interrupt_stack
      assert first.type == :alert
      assert second.type == :sub_train
    end

    test "removes interrupt by id", %{producer: producer} do
      interrupt_id = "test-interrupt"
      GenServer.cast(producer, {:add_interrupt, :alert, %{}, [id: interrupt_id]})

      state = GenServer.call(producer, :get_state)
      assert Enum.count(state.interrupt_stack) == 1

      GenServer.cast(producer, {:remove_interrupt, interrupt_id})

      state = GenServer.call(producer, :get_state)
      assert Enum.empty?(state.interrupt_stack)
    end
  end

  describe "sub train handling" do
    test "creates new sub train", %{producer: producer} do
      event = %{user_name: "testuser", tier: "1000", cumulative_months: 5}
      send(producer, {:new_subscription, event})

      # Give time for async processing
      Process.sleep(10)

      state = GenServer.call(producer, :get_state)
      assert Enum.count(state.interrupt_stack) == 1

      sub_train = List.first(state.interrupt_stack)
      assert sub_train.type == :sub_train
      assert sub_train.data.subscriber == "testuser"
      assert sub_train.data.count == 1
    end

    test "extends existing sub train", %{producer: producer} do
      # Create initial sub train
      event1 = %{user_name: "user1", tier: "1000"}
      send(producer, {:new_subscription, event1})
      Process.sleep(10)

      # Add another subscription
      event2 = %{user_name: "user2", tier: "2000"}
      send(producer, {:new_subscription, event2})
      Process.sleep(10)

      state = GenServer.call(producer, :get_state)
      assert Enum.count(state.interrupt_stack) == 1

      sub_train = List.first(state.interrupt_stack)
      assert sub_train.data.count == 2
      assert sub_train.data.latest_subscriber == "user2"
    end
  end

  describe "active content selection" do
    test "selects highest priority interrupt as active content", %{producer: producer} do
      GenServer.cast(producer, {:add_interrupt, :sub_train, %{count: 3}, []})
      GenServer.cast(producer, {:add_interrupt, :alert, %{message: "Alert"}, []})

      state = GenServer.call(producer, :get_state)
      assert state.active_content.type == :alert
    end

    test "falls back to ticker when no interrupts", %{producer: producer} do
      # Trigger ticker advancement to ensure active content is set
      send(producer, :ticker_tick)
      Process.sleep(10)

      state = GenServer.call(producer, :get_state)
      assert state.active_content != nil
      assert state.active_content.type in [:emote_stats, :recent_follows, :stream_goals, :daily_stats]
    end

    test "priority hierarchy works correctly", %{producer: producer} do
      # Add sub train first (priority 50)
      GenServer.cast(producer, {:add_interrupt, :sub_train, %{count: 5, subscriber: "user1"}, []})

      state = GenServer.call(producer, :get_state)
      assert state.active_content.type == :sub_train

      # Add alert (priority 100) - should win over sub train
      GenServer.cast(producer, {:add_interrupt, :alert, %{message: "Breaking News"}, []})

      state = GenServer.call(producer, :get_state)
      # Alert should win due to higher priority
      assert state.active_content.type == :alert
      assert state.active_content.data.message == "Breaking News"
    end
  end

  describe "timer management" do
    test "atomic timer registration prevents race conditions", %{producer: producer} do
      # Test with unique IDs to actually test the atomicity
      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            GenServer.cast(producer, {:add_interrupt, :alert, %{index: i}, [id: "race-test-#{i}"]})
          end)
        end

      Enum.each(tasks, &Task.await/1)
      Process.sleep(20)

      state = GenServer.call(producer, :get_state)
      # All interrupts should be added successfully with unique IDs
      assert Enum.count(state.interrupt_stack) == 10
      # All should have unique IDs
      ids = Enum.map(state.interrupt_stack, & &1.id)
      assert Enum.count(Enum.uniq(ids)) == 10
    end

    test "expired interrupts are cleaned up", %{producer: producer} do
      # Add interrupt with very short duration
      GenServer.cast(producer, {:add_interrupt, :alert, %{}, [duration: 1]})

      state = GenServer.call(producer, :get_state)
      assert Enum.count(state.interrupt_stack) == 1

      # Wait for expiration
      Process.sleep(50)

      state = GenServer.call(producer, :get_state)
      assert Enum.empty?(state.interrupt_stack)
    end
  end

  describe "memory management" do
    test "enforces interrupt stack size limits", %{producer: producer} do
      # Add more interrupts than the configured limit
      max_size =
        Application.get_env(:server, :cleanup_settings, %{})
        |> Map.get(:max_interrupt_stack_size, 50)

      for i <- 1..(max_size + 10)//1 do
        GenServer.cast(producer, {:add_interrupt, :alert, %{id: i}, [id: "alert-#{i}"]})
      end

      # Trigger cleanup
      send(producer, :cleanup)
      Process.sleep(10)

      state = GenServer.call(producer, :get_state)

      keep_count =
        Application.get_env(:server, :cleanup_settings, %{})
        |> Map.get(:interrupt_stack_keep_count, 25)

      assert Enum.count(state.interrupt_stack) <= keep_count
    end

    test "cleanup removes stale timers", %{producer: producer} do
      # Add some interrupts
      GenServer.cast(producer, {:add_interrupt, :alert, %{}, [id: "test1"]})
      GenServer.cast(producer, {:add_interrupt, :alert, %{}, [id: "test2"]})

      state = GenServer.call(producer, :get_state)
      initial_timer_count = map_size(state.timers)

      # Manually remove from interrupt stack (simulating stale timer)
      new_state = %{state | interrupt_stack: []}
      :sys.replace_state(producer, fn _ -> new_state end)

      # Trigger cleanup
      send(producer, :cleanup)
      Process.sleep(10)

      final_state = GenServer.call(producer, :get_state)
      assert map_size(final_state.timers) < initial_timer_count
    end
  end

  describe "configuration" do
    test "uses configured cleanup values" do
      config = Application.get_env(:server, :cleanup_settings, %{})

      assert is_integer(Map.get(config, :max_interrupt_stack_size, 50))
      assert is_integer(Map.get(config, :interrupt_stack_keep_count, 25))
    end

    test "uses configured timing values" do
      assert is_integer(Application.get_env(:server, :ticker_interval, 15_000))
      assert is_integer(Application.get_env(:server, :sub_train_duration, 300_000))
      assert is_integer(Application.get_env(:server, :cleanup_interval, 600_000))
    end
  end

  describe "error handling" do
    test "handles malformed events gracefully", %{producer: producer} do
      # Send malformed subscription event (missing required fields)
      send(producer, {:new_subscription, %{invalid: "data"}})

      # Should not crash and should handle gracefully with defaults
      Process.sleep(10)
      assert Process.alive?(producer)

      state = GenServer.call(producer, :get_state)
      # Should have created sub train with default values
      assert Enum.count(state.interrupt_stack) == 1

      sub_train = List.first(state.interrupt_stack)
      assert sub_train.type == :sub_train
      assert sub_train.data.subscriber == "unknown"
      assert sub_train.data.tier == "1000"
    end

    test "recovers from service call failures", %{producer: producer} do
      # Test that ticker content generation handles failures
      send(producer, :ticker_tick)

      Process.sleep(10)
      assert Process.alive?(producer)

      state = GenServer.call(producer, :get_state)
      assert state.active_content != nil
    end

    test "handles canonical chat messages without crashing", %{producer: producer} do
      # Test that StreamProducer processes canonical chat message events
      chat_event = %{
        # Core fields (always present)
        id: "msg_123",
        type: "channel.chat.message",
        timestamp: DateTime.utc_now(),
        correlation_id: "test_correlation_id",
        source: :twitch,
        source_id: "msg_123",
        raw_type: "channel.chat.message",

        # Chat-specific fields (flat structure)
        user_name: "test_user",
        message: "Hello world!",
        emotes: [],
        native_emotes: [],
        user_id: "user_123",
        user_login: "test_user",
        message_id: "msg_123"
      }

      # Send the canonical chat message
      send(producer, {:chat_message, chat_event})

      # Give time for async processing
      Process.sleep(50)
      assert Process.alive?(producer)

      # Verify producer didn't crash
      state = GenServer.call(producer, :get_state)
      assert is_map(state)
    end

    test "handles chat messages with emotes from canonical events", %{producer: producer} do
      # Test chat message with emotes using canonical event format
      chat_event = %{
        # Core fields (always present)
        id: "msg_456",
        type: "channel.chat.message",
        timestamp: DateTime.utc_now(),
        correlation_id: "test_correlation_id",
        source: :twitch,
        source_id: "msg_456",
        raw_type: "channel.chat.message",

        # Chat-specific fields (flat structure)
        user_name: "test_user",
        message: "Hello world!",
        emotes: [%{name: "Kappa", count: 2}],
        native_emotes: [],
        user_id: "user_456",
        user_login: "test_user",
        message_id: "msg_456"
      }

      # Send the canonical chat message
      send(producer, {:chat_message, chat_event})

      # Give time for async processing
      Process.sleep(50)
      assert Process.alive?(producer)

      # Verify producer handled the event correctly without crashing
      state = GenServer.call(producer, :get_state)
      assert is_map(state)
    end
  end
end
