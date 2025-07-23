defmodule Server.Services.OBS.SceneManagerTest do
  @moduledoc """
  Unit tests for the OBS SceneManager GenServer.

  Tests scene state management including:
  - GenServer initialization with ETS table
  - Scene list management
  - Current scene tracking
  - Preview scene tracking  
  - Studio mode state
  - ETS cache operations
  - PubSub event handling and broadcasting
  """
  use ExUnit.Case, async: true

  alias Server.Services.OBS.SceneManager

  def test_session_id, do: "test_scene_manager_#{:rand.uniform(100_000)}_#{System.unique_integer([:positive])}"

  setup do
    # Start PubSub if not already started
    case start_supervised({Phoenix.PubSub, name: Server.PubSub}) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end
  end

  describe "start_link/1 and initialization" do
    test "starts GenServer with session_id and creates ETS table" do
      session_id = test_session_id()
      opts = [session_id: session_id, name: :"scene_manager_#{session_id}"]

      assert {:ok, pid} = SceneManager.start_link(opts)
      assert Process.alive?(pid)

      # Verify state initialization
      state = SceneManager.get_state(pid)

      assert %SceneManager{
               session_id: ^session_id,
               current_scene: nil,
               preview_scene: nil,
               scene_list: [],
               studio_mode_enabled: false,
               ets_table: table
             } = state

      # Verify ETS table was created
      assert is_atom(table) or is_reference(table)
      table_name = :"obs_scenes_#{session_id}"
      assert :ets.info(table_name) != :undefined

      # Clean up
      GenServer.stop(pid)
    end

    test "requires session_id in options" do
      Process.flag(:trap_exit, true)
      opts = [name: :test_no_session]

      assert {:error, _} = SceneManager.start_link(opts)
    end

    test "subscribes to PubSub topic on init" do
      session_id = test_session_id()
      opts = [session_id: session_id, name: :"scene_pubsub_#{session_id}"]
      {:ok, pid} = SceneManager.start_link(opts)

      # Send test event to verify subscription
      topic = "obs_events:#{session_id}"
      event = %{eventType: "SceneListChanged", eventData: %{scenes: []}}
      Phoenix.PubSub.broadcast(Server.PubSub, topic, {:obs_event, event})

      Process.sleep(10)

      # Should still be alive
      assert Process.alive?(pid)

      GenServer.stop(pid)
    end
  end

  describe "get_state/1" do
    setup do
      session_id = test_session_id()
      opts = [session_id: session_id, name: :"scene_state_#{:rand.uniform(10000)}"]
      {:ok, pid} = start_supervised({SceneManager, opts})
      {:ok, pid: pid, session_id: session_id}
    end

    test "returns current state", %{pid: pid, session_id: session_id} do
      state = SceneManager.get_state(pid)

      assert %SceneManager{
               session_id: ^session_id,
               current_scene: nil,
               preview_scene: nil,
               scene_list: [],
               studio_mode_enabled: false
             } = state
    end
  end

  describe "handle_info - SceneListChanged" do
    setup do
      session_id = test_session_id()
      opts = [session_id: session_id, name: :"scene_list_#{:rand.uniform(10000)}"]
      {:ok, pid} = start_supervised({SceneManager, opts})
      {:ok, pid: pid, session_id: session_id}
    end

    test "updates scene list in state and ETS", %{pid: pid, session_id: session_id} do
      scenes = [
        %{sceneName: "Scene 1", sceneIndex: 0},
        %{sceneName: "Scene 2", sceneIndex: 1},
        %{sceneName: "Scene 3", sceneIndex: 2}
      ]

      event = %{
        eventType: "SceneListChanged",
        eventData: %{scenes: scenes}
      }

      send(pid, {:obs_event, event})
      Process.sleep(10)

      # Check state was updated
      state = SceneManager.get_state(pid)
      assert state.scene_list == scenes

      # Check ETS was updated
      table_name = :"obs_scenes_#{session_id}"
      assert [{:scenes, ^scenes}] = :ets.lookup(table_name, :scenes)
    end

    test "handles empty scene list", %{pid: pid, session_id: session_id} do
      event = %{
        eventType: "SceneListChanged",
        eventData: %{scenes: []}
      }

      send(pid, {:obs_event, event})
      Process.sleep(10)

      state = SceneManager.get_state(pid)
      assert state.scene_list == []
    end

    test "handles missing scenes field", %{pid: pid, session_id: session_id} do
      event = %{
        eventType: "SceneListChanged",
        eventData: %{}
      }

      send(pid, {:obs_event, event})
      Process.sleep(10)

      state = SceneManager.get_state(pid)
      assert state.scene_list == []
    end
  end

  describe "handle_info - CurrentProgramSceneChanged" do
    setup do
      session_id = test_session_id()
      opts = [session_id: session_id, name: :"scene_current_#{:rand.uniform(10000)}"]
      {:ok, pid} = start_supervised({SceneManager, opts})

      # Subscribe to broadcast topic
      Phoenix.PubSub.subscribe(Server.PubSub, "obs:events")

      {:ok, pid: pid, session_id: session_id}
    end

    test "updates current scene and broadcasts event", %{pid: pid, session_id: session_id} do
      scene_name = "Main Scene"

      event = %{
        eventType: "CurrentProgramSceneChanged",
        eventData: %{sceneName: scene_name}
      }

      send(pid, {:obs_event, event})

      # Should receive broadcast
      assert_receive {:scene_current_changed,
                      %{
                        session_id: ^session_id,
                        scene_name: ^scene_name
                      }},
                     100

      # Check state was updated
      state = SceneManager.get_state(pid)
      assert state.current_scene == scene_name

      # Check ETS was updated
      table_name = :"obs_scenes_#{session_id}"
      assert [{:current_scene, ^scene_name}] = :ets.lookup(table_name, :current_scene)
    end

    test "handles scene change to nil", %{pid: pid, session_id: session_id} do
      event = %{
        eventType: "CurrentProgramSceneChanged",
        eventData: %{sceneName: nil}
      }

      send(pid, {:obs_event, event})
      Process.sleep(10)

      state = SceneManager.get_state(pid)
      assert state.current_scene == nil
    end
  end

  describe "handle_info - CurrentPreviewSceneChanged" do
    setup do
      session_id = test_session_id()
      opts = [session_id: session_id, name: :"scene_preview_#{:rand.uniform(10000)}"]
      {:ok, pid} = start_supervised({SceneManager, opts})
      {:ok, pid: pid, session_id: session_id}
    end

    test "updates preview scene in state and ETS", %{pid: pid, session_id: session_id} do
      scene_name = "Preview Scene"

      event = %{
        eventType: "CurrentPreviewSceneChanged",
        eventData: %{sceneName: scene_name}
      }

      send(pid, {:obs_event, event})
      Process.sleep(10)

      # Check state was updated
      state = SceneManager.get_state(pid)
      assert state.preview_scene == scene_name

      # Check ETS was updated
      table_name = :"obs_scenes_#{session_id}"
      assert [{:preview_scene, ^scene_name}] = :ets.lookup(table_name, :preview_scene)
    end
  end

  describe "handle_info - StudioModeStateChanged" do
    setup do
      session_id = test_session_id()
      opts = [session_id: session_id, name: :"scene_studio_#{:rand.uniform(10000)}"]
      {:ok, pid} = start_supervised({SceneManager, opts})
      {:ok, pid: pid, session_id: session_id}
    end

    test "updates studio mode state", %{pid: pid, session_id: session_id} do
      event = %{
        eventType: "StudioModeStateChanged",
        eventData: %{studioModeEnabled: true}
      }

      send(pid, {:obs_event, event})
      Process.sleep(10)

      state = SceneManager.get_state(pid)
      assert state.studio_mode_enabled == true

      # Send disable event
      event2 = %{
        eventType: "StudioModeStateChanged",
        eventData: %{studioModeEnabled: false}
      }

      send(pid, {:obs_event, event2})
      Process.sleep(10)

      state2 = SceneManager.get_state(pid)
      assert state2.studio_mode_enabled == false
    end
  end

  describe "handle_info - unknown events" do
    setup do
      session_id = test_session_id()
      opts = [session_id: session_id, name: :"scene_unknown_#{:rand.uniform(10000)}"]
      {:ok, pid} = start_supervised({SceneManager, opts})
      {:ok, pid: pid, session_id: session_id}
    end

    test "ignores unknown event types", %{pid: pid, session_id: session_id} do
      initial_state = SceneManager.get_state(pid)

      event = %{
        eventType: "UnknownEventType",
        eventData: %{some: "data"}
      }

      send(pid, {:obs_event, event})
      Process.sleep(10)

      # State should be unchanged
      final_state = SceneManager.get_state(pid)
      assert initial_state == final_state
    end
  end

  describe "get_scenes_cached/1" do
    setup do
      session_id = "cache_test_#{:rand.uniform(10000)}"
      opts = [session_id: session_id, name: :"scene_cache_#{session_id}"]
      {:ok, pid} = start_supervised({SceneManager, opts})
      {:ok, pid: pid, session_id: session_id}
    end

    test "returns scenes from ETS cache", %{pid: pid, session_id: session_id} do
      # Initially empty
      assert {:error, :not_found} = SceneManager.get_scenes_cached(session_id)

      # Update scenes
      scenes = [
        %{sceneName: "Scene A", sceneIndex: 0},
        %{sceneName: "Scene B", sceneIndex: 1}
      ]

      event = %{
        eventType: "SceneListChanged",
        eventData: %{scenes: scenes}
      }

      send(pid, {:obs_event, event})
      Process.sleep(10)

      # Should now return scenes from cache
      assert {:ok, ^scenes} = SceneManager.get_scenes_cached(session_id)
    end

    test "returns error for non-existent session" do
      assert {:error, :not_found} = SceneManager.get_scenes_cached("non_existent_session")
    end
  end

  describe "comprehensive scene management flow" do
    setup do
      session_id = test_session_id()
      opts = [session_id: session_id, name: :"scene_flow_#{:rand.uniform(10000)}"]
      {:ok, pid} = start_supervised({SceneManager, opts})

      # Subscribe to broadcasts
      Phoenix.PubSub.subscribe(Server.PubSub, "obs:events")

      {:ok, pid: pid, session_id: session_id}
    end

    test "handles complete scene workflow", %{pid: pid, session_id: session_id} do
      # 1. Set scene list
      scenes = [
        %{sceneName: "Starting Scene", sceneIndex: 0},
        %{sceneName: "Main Scene", sceneIndex: 1},
        %{sceneName: "BRB Scene", sceneIndex: 2},
        %{sceneName: "Ending Scene", sceneIndex: 3}
      ]

      send(
        pid,
        {:obs_event,
         %{
           eventType: "SceneListChanged",
           eventData: %{scenes: scenes}
         }}
      )

      # 2. Enable studio mode
      send(
        pid,
        {:obs_event,
         %{
           eventType: "StudioModeStateChanged",
           eventData: %{studioModeEnabled: true}
         }}
      )

      # 3. Set current scene
      send(
        pid,
        {:obs_event,
         %{
           eventType: "CurrentProgramSceneChanged",
           eventData: %{sceneName: "Starting Scene"}
         }}
      )

      # 4. Set preview scene
      send(
        pid,
        {:obs_event,
         %{
           eventType: "CurrentPreviewSceneChanged",
           eventData: %{sceneName: "Main Scene"}
         }}
      )

      # Wait for all events to process
      Process.sleep(20)

      # Verify final state
      state = SceneManager.get_state(pid)
      assert state.scene_list == scenes
      assert state.studio_mode_enabled == true
      assert state.current_scene == "Starting Scene"
      assert state.preview_scene == "Main Scene"

      # Verify broadcast was received
      assert_received {:scene_current_changed,
                       %{
                         session_id: ^session_id,
                         scene_name: "Starting Scene"
                       }}
    end
  end

  describe "ETS table lifecycle" do
    test "ETS table is cleaned up when process terminates" do
      session_id = "cleanup_#{:rand.uniform(10000)}"
      table_name = :"obs_scenes_#{session_id}"
      opts = [session_id: session_id, name: :"scene_cleanup_#{session_id}"]

      {:ok, pid} = SceneManager.start_link(opts)

      # Verify table exists
      assert :ets.info(table_name) != :undefined

      # Stop the process
      GenServer.stop(pid)
      Process.sleep(10)

      # Table should be gone
      assert :ets.info(table_name) == :undefined
    end
  end
end
