defmodule Server.Events.EventTest do
  use ExUnit.Case, async: true

  @moduletag :unit

  alias Server.Events.Event

  describe "new/4" do
    test "creates event with all required fields" do
      event = Event.new("test.event", :test, %{foo: "bar"})

      assert event.id =~ ~r/^evt_[a-f0-9]{8}$/
      assert event.type == "test.event"
      assert event.source == :test
      assert event.data == %{foo: "bar"}
      assert %DateTime{} = event.timestamp
      assert event.meta.priority == :normal
      assert %DateTime{} = event.meta.processed_at
      assert is_nil(event.meta.correlation_id)
      assert is_nil(event.meta.batch_id)
    end

    test "accepts custom id in options" do
      custom_id = "custom_123"
      event = Event.new("test.event", :test, %{}, id: custom_id)

      assert event.id == custom_id
    end

    test "accepts custom timestamp in options" do
      custom_time = ~U[2025-01-01 12:00:00Z]
      event = Event.new("test.event", :test, %{}, timestamp: custom_time)

      assert event.timestamp == custom_time
    end

    test "accepts correlation_id in options" do
      correlation_id = "corr_123"
      event = Event.new("test.event", :test, %{}, correlation_id: correlation_id)

      assert event.meta.correlation_id == correlation_id
    end

    test "accepts batch_id in options" do
      batch_id = "batch_456"
      event = Event.new("test.event", :test, %{}, batch_id: batch_id)

      assert event.meta.batch_id == batch_id
    end

    test "accepts critical priority in options" do
      event = Event.new("test.event", :test, %{}, priority: :critical)

      assert event.meta.priority == :critical
    end

    test "supports all source types" do
      sources = [:twitch, :obs, :system, :ironmon, :rainwave, :test]

      for source <- sources do
        event = Event.new("test.event", source, %{})
        assert event.source == source
      end
    end
  end

  describe "from_raw/3" do
    test "converts flat legacy event" do
      raw = %{
        type: "channel.follow",
        user_name: "viewer123",
        user_id: "12345",
        timestamp: 1_691_932_800
      }

      event = Event.from_raw(raw, :twitch)

      assert event.type == "channel.follow"
      assert event.source == :twitch
      assert event.data.user_name == "viewer123"
      assert event.data.user_id == "12345"
      refute Map.has_key?(event.data, :type)
      assert DateTime.to_unix(event.timestamp) == 1_691_932_800
    end

    test "converts nested event with data field" do
      raw = %{
        type: "channel.follow",
        data: %{
          user_name: "viewer123",
          user_id: "12345"
        },
        timestamp: ~U[2025-01-01 12:00:00Z]
      }

      event = Event.from_raw(raw, :twitch)

      assert event.type == "channel.follow"
      assert event.source == :twitch
      assert event.data.user_name == "viewer123"
      assert event.data.user_id == "12345"
      assert event.timestamp == ~U[2025-01-01 12:00:00Z]
    end

    test "handles event without type using opts" do
      raw = %{user_name: "viewer123"}
      event = Event.from_raw(raw, :test, type: "inferred.event")

      assert event.type == "inferred.event"
      assert event.source == :test
      assert event.data.user_name == "viewer123"
    end

    test "handles DateTime timestamp" do
      timestamp = ~U[2025-01-01 15:30:00Z]
      raw = %{type: "test", timestamp: timestamp}
      event = Event.from_raw(raw, :test)

      assert event.timestamp == timestamp
    end

    test "handles unix timestamp" do
      unix_time = 1_691_932_800
      raw = %{type: "test", timestamp: unix_time}
      event = Event.from_raw(raw, :test)

      assert DateTime.to_unix(event.timestamp) == unix_time
    end

    test "uses current time when no timestamp provided" do
      raw = %{type: "test"}
      before_time = DateTime.utc_now()
      event = Event.from_raw(raw, :test)
      after_time = DateTime.utc_now()

      assert DateTime.compare(event.timestamp, before_time) in [:gt, :eq]
      assert DateTime.compare(event.timestamp, after_time) in [:lt, :eq]
    end

    test "preserves options like correlation_id" do
      raw = %{type: "test", user: "test"}
      correlation_id = "corr_123"

      event = Event.from_raw(raw, :test, correlation_id: correlation_id)

      assert event.meta.correlation_id == correlation_id
    end
  end

  describe "critical?/1" do
    test "returns true for critical priority events" do
      event = Event.new("test.event", :test, %{}, priority: :critical)
      assert Event.critical?(event)
    end

    test "returns false for normal priority events" do
      event = Event.new("test.event", :test, %{}, priority: :normal)
      refute Event.critical?(event)
    end

    test "returns false for events without explicit priority" do
      event = Event.new("test.event", :test, %{})
      refute Event.critical?(event)
    end
  end

  describe "create_batch/2" do
    test "creates batch event from list of events" do
      events = [
        Event.new("test.one", :test, %{msg: "first"}),
        Event.new("test.two", :test, %{msg: "second"})
      ]

      batch = Event.create_batch(events)

      assert batch.type == "event.batch"
      assert batch.source == :system
      assert batch.data.events == events
      assert batch.data.count == 2
      assert batch.meta.priority == :normal
      assert batch.id =~ ~r/^evt_[a-f0-9]{8}$/
      assert batch.meta.batch_id =~ ~r/^batch_[a-f0-9]{8}$/
    end

    test "accepts custom batch_id in options" do
      events = [Event.new("test.event", :test, %{})]
      custom_batch_id = "custom_batch_123"

      batch = Event.create_batch(events, batch_id: custom_batch_id)

      assert batch.meta.batch_id == custom_batch_id
    end

    test "creates batch with empty events list" do
      batch = Event.create_batch([])

      assert batch.data.events == []
      assert batch.data.count == 0
    end

    test "preserves original events without modification" do
      original_event = Event.new("test.event", :test, %{important: "data"})
      events = [original_event]

      batch = Event.create_batch(events)

      batched_event = List.first(batch.data.events)
      assert batched_event == original_event
      assert batched_event.data.important == "data"
    end
  end

  describe "event structure validation" do
    test "maintains consistent field types" do
      event = Event.new("test.event", :twitch, %{user: "test"})

      assert is_binary(event.id)
      assert is_binary(event.type)
      assert is_atom(event.source)
      assert %DateTime{} = event.timestamp
      assert is_map(event.data)
      assert is_map(event.meta)
    end

    test "meta structure is consistent" do
      event =
        Event.new("test.event", :test, %{},
          correlation_id: "corr_123",
          batch_id: "batch_456",
          priority: :critical
        )

      assert is_binary(event.meta.correlation_id) or is_nil(event.meta.correlation_id)
      assert is_binary(event.meta.batch_id) or is_nil(event.meta.batch_id)
      assert event.meta.priority in [:critical, :normal]
      assert %DateTime{} = event.meta.processed_at
    end
  end

  describe "edge cases" do
    test "handles nil data gracefully" do
      # This shouldn't happen in practice, but we should handle it
      event = Event.new("test.event", :test, nil)
      assert event.data == nil
    end

    test "handles empty data map" do
      event = Event.new("test.event", :test, %{})
      assert event.data == %{}
    end

    test "handles complex nested data" do
      complex_data = %{
        user: %{
          id: "123",
          profile: %{
            name: "Test User",
            settings: %{theme: "dark", notifications: true}
          }
        },
        metrics: [1, 2, 3, 4, 5],
        tags: ["important", "test"]
      }

      event = Event.new("complex.event", :test, complex_data)
      assert event.data == complex_data
    end
  end

  describe "id generation" do
    test "generates unique IDs" do
      events = for _i <- 1..100, do: Event.new("test.event", :test, %{})
      ids = Enum.map(events, & &1.id)

      assert length(Enum.uniq(ids)) == 100
    end

    test "ID format is consistent" do
      event = Event.new("test.event", :test, %{})
      assert event.id =~ ~r/^evt_[a-f0-9]{8}$/
    end
  end

  describe "timestamp handling" do
    test "timestamp is always DateTime struct" do
      event = Event.new("test.event", :test, %{})
      assert %DateTime{} = event.timestamp
    end

    test "processed_at is always set to current time" do
      before_time = DateTime.utc_now()
      event = Event.new("test.event", :test, %{})
      after_time = DateTime.utc_now()

      assert DateTime.compare(event.meta.processed_at, before_time) in [:gt, :eq]
      assert DateTime.compare(event.meta.processed_at, after_time) in [:lt, :eq]
    end
  end
end
