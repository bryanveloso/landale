defmodule Server.StreamProducerTest do
  use ExUnit.Case, async: false

  alias Server.StreamProducer
  alias Server.Domains.StreamState

  @moduletag :unit

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

  describe "domain logic integration" do
    test "uses StreamState domain for state transitions", %{producer: producer} do
      # Test that the GenServer uses pure domain logic correctly
      GenServer.cast(producer, {:change_show, :ironmon, %{}})

      state = GenServer.call(producer, :get_state)

      # Verify the state change followed domain rules
      expected_ticker = StreamState.get_ticker_rotation_for_show(:ironmon)
      assert state.ticker_rotation == expected_ticker
      assert state.current_show == :ironmon
    end

    test "interrupt prioritization follows domain rules", %{producer: producer} do
      # Add interrupts that should be sorted by domain logic
      GenServer.cast(producer, {:add_interrupt, :sub_train, %{count: 1}, []})
      GenServer.cast(producer, {:add_interrupt, :alert, %{message: "Breaking"}, []})

      state = GenServer.call(producer, :get_state)

      # Verify domain logic was applied (alerts should win over sub trains)
      assert state.active_content.type == :alert
      assert state.active_content.priority == 100
    end
  end
end
