defmodule Server.Domains.EventSourcingTest do
  @moduledoc """
  TDD tests for pure event sourcing domain logic.

  These tests drive the implementation of pure functions for event handling,
  state projection, and event stream processing.
  """

  use ExUnit.Case, async: true

  alias Server.Domains.EventSourcing

  describe "apply_event/2" do
    test "applies initial stream_online event to empty state" do
      event = %{
        type: :stream_online,
        timestamp: "2024-01-01T00:00:01Z",
        data: %{title: "Stream Title", game: "Programming"}
      }

      state = EventSourcing.apply_event(%{}, event)

      assert state.status == :online
      assert state.title == "Stream Title"
      assert state.game == "Programming"
      assert state.started_at == "2024-01-01T00:00:01Z"
    end

    test "applies stream_offline event to online state" do
      initial_state = %{
        status: :online,
        title: "Stream Title",
        game: "Programming",
        started_at: "2024-01-01T00:00:01Z"
      }

      event = %{
        type: :stream_offline,
        timestamp: "2024-01-01T02:00:00Z",
        data: %{}
      }

      state = EventSourcing.apply_event(initial_state, event)

      assert state.status == :offline
      assert state.ended_at == "2024-01-01T02:00:00Z"
      # Previous fields should be preserved
      assert state.title == "Stream Title"
      assert state.game == "Programming"
    end

    test "applies alert_created event to state" do
      initial_state = %{status: :online}

      event = %{
        type: :alert_created,
        timestamp: "2024-01-01T00:00:01Z",
        data: %{
          alert_type: :sub_train,
          priority: 50,
          message: "5 new subs!"
        }
      }

      state = EventSourcing.apply_event(initial_state, event)

      assert Map.has_key?(state, :alerts)
      assert length(state.alerts) == 1

      alert = List.first(state.alerts)
      assert alert.type == :sub_train
      assert alert.priority == 50
      assert alert.message == "5 new subs!"
    end

    test "applies alert_dismissed event to state with existing alerts" do
      initial_state = %{
        status: :online,
        alerts: [
          %{id: "alert-1", type: :alert, priority: 100},
          %{id: "alert-2", type: :sub_train, priority: 50}
        ]
      }

      event = %{
        type: :alert_dismissed,
        timestamp: "2024-01-01T00:00:01Z",
        data: %{alert_id: "alert-1"}
      }

      state = EventSourcing.apply_event(initial_state, event)

      assert length(state.alerts) == 1
      remaining_alert = List.first(state.alerts)
      assert remaining_alert.id == "alert-2"
    end

    test "ignores unknown event types" do
      initial_state = %{status: :online}

      event = %{
        type: :unknown_event,
        timestamp: "2024-01-01T00:00:01Z",
        data: %{some: "data"}
      }

      state = EventSourcing.apply_event(initial_state, event)

      # State should remain unchanged
      assert state == initial_state
    end
  end

  describe "project_from_events/2" do
    test "projects empty state from empty event list" do
      events = []
      initial_state = %{}

      final_state = EventSourcing.project_from_events(events, initial_state)

      assert final_state == %{}
    end

    test "projects final state from sequence of events" do
      events = [
        %{
          type: :stream_online,
          timestamp: "2024-01-01T00:00:01Z",
          data: %{title: "Test Stream", game: "Programming"}
        },
        %{
          type: :alert_created,
          timestamp: "2024-01-01T00:00:02Z",
          data: %{alert_type: :alert, priority: 100, message: "Breaking news!"}
        },
        %{
          type: :alert_created,
          timestamp: "2024-01-01T00:00:03Z",
          data: %{alert_type: :sub_train, priority: 50, message: "Sub train!"}
        }
      ]

      final_state = EventSourcing.project_from_events(events, %{})

      assert final_state.status == :online
      assert final_state.title == "Test Stream"
      assert final_state.game == "Programming"
      assert length(final_state.alerts) == 2
    end

    test "handles events with dependencies correctly" do
      events = [
        %{
          type: :alert_created,
          timestamp: "2024-01-01T00:00:01Z",
          data: %{alert_type: :alert, priority: 100, message: "First alert", id: "alert-1"}
        },
        %{
          type: :alert_created,
          timestamp: "2024-01-01T00:00:02Z",
          data: %{alert_type: :sub_train, priority: 50, message: "Second alert", id: "alert-2"}
        },
        %{
          type: :alert_dismissed,
          timestamp: "2024-01-01T00:00:03Z",
          data: %{alert_id: "alert-1"}
        }
      ]

      final_state = EventSourcing.project_from_events(events, %{})

      assert length(final_state.alerts) == 1
      remaining_alert = List.first(final_state.alerts)
      assert remaining_alert.id == "alert-2"
    end
  end

  describe "validate_event/1" do
    test "validates valid event structure" do
      event = %{
        type: :stream_online,
        timestamp: "2024-01-01T00:00:01Z",
        data: %{title: "Stream Title"}
      }

      assert EventSourcing.validate_event(event) == :ok
    end

    test "rejects event without required type field" do
      event = %{
        timestamp: "2024-01-01T00:00:01Z",
        data: %{}
      }

      assert EventSourcing.validate_event(event) == {:error, :missing_type}
    end

    test "rejects event without required timestamp field" do
      event = %{
        type: :stream_online,
        data: %{}
      }

      assert EventSourcing.validate_event(event) == {:error, :missing_timestamp}
    end

    test "rejects event without required data field" do
      event = %{
        type: :stream_online,
        timestamp: "2024-01-01T00:00:01Z"
      }

      assert EventSourcing.validate_event(event) == {:error, :missing_data}
    end

    test "rejects event with invalid timestamp format" do
      event = %{
        type: :stream_online,
        timestamp: "invalid-timestamp",
        data: %{}
      }

      assert EventSourcing.validate_event(event) == {:error, :invalid_timestamp}
    end

    test "rejects event with non-map data" do
      event = %{
        type: :stream_online,
        timestamp: "2024-01-01T00:00:01Z",
        data: "not a map"
      }

      assert EventSourcing.validate_event(event) == {:error, :invalid_data}
    end
  end

  describe "get_events_since/2" do
    test "returns all events when since_timestamp is nil" do
      events = [
        %{timestamp: "2024-01-01T00:00:01Z", type: :stream_online},
        %{timestamp: "2024-01-01T00:00:02Z", type: :alert_created},
        %{timestamp: "2024-01-01T00:00:03Z", type: :stream_offline}
      ]

      result = EventSourcing.get_events_since(events, nil)

      assert length(result) == 3
      assert result == events
    end

    test "returns events after given timestamp" do
      events = [
        %{timestamp: "2024-01-01T00:00:01Z", type: :stream_online},
        %{timestamp: "2024-01-01T00:00:02Z", type: :alert_created},
        %{timestamp: "2024-01-01T00:00:03Z", type: :stream_offline}
      ]

      result = EventSourcing.get_events_since(events, "2024-01-01T00:00:01Z")

      assert length(result) == 2
      assert Enum.map(result, & &1.type) == [:alert_created, :stream_offline]
    end

    test "returns empty list when no events after timestamp" do
      events = [
        %{timestamp: "2024-01-01T00:00:01Z", type: :stream_online},
        %{timestamp: "2024-01-01T00:00:02Z", type: :alert_created}
      ]

      result = EventSourcing.get_events_since(events, "2024-01-01T00:00:03Z")

      assert result == []
    end

    test "handles empty event list" do
      result = EventSourcing.get_events_since([], "2024-01-01T00:00:01Z")

      assert result == []
    end
  end
end
