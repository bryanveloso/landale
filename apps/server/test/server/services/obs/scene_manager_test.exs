defmodule Server.Services.OBS.SceneManagerTest do
  @moduledoc """
  Behavior-driven tests for the OBS SceneManager GenServer.

  Tests focus on observable behavior through public APIs rather than
  internal message handling. Events are delivered through the proper
  PubSub channel as they would be in production.
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

      # Verify initial state through public API
      assert SceneManager.get_scenes(pid) == []
      assert SceneManager.get_current_scene(pid) == nil
      assert SceneManager.get_preview_scene(pid) == nil
      assert SceneManager.studio_mode_enabled?(pid) == false

      # Verify ETS table was created
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
  end

  describe "public API queries" do
    setup do
      session_id = test_session_id()
      opts = [session_id: session_id, name: :"scene_state_#{:rand.uniform(10000)}"]
      {:ok, pid} = start_supervised({SceneManager, opts})
      {:ok, pid: pid, session_id: session_id}
    end

    test "get_scene_info returns comprehensive state", %{pid: pid, session_id: session_id} do
      info = SceneManager.get_scene_info(pid)

      assert %{
               scenes: [],
               current_scene: nil,
               preview_scene: nil,
               studio_mode_enabled: false,
               session_id: ^session_id
             } = info
    end

    test "individual state queries work correctly", %{pid: pid} do
      assert SceneManager.get_scenes(pid) == []
      assert SceneManager.get_current_scene(pid) == nil
      assert SceneManager.get_preview_scene(pid) == nil
      assert SceneManager.studio_mode_enabled?(pid) == false
    end
  end

  describe "scene list management" do
    setup do
      session_id = test_session_id()
      opts = [session_id: session_id, name: :"scene_list_#{:rand.uniform(10000)}"]
      {:ok, pid} = start_supervised({SceneManager, opts})
      {:ok, pid: pid, session_id: session_id}
    end

    test "updates scene list from OBS events", %{pid: pid, session_id: session_id} do
      scenes = [
        %{sceneName: "Scene 1", sceneIndex: 0},
        %{sceneName: "Scene 2", sceneIndex: 1},
        %{sceneName: "Scene 3", sceneIndex: 2}
      ]

      # Simulate OBS event through proper channel
      Phoenix.PubSub.broadcast(
        Server.PubSub,
        "obs_events:#{session_id}",
        {:obs_event,
         %{
           eventType: "SceneListChanged",
           eventData: %{scenes: scenes}
         }}
      )

      # Allow time for async processing
      Process.sleep(10)

      # Verify state through public API
      assert SceneManager.get_scenes(pid) == scenes

      # Verify ETS cache was updated
      assert {:ok, ^scenes} = SceneManager.get_scenes_cached(session_id)
    end

    test "handles empty scene list", %{pid: pid, session_id: session_id} do
      Phoenix.PubSub.broadcast(
        Server.PubSub,
        "obs_events:#{session_id}",
        {:obs_event,
         %{
           eventType: "SceneListChanged",
           eventData: %{scenes: []}
         }}
      )

      Process.sleep(10)

      assert SceneManager.get_scenes(pid) == []
    end

    test "handles missing scenes field gracefully", %{pid: pid, session_id: session_id} do
      Phoenix.PubSub.broadcast(
        Server.PubSub,
        "obs_events:#{session_id}",
        {:obs_event,
         %{
           eventType: "SceneListChanged",
           eventData: %{}
         }}
      )

      Process.sleep(10)

      # Should default to empty list
      assert SceneManager.get_scenes(pid) == []
    end
  end

  describe "current scene changes" do
    setup do
      session_id = test_session_id()
      opts = [session_id: session_id, name: :"scene_current_#{:rand.uniform(10000)}"]
      {:ok, pid} = start_supervised({SceneManager, opts})

      # Subscribe to broadcast topic for verification
      Phoenix.PubSub.subscribe(Server.PubSub, "obs:events")

      {:ok, pid: pid, session_id: session_id}
    end

    test "updates current scene and broadcasts event", %{pid: pid, session_id: session_id} do
      scene_name = "Main Scene"

      Phoenix.PubSub.broadcast(
        Server.PubSub,
        "obs_events:#{session_id}",
        {:obs_event,
         %{
           eventType: "CurrentProgramSceneChanged",
           eventData: %{sceneName: scene_name}
         }}
      )

      Process.sleep(10)

      # Verify state through public API
      assert SceneManager.get_current_scene(pid) == scene_name

      # Verify broadcast was sent
      assert_receive {:scene_current_changed,
                      %{
                        session_id: ^session_id,
                        scene_name: ^scene_name
                      }},
                     100

      # Verify ETS cache was updated
      table_name = :"obs_scenes_#{session_id}"
      assert [{:current_scene, ^scene_name}] = :ets.lookup(table_name, :current_scene)
    end

    test "handles scene change to nil", %{pid: pid, session_id: session_id} do
      Phoenix.PubSub.broadcast(
        Server.PubSub,
        "obs_events:#{session_id}",
        {:obs_event,
         %{
           eventType: "CurrentProgramSceneChanged",
           eventData: %{sceneName: nil}
         }}
      )

      Process.sleep(10)

      assert SceneManager.get_current_scene(pid) == nil
    end
  end

  describe "preview scene changes" do
    setup do
      session_id = test_session_id()
      opts = [session_id: session_id, name: :"scene_preview_#{:rand.uniform(10000)}"]
      {:ok, pid} = start_supervised({SceneManager, opts})
      {:ok, pid: pid, session_id: session_id}
    end

    test "updates preview scene in state and ETS", %{pid: pid, session_id: session_id} do
      scene_name = "Preview Scene"

      Phoenix.PubSub.broadcast(
        Server.PubSub,
        "obs_events:#{session_id}",
        {:obs_event,
         %{
           eventType: "CurrentPreviewSceneChanged",
           eventData: %{sceneName: scene_name}
         }}
      )

      Process.sleep(10)

      # Verify state through public API
      assert SceneManager.get_preview_scene(pid) == scene_name

      # Verify ETS cache was updated
      table_name = :"obs_scenes_#{session_id}"
      assert [{:preview_scene, ^scene_name}] = :ets.lookup(table_name, :preview_scene)
    end
  end

  describe "studio mode changes" do
    setup do
      session_id = test_session_id()
      opts = [session_id: session_id, name: :"scene_studio_#{:rand.uniform(10000)}"]
      {:ok, pid} = start_supervised({SceneManager, opts})
      {:ok, pid: pid, session_id: session_id}
    end

    test "updates studio mode state", %{pid: pid, session_id: session_id} do
      # Enable studio mode
      Phoenix.PubSub.broadcast(
        Server.PubSub,
        "obs_events:#{session_id}",
        {:obs_event,
         %{
           eventType: "StudioModeStateChanged",
           eventData: %{studioModeEnabled: true}
         }}
      )

      Process.sleep(10)
      assert SceneManager.studio_mode_enabled?(pid) == true

      # Disable studio mode
      Phoenix.PubSub.broadcast(
        Server.PubSub,
        "obs_events:#{session_id}",
        {:obs_event,
         %{
           eventType: "StudioModeStateChanged",
           eventData: %{studioModeEnabled: false}
         }}
      )

      Process.sleep(10)
      assert SceneManager.studio_mode_enabled?(pid) == false
    end
  end

  describe "ETS cache functionality" do
    setup do
      session_id = "cache_test_#{:rand.uniform(10000)}"
      opts = [session_id: session_id, name: :"scene_cache_#{session_id}"]
      {:ok, pid} = start_supervised({SceneManager, opts})
      {:ok, pid: pid, session_id: session_id}
    end

    test "get_scenes_cached returns scenes from ETS", %{pid: _pid, session_id: session_id} do
      # Initially not found
      assert {:error, :not_found} = SceneManager.get_scenes_cached(session_id)

      # Update scenes
      scenes = [
        %{sceneName: "Scene A", sceneIndex: 0},
        %{sceneName: "Scene B", sceneIndex: 1}
      ]

      Phoenix.PubSub.broadcast(
        Server.PubSub,
        "obs_events:#{session_id}",
        {:obs_event,
         %{
           eventType: "SceneListChanged",
           eventData: %{scenes: scenes}
         }}
      )

      Process.sleep(10)

      # Should now return scenes from cache
      assert {:ok, ^scenes} = SceneManager.get_scenes_cached(session_id)
    end

    test "returns error for non-existent session" do
      assert {:error, :not_found} = SceneManager.get_scenes_cached("non_existent_session")
    end
  end

  describe "comprehensive scene workflow" do
    setup do
      session_id = test_session_id()
      opts = [session_id: session_id, name: :"scene_flow_#{:rand.uniform(10000)}"]
      {:ok, pid} = start_supervised({SceneManager, opts})

      # Subscribe to broadcasts
      Phoenix.PubSub.subscribe(Server.PubSub, "obs:events")

      {:ok, pid: pid, session_id: session_id}
    end

    test "handles complete scene management workflow", %{pid: pid, session_id: session_id} do
      # Set scene list
      scenes = [
        %{sceneName: "Starting Scene", sceneIndex: 0},
        %{sceneName: "Main Scene", sceneIndex: 1},
        %{sceneName: "BRB Scene", sceneIndex: 2},
        %{sceneName: "Ending Scene", sceneIndex: 3}
      ]

      Phoenix.PubSub.broadcast(
        Server.PubSub,
        "obs_events:#{session_id}",
        {:obs_event,
         %{
           eventType: "SceneListChanged",
           eventData: %{scenes: scenes}
         }}
      )

      # Enable studio mode
      Phoenix.PubSub.broadcast(
        Server.PubSub,
        "obs_events:#{session_id}",
        {:obs_event,
         %{
           eventType: "StudioModeStateChanged",
           eventData: %{studioModeEnabled: true}
         }}
      )

      # Set current scene
      Phoenix.PubSub.broadcast(
        Server.PubSub,
        "obs_events:#{session_id}",
        {:obs_event,
         %{
           eventType: "CurrentProgramSceneChanged",
           eventData: %{sceneName: "Starting Scene"}
         }}
      )

      # Set preview scene
      Phoenix.PubSub.broadcast(
        Server.PubSub,
        "obs_events:#{session_id}",
        {:obs_event,
         %{
           eventType: "CurrentPreviewSceneChanged",
           eventData: %{sceneName: "Main Scene"}
         }}
      )

      # Wait for all events to process
      Process.sleep(20)

      # Verify final state through public API
      info = SceneManager.get_scene_info(pid)
      assert info.scenes == scenes
      assert info.studio_mode_enabled == true
      assert info.current_scene == "Starting Scene"
      assert info.preview_scene == "Main Scene"

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

  describe "resilience" do
    setup do
      session_id = test_session_id()
      opts = [session_id: session_id, name: :"scene_resilience_#{:rand.uniform(10000)}"]
      {:ok, pid} = start_supervised({SceneManager, opts})
      {:ok, pid: pid, session_id: session_id}
    end

    test "ignores unknown event types", %{pid: pid, session_id: session_id} do
      initial_info = SceneManager.get_scene_info(pid)

      # Send unknown event
      Phoenix.PubSub.broadcast(
        Server.PubSub,
        "obs_events:#{session_id}",
        {:obs_event,
         %{
           eventType: "UnknownEventType",
           eventData: %{some: "data"}
         }}
      )

      Process.sleep(10)

      # State should be unchanged
      final_info = SceneManager.get_scene_info(pid)
      assert initial_info == final_info
    end
  end
end
