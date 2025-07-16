defmodule Server.Domains.StreamStateTest do
  @moduledoc """
  TDD tests for pure stream state domain logic.

  These tests drive the implementation of pure functions for stream state management.
  """

  use ExUnit.Case, async: true

  # This test module tests pure functions - no database needed
  # Skip all application setup since we're testing the functional core

  alias Server.Domains.StreamState

  describe "determine_active_content/2" do
    test "returns highest priority interrupt when available" do
      interrupt_stack = [
        %{type: :sub_train, priority: 50, data: %{count: 3}},
        %{type: :alert, priority: 100, data: %{message: "Breaking"}},
        %{type: :alert, priority: 100, data: %{message: "Latest"}}
      ]

      ticker_rotation = [:emote_stats, :recent_follows]

      active_content = StreamState.determine_active_content(interrupt_stack, ticker_rotation)

      # Should pick first alert (highest priority, first in list)
      assert active_content.type == :alert
      assert active_content.priority == 100
      assert active_content.data.message == "Breaking"
    end

    test "falls back to ticker content when no interrupts" do
      interrupt_stack = []
      ticker_rotation = [:emote_stats, :recent_follows, :stream_goals]

      active_content = StreamState.determine_active_content(interrupt_stack, ticker_rotation)

      # Should return first ticker item
      assert active_content.type == :emote_stats
      assert active_content.priority == 10
    end

    test "returns nil when no interrupts and empty ticker rotation" do
      interrupt_stack = []
      ticker_rotation = []

      active_content = StreamState.determine_active_content(interrupt_stack, ticker_rotation)

      assert active_content == nil
    end

    test "prioritizes by priority value descending, then by position" do
      interrupt_stack = [
        %{type: :sub_train, priority: 50, data: %{count: 1}},
        %{type: :alert, priority: 100, data: %{message: "First alert"}},
        %{type: :sub_train, priority: 50, data: %{count: 2}},
        %{type: :alert, priority: 100, data: %{message: "Second alert"}}
      ]

      ticker_rotation = [:emote_stats]

      active_content = StreamState.determine_active_content(interrupt_stack, ticker_rotation)

      # Should pick first alert (highest priority, first among alerts)
      assert active_content.type == :alert
      assert active_content.data.message == "First alert"
    end
  end

  describe "add_interrupt/3" do
    test "adds interrupt with correct priority and maintains sort order" do
      state = %{
        interrupt_stack: [
          %{id: "existing", type: :sub_train, priority: 50, data: %{count: 1}, started_at: "2024-01-01T00:00:00Z"}
        ],
        version: 0,
        last_updated: "2024-01-01T00:00:00Z"
      }

      interrupt_data = %{message: "New alert"}
      options = [id: "new-alert"]

      new_state = StreamState.add_interrupt(state, :alert, interrupt_data, options)

      assert length(new_state.interrupt_stack) == 2

      # New alert should be first (higher priority)
      [first, second] = new_state.interrupt_stack
      assert first.id == "new-alert"
      assert first.type == :alert
      assert first.priority == 100
      assert first.data.message == "New alert"

      assert second.id == "existing"
      assert second.type == :sub_train
    end

    test "generates unique ID when not provided" do
      state = %{interrupt_stack: [], version: 0, last_updated: "2024-01-01T00:00:00Z"}
      interrupt_data = %{message: "Test"}

      new_state = StreamState.add_interrupt(state, :alert, interrupt_data, [])

      assert length(new_state.interrupt_stack) == 1
      interrupt = List.first(new_state.interrupt_stack)
      assert is_binary(interrupt.id)
      assert String.length(interrupt.id) > 0
    end

    test "respects custom duration option" do
      state = %{interrupt_stack: [], version: 0, last_updated: "2024-01-01T00:00:00Z"}
      interrupt_data = %{message: "Test"}
      options = [duration: 5000]

      new_state = StreamState.add_interrupt(state, :alert, interrupt_data, options)

      interrupt = List.first(new_state.interrupt_stack)
      assert interrupt.duration == 5000
    end

    test "uses default duration for interrupt type when not specified" do
      state = %{interrupt_stack: [], version: 0, last_updated: "2024-01-01T00:00:00Z"}
      interrupt_data = %{message: "Test"}

      new_state = StreamState.add_interrupt(state, :alert, interrupt_data, [])

      interrupt = List.first(new_state.interrupt_stack)
      # Alert default duration should be set
      assert interrupt.duration == 10_000
    end

    test "includes started_at timestamp" do
      state = %{interrupt_stack: [], version: 0, last_updated: "2024-01-01T00:00:00Z"}
      interrupt_data = %{message: "Test"}

      before_time = DateTime.utc_now()
      new_state = StreamState.add_interrupt(state, :alert, interrupt_data, [])
      after_time = DateTime.utc_now()

      interrupt = List.first(new_state.interrupt_stack)
      assert is_binary(interrupt.started_at)

      {:ok, started_at, _} = DateTime.from_iso8601(interrupt.started_at)
      assert DateTime.compare(started_at, before_time) in [:eq, :gt]
      assert DateTime.compare(started_at, after_time) in [:eq, :lt]
    end
  end

  describe "update_show_context/2" do
    test "updates show and adjusts ticker rotation for ironmon" do
      state = %{
        current_show: :variety,
        ticker_rotation: [:emote_stats, :recent_follows, :stream_goals],
        version: 0,
        last_updated: "2024-01-01T00:00:00Z"
      }

      new_state = StreamState.update_show_context(state, :ironmon)

      assert new_state.current_show == :ironmon
      # IronMON should have different ticker content
      assert :ironmon_run_stats in new_state.ticker_rotation
      assert :recent_follows in new_state.ticker_rotation
      refute :stream_goals in new_state.ticker_rotation
    end

    test "updates show and adjusts ticker rotation for coding" do
      state = %{
        current_show: :variety,
        ticker_rotation: [:emote_stats, :recent_follows, :stream_goals],
        version: 0,
        last_updated: "2024-01-01T00:00:00Z"
      }

      new_state = StreamState.update_show_context(state, :coding)

      assert new_state.current_show == :coding
      # Coding should have build-related content
      assert :build_status in new_state.ticker_rotation
      assert :commit_stats in new_state.ticker_rotation
      assert :recent_follows in new_state.ticker_rotation
    end

    test "increments version number" do
      state = %{
        current_show: :variety,
        ticker_rotation: [:emote_stats],
        version: 5,
        last_updated: "2024-01-01T00:00:00Z"
      }

      new_state = StreamState.update_show_context(state, :ironmon)

      assert new_state.version == 6
    end

    test "updates last_updated timestamp" do
      state = %{
        current_show: :variety,
        ticker_rotation: [:emote_stats],
        version: 0,
        last_updated: "2024-01-01T00:00:00Z"
      }

      new_state = StreamState.update_show_context(state, :ironmon)

      assert new_state.last_updated != "2024-01-01T00:00:00Z"
      # Should be valid ISO8601 timestamp
      assert {:ok, _, _} = DateTime.from_iso8601(new_state.last_updated)
    end
  end

  describe "expire_content/2" do
    test "removes expired interrupts from stack" do
      # One hour ago
      past_time = DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.to_iso8601()
      # One hour from now
      future_time = DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.to_iso8601()

      state = %{
        interrupt_stack: [
          %{id: "expired", type: :alert, duration: 1000, started_at: past_time},
          %{id: "active", type: :sub_train, duration: 7_200_000, started_at: future_time}
        ],
        version: 0,
        last_updated: "2024-01-01T00:00:00Z"
      }

      current_time = DateTime.utc_now()
      new_state = StreamState.expire_content(state, current_time)

      # Should only keep the non-expired interrupt
      assert length(new_state.interrupt_stack) == 1
      remaining = List.first(new_state.interrupt_stack)
      assert remaining.id == "active"
    end

    test "keeps all content when nothing is expired" do
      future_time = DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.to_iso8601()

      state = %{
        interrupt_stack: [
          %{id: "1", type: :alert, duration: 7_200_000, started_at: future_time},
          %{id: "2", type: :sub_train, duration: 7_200_000, started_at: future_time}
        ],
        version: 0,
        last_updated: "2024-01-01T00:00:00Z"
      }

      current_time = DateTime.utc_now()
      new_state = StreamState.expire_content(state, current_time)

      # Should keep all interrupts
      assert length(new_state.interrupt_stack) == 2
    end

    test "removes all content when everything is expired" do
      past_time = DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.to_iso8601()

      state = %{
        interrupt_stack: [
          %{id: "1", type: :alert, duration: 1000, started_at: past_time},
          %{id: "2", type: :sub_train, duration: 1000, started_at: past_time}
        ],
        version: 0,
        last_updated: "2024-01-01T00:00:00Z"
      }

      current_time = DateTime.utc_now()
      new_state = StreamState.expire_content(state, current_time)

      # Should remove all expired interrupts
      assert new_state.interrupt_stack == []
    end

    test "increments version when changes are made" do
      past_time = DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.to_iso8601()

      state = %{
        interrupt_stack: [
          %{id: "expired", type: :alert, duration: 1000, started_at: past_time}
        ],
        version: 10,
        last_updated: "2024-01-01T00:00:00Z"
      }

      current_time = DateTime.utc_now()
      new_state = StreamState.expire_content(state, current_time)

      assert new_state.version == 11
    end

    test "does not change version when no content expires" do
      future_time = DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.to_iso8601()

      state = %{
        interrupt_stack: [
          %{id: "active", type: :alert, duration: 7_200_000, started_at: future_time}
        ],
        version: 10,
        last_updated: "2024-01-01T00:00:00Z"
      }

      current_time = DateTime.utc_now()
      new_state = StreamState.expire_content(state, current_time)

      assert new_state.version == 10
    end
  end

  describe "remove_interrupt/2" do
    test "removes interrupt by id and maintains order" do
      state = %{
        interrupt_stack: [
          %{id: "keep-1", type: :alert, priority: 100},
          %{id: "remove", type: :sub_train, priority: 50},
          %{id: "keep-2", type: :alert, priority: 100}
        ],
        version: 0,
        last_updated: "2024-01-01T00:00:00Z"
      }

      new_state = StreamState.remove_interrupt(state, "remove")

      assert length(new_state.interrupt_stack) == 2
      ids = Enum.map(new_state.interrupt_stack, & &1.id)
      assert ids == ["keep-1", "keep-2"]
    end

    test "returns unchanged state when id not found" do
      state = %{
        interrupt_stack: [
          %{id: "existing", type: :alert, priority: 100}
        ],
        version: 5,
        last_updated: "2024-01-01T00:00:00Z"
      }

      new_state = StreamState.remove_interrupt(state, "nonexistent")

      # Should be unchanged
      assert new_state == state
    end

    test "increments version when interrupt is removed" do
      state = %{
        interrupt_stack: [
          %{id: "remove-me", type: :alert, priority: 100}
        ],
        version: 3,
        last_updated: "2024-01-01T00:00:00Z"
      }

      new_state = StreamState.remove_interrupt(state, "remove-me")

      assert new_state.version == 4
      assert new_state.interrupt_stack == []
    end
  end
end
