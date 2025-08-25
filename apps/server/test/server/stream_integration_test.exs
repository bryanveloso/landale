defmodule Server.StreamIntegrationTest do
  @moduledoc """
  Tests the integration between stream system and unified events system.
  Validates that stream events flow through the unified architecture correctly.
  """

  use Server.DataCase, async: true
  import Phoenix.PubSub

  describe "stream system unified events integration" do
    test "stream events are published to unified events topic" do
      # Subscribe to the unified events topic
      subscribe(Server.PubSub, "events")

      # Process a stream event through Server.Events
      :ok =
        Server.Events.process_event("stream.state_updated", %{
          current_show: "variety",
          current: %{type: "emote_stats"},
          alerts: [],
          ticker: ["emote_stats", "recent_follows"],
          version: 1,
          metadata: %{last_updated: "2025-08-15T10:00:00Z", state_version: 1}
        })

      # Verify the event is published to unified topic
      assert_receive {:event, normalized_event}, 500
      assert normalized_event.type == "stream.state_updated"
      assert normalized_event.source == :stream
      assert Map.get(normalized_event, :current_show) == "variety"
      assert Map.get(normalized_event, :version) == 1
    end

    test "stream show change events are properly normalized" do
      # Subscribe to the unified events topic
      subscribe(Server.PubSub, "events")

      # Process a show change event
      :ok =
        Server.Events.process_event("stream.show_changed", %{
          show: "ironmon",
          game_id: "490100",
          game_name: "Pokemon FireRed/LeafGreen",
          title: "IronMON Challenge",
          changed_at: "2025-08-15T10:00:00Z"
        })

      # Verify the event is published and normalized correctly
      assert_receive {:event, normalized_event}, 500
      assert normalized_event.type == "stream.show_changed"
      assert normalized_event.source == :stream
      assert Map.get(normalized_event, :show) == "ironmon"
      assert Map.get(normalized_event, :game_id) == "490100"
      assert Map.get(normalized_event, :game_name) == "Pokemon FireRed/LeafGreen"
      assert Map.get(normalized_event, :title) == "IronMON Challenge"
      assert %DateTime{} = Map.get(normalized_event, :changed_at)
    end

    test "stream takeover events work through unified system" do
      # Subscribe to the unified events topic
      subscribe(Server.PubSub, "events")

      # Process a takeover started event
      :ok =
        Server.Events.process_event("stream.takeover_started", %{
          takeover_type: "alert",
          message: "Test Alert",
          duration: 5000,
          timestamp: "2025-08-15T10:00:00Z"
        })

      # Verify the event is published correctly
      assert_receive {:event, normalized_event}, 500
      assert normalized_event.type == "stream.takeover_started"
      assert normalized_event.source == :stream
      assert Map.get(normalized_event, :takeover_type) == "alert"
      assert Map.get(normalized_event, :message) == "Test Alert"
      assert Map.get(normalized_event, :duration) == 5000
      assert %DateTime{} = Map.get(normalized_event, :takeover_timestamp)
    end

    test "stream goals update events are properly formatted" do
      # Subscribe to the unified events topic
      subscribe(Server.PubSub, "events")

      # Process a goals update event
      :ok =
        Server.Events.process_event("stream.goals_updated", %{
          follower_goal: %{current: 50, target: 100},
          sub_goal: %{current: 5, target: 10},
          new_sub_goal: %{current: 2, target: 5},
          timestamp: "2025-08-15T10:00:00Z"
        })

      # Verify the event is published correctly
      assert_receive {:event, normalized_event}, 500
      assert normalized_event.type == "stream.goals_updated"
      assert normalized_event.source == :stream
      assert Map.get(normalized_event, :follower_goal) == %{current: 50, target: 100}
      assert Map.get(normalized_event, :sub_goal) == %{current: 5, target: 10}
      assert Map.get(normalized_event, :new_sub_goal) == %{current: 2, target: 5}
      assert %DateTime{} = Map.get(normalized_event, :goals_timestamp)
    end

    test "stream emote increment events preserve emote data" do
      # Subscribe to the unified events topic
      subscribe(Server.PubSub, "events")

      # Process an emote increment event
      :ok =
        Server.Events.process_event("stream.emote_increment", %{
          emotes: ["Kappa", "PogChamp"],
          native_emotes: ["avalonPog", "avalonKappa"],
          user_name: "testuser",
          timestamp: "2025-08-15T10:00:00Z"
        })

      # Verify the event is published correctly
      assert_receive {:event, normalized_event}, 500
      assert normalized_event.type == "stream.emote_increment"
      assert normalized_event.source == :stream
      assert Map.get(normalized_event, :emotes) == ["Kappa", "PogChamp"]
      assert Map.get(normalized_event, :native_emotes) == ["avalonPog", "avalonKappa"]
      assert Map.get(normalized_event, :user_name) == "testuser"
      assert %DateTime{} = Map.get(normalized_event, :increment_timestamp)
    end
  end
end
