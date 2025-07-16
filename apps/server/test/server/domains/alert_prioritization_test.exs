defmodule Server.Domains.AlertPrioritizationTest do
  @moduledoc """
  TDD tests for pure alert prioritization domain logic.

  These tests drive the implementation of pure functions for determining
  alert priority, ordering interrupt stacks, and selecting active alerts.
  """

  use ExUnit.Case, async: true

  alias Server.Domains.AlertPrioritization

  describe "get_priority_for_alert_type/1" do
    test "returns high priority for alert type" do
      priority = AlertPrioritization.get_priority_for_alert_type(:alert)
      assert priority == 100
    end

    test "returns medium priority for sub_train alert" do
      priority = AlertPrioritization.get_priority_for_alert_type(:sub_train)
      assert priority == 50
    end

    test "returns low priority for ticker alert" do
      priority = AlertPrioritization.get_priority_for_alert_type(:ticker)
      assert priority == 10
    end

    test "returns medium priority for manual_override alert" do
      priority = AlertPrioritization.get_priority_for_alert_type(:manual_override)
      assert priority == 50
    end

    test "returns low priority for unknown alert types" do
      priority = AlertPrioritization.get_priority_for_alert_type(:unknown_type)
      assert priority == 10
    end
  end

  describe "determine_active_alert/2" do
    test "returns highest priority interrupt when available" do
      interrupt_stack = [
        %{type: :ticker, priority: 10, data: %{}, started_at: "2024-01-01T00:00:01Z"},
        %{type: :alert, priority: 100, data: %{message: "Breaking"}, started_at: "2024-01-01T00:00:02Z"},
        %{type: :sub_train, priority: 50, data: %{count: 3}, started_at: "2024-01-01T00:00:03Z"}
      ]

      ticker_rotation = [:emote_stats, :recent_follows]

      active_alert = AlertPrioritization.determine_active_alert(interrupt_stack, ticker_rotation)

      assert active_alert.type == :alert
      assert active_alert.priority == 100
    end

    test "returns FIFO for same priority interrupts" do
      interrupt_stack = [
        %{type: :alert, priority: 100, data: %{message: "Second"}, started_at: "2024-01-01T00:00:02Z"},
        %{type: :alert, priority: 100, data: %{message: "First"}, started_at: "2024-01-01T00:00:01Z"}
      ]

      ticker_rotation = [:emote_stats]

      active_alert = AlertPrioritization.determine_active_alert(interrupt_stack, ticker_rotation)

      assert active_alert.type == :alert
      assert active_alert.data.message == "First"
    end

    test "falls back to ticker alert when no interrupts" do
      interrupt_stack = []
      ticker_rotation = [:emote_stats, :recent_follows]

      active_alert = AlertPrioritization.determine_active_alert(interrupt_stack, ticker_rotation)

      assert active_alert.type == :emote_stats
      assert active_alert.priority == 10
    end

    test "returns nil when no interrupts and empty ticker rotation" do
      interrupt_stack = []
      ticker_rotation = []

      active_alert = AlertPrioritization.determine_active_alert(interrupt_stack, ticker_rotation)

      assert active_alert == nil
    end

    test "ignores empty interrupt stack entries" do
      interrupt_stack = [nil, %{type: :sub_train, priority: 50, data: %{}, started_at: "2024-01-01T00:00:01Z"}]
      ticker_rotation = [:emote_stats]

      active_alert = AlertPrioritization.determine_active_alert(interrupt_stack, ticker_rotation)

      assert active_alert.type == :sub_train
      assert active_alert.priority == 50
    end
  end

  describe "sort_alerts_by_priority/1" do
    test "sorts alerts by priority descending" do
      alert_list = [
        %{type: :ticker, priority: 10, started_at: "2024-01-01T00:00:01Z"},
        %{type: :alert, priority: 100, started_at: "2024-01-01T00:00:02Z"},
        %{type: :sub_train, priority: 50, started_at: "2024-01-01T00:00:03Z"}
      ]

      sorted = AlertPrioritization.sort_alerts_by_priority(alert_list)

      priorities = Enum.map(sorted, & &1.priority)
      assert priorities == [100, 50, 10]
    end

    test "uses FIFO ordering for same priority items" do
      alert_list = [
        %{type: :alert, priority: 100, data: %{message: "Third"}, started_at: "2024-01-01T00:00:03Z"},
        %{type: :alert, priority: 100, data: %{message: "First"}, started_at: "2024-01-01T00:00:01Z"},
        %{type: :alert, priority: 100, data: %{message: "Second"}, started_at: "2024-01-01T00:00:02Z"}
      ]

      sorted = AlertPrioritization.sort_alerts_by_priority(alert_list)

      messages = Enum.map(sorted, & &1.data.message)
      assert messages == ["First", "Second", "Third"]
    end

    test "handles alerts without started_at timestamp" do
      alert_list = [
        %{type: :alert, priority: 100, data: %{}},
        %{type: :sub_train, priority: 50, started_at: "2024-01-01T00:00:01Z"}
      ]

      sorted = AlertPrioritization.sort_alerts_by_priority(alert_list)

      # Should not crash and should prioritize by priority
      assert length(sorted) == 2
      assert List.first(sorted).priority == 100
    end

    test "handles empty alert list" do
      sorted = AlertPrioritization.sort_alerts_by_priority([])
      assert sorted == []
    end
  end

  describe "create_alert/3" do
    test "creates alert with correct priority for alert type" do
      alert = AlertPrioritization.create_alert(:alert, %{message: "Test"}, [])

      assert alert.type == :alert
      assert alert.priority == 100
      assert alert.data.message == "Test"
      assert is_binary(alert.id)
      assert is_binary(alert.started_at)
    end

    test "accepts custom ID option" do
      alert = AlertPrioritization.create_alert(:sub_train, %{}, id: "custom-123")

      assert alert.id == "custom-123"
    end

    test "accepts custom duration option" do
      alert = AlertPrioritization.create_alert(:alert, %{}, duration: 5000)

      assert alert.duration == 5000
    end

    test "generates unique IDs when not provided" do
      alert1 = AlertPrioritization.create_alert(:alert, %{}, [])
      alert2 = AlertPrioritization.create_alert(:alert, %{}, [])

      assert alert1.id != alert2.id
    end

    test "includes all required fields" do
      alert = AlertPrioritization.create_alert(:manual_override, %{action: "test"}, [])

      assert Map.has_key?(alert, :id)
      assert Map.has_key?(alert, :type)
      assert Map.has_key?(alert, :priority)
      assert Map.has_key?(alert, :data)
      assert Map.has_key?(alert, :duration)
      assert Map.has_key?(alert, :started_at)
    end
  end

  describe "get_priority_level/1" do
    test "returns alert level when high priority alerts present in stack" do
      interrupt_stack = [
        %{type: :emote_stats, priority: 10},
        %{type: :alert, priority: 100},
        %{type: :sub_train, priority: 50}
      ]

      level = AlertPrioritization.get_priority_level(interrupt_stack)
      assert level == :alert
    end

    test "returns sub_train level when sub trains present but no high priority alerts" do
      interrupt_stack = [
        %{type: :emote_stats, priority: 10},
        %{type: :sub_train, priority: 50}
      ]

      level = AlertPrioritization.get_priority_level(interrupt_stack)
      assert level == :sub_train
    end

    test "returns ticker level when only low priority alerts" do
      interrupt_stack = [
        %{type: :emote_stats, priority: 10},
        %{type: :recent_follows, priority: 10}
      ]

      level = AlertPrioritization.get_priority_level(interrupt_stack)
      assert level == :ticker
    end

    test "returns ticker level for empty interrupt stack" do
      level = AlertPrioritization.get_priority_level([])
      assert level == :ticker
    end
  end
end
