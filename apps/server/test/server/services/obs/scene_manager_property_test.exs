defmodule Server.Services.OBS.SceneManagerPropertyTest do
  @moduledoc """
  Property-based tests for the OBS SceneManager.

  Tests invariants and properties including:
  - Scene list consistency
  - Current scene is always in scene list (when set)
  - Preview scene is always in scene list (when set)
  - ETS cache stays synchronized with state
  - Concurrent updates maintain consistency
  - Broadcast events contain correct data
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Server.Services.OBS.SceneManager

  setup do
    # Start PubSub if not already started
    case start_supervised({Phoenix.PubSub, name: Server.PubSub}) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end
  end

  describe "scene list management properties" do
    property "scene list updates maintain consistency" do
      check all(
              session_id <- session_id_gen(),
              scene_lists <- list_of(scene_list_gen(), min_length: 1, max_length: 10)
            ) do
        name = :"scene_prop_#{session_id}_#{:rand.uniform(10000)}"
        opts = [session_id: session_id, name: name]
        {:ok, pid} = SceneManager.start_link(opts)

        # Apply all scene list updates
        for scenes <- scene_lists do
          event = %{
            eventType: "SceneListChanged",
            eventData: %{scenes: scenes}
          }

          send(pid, {:obs_event, event})
        end

        Process.sleep(20)

        # Final state should match last scene list
        state = SceneManager.get_state(pid)
        last_scenes = List.last(scene_lists)
        assert state.scene_list == last_scenes

        # ETS should also match
        table_name = :"obs_scenes_#{session_id}"

        case :ets.lookup(table_name, :scenes) do
          [{:scenes, ets_scenes}] -> assert ets_scenes == last_scenes
          [] -> assert last_scenes == []
        end

        GenServer.stop(pid)
        Process.sleep(10)
      end
    end

    property "empty or missing scene data is handled gracefully" do
      check all(
              session_id <- session_id_gen(),
              event_data <- scene_event_data_gen()
            ) do
        name = :"scene_empty_#{session_id}_#{:rand.uniform(10000)}"
        opts = [session_id: session_id, name: name]
        {:ok, pid} = SceneManager.start_link(opts)

        event = %{
          eventType: "SceneListChanged",
          eventData: event_data
        }

        send(pid, {:obs_event, event})
        Process.sleep(10)

        # Should not crash and scene list should be empty or valid
        assert Process.alive?(pid)
        state = SceneManager.get_state(pid)
        assert is_list(state.scene_list)

        GenServer.stop(pid)
        Process.sleep(10)
      end
    end
  end

  describe "current scene properties" do
    property "current scene changes are reflected in state and ETS" do
      check all(
              session_id <- session_id_gen(),
              scenes <- non_empty_scene_list_gen(),
              current_scene_changes <-
                list_of(
                  member_of(Enum.map(scenes, & &1.sceneName)),
                  min_length: 1,
                  max_length: 10
                )
            ) do
        name = :"scene_current_#{session_id}_#{:rand.uniform(10000)}"
        opts = [session_id: session_id, name: name]
        {:ok, pid} = SceneManager.start_link(opts)

        # Set up scene list first
        send(
          pid,
          {:obs_event,
           %{
             eventType: "SceneListChanged",
             eventData: %{scenes: scenes}
           }}
        )

        # Apply scene changes
        for scene_name <- current_scene_changes do
          send(
            pid,
            {:obs_event,
             %{
               eventType: "CurrentProgramSceneChanged",
               eventData: %{sceneName: scene_name}
             }}
          )
        end

        Process.sleep(20)

        # Final state should reflect last change
        state = SceneManager.get_state(pid)
        last_scene = List.last(current_scene_changes)
        assert state.current_scene == last_scene

        # ETS should match
        table_name = :"obs_scenes_#{session_id}"
        assert [{:current_scene, ^last_scene}] = :ets.lookup(table_name, :current_scene)

        GenServer.stop(pid)
        Process.sleep(10)
      end
    end

    @tag :skip
    property "scene broadcasts contain correct session and scene data" do
      check all(
              session_id <- session_id_gen(),
              scene_name <- scene_name_gen()
            ) do
        name = :"scene_broadcast_#{session_id}_#{:rand.uniform(10000)}"
        opts = [session_id: session_id, name: name]
        {:ok, pid} = SceneManager.start_link(opts)

        # Subscribe to broadcasts
        Phoenix.PubSub.subscribe(Server.PubSub, "obs:events")

        event = %{
          eventType: "CurrentProgramSceneChanged",
          eventData: %{sceneName: scene_name}
        }

        send(pid, {:obs_event, event})

        # Should receive broadcast with correct data
        assert_receive {:scene_current_changed, broadcast_data}, 100

        assert broadcast_data.session_id == session_id
        assert broadcast_data.scene_name == scene_name

        GenServer.stop(pid)
        Process.sleep(10)
      end
    end
  end

  describe "preview scene properties" do
    property "preview scene updates independently from current scene" do
      check all(
              session_id <- session_id_gen(),
              scenes <- non_empty_scene_list_gen(),
              scene_pairs <-
                list_of(
                  {member_of(Enum.map(scenes, & &1.sceneName)), member_of(Enum.map(scenes, & &1.sceneName))},
                  min_length: 1,
                  max_length: 5
                )
            ) do
        name = :"scene_preview_#{session_id}_#{:rand.uniform(10000)}"
        opts = [session_id: session_id, name: name]
        {:ok, pid} = SceneManager.start_link(opts)

        # Set up scene list
        send(
          pid,
          {:obs_event,
           %{
             eventType: "SceneListChanged",
             eventData: %{scenes: scenes}
           }}
        )

        # Apply current and preview scene changes
        for {current, preview} <- scene_pairs do
          send(
            pid,
            {:obs_event,
             %{
               eventType: "CurrentProgramSceneChanged",
               eventData: %{sceneName: current}
             }}
          )

          send(
            pid,
            {:obs_event,
             %{
               eventType: "CurrentPreviewSceneChanged",
               eventData: %{sceneName: preview}
             }}
          )
        end

        Process.sleep(20)

        # Both should reflect last changes
        state = SceneManager.get_state(pid)
        {last_current, last_preview} = List.last(scene_pairs)

        assert state.current_scene == last_current
        assert state.preview_scene == last_preview

        GenServer.stop(pid)
        Process.sleep(10)
      end
    end
  end

  describe "studio mode properties" do
    property "studio mode state toggles correctly" do
      check all(
              session_id <- session_id_gen(),
              mode_changes <- list_of(boolean(), min_length: 1, max_length: 10)
            ) do
        name = :"scene_studio_#{session_id}_#{:rand.uniform(10000)}"
        opts = [session_id: session_id, name: name]
        {:ok, pid} = SceneManager.start_link(opts)

        # Apply studio mode changes
        for enabled <- mode_changes do
          send(
            pid,
            {:obs_event,
             %{
               eventType: "StudioModeStateChanged",
               eventData: %{studioModeEnabled: enabled}
             }}
          )
        end

        Process.sleep(20)

        # Final state should match last change
        state = SceneManager.get_state(pid)
        assert state.studio_mode_enabled == List.last(mode_changes)

        GenServer.stop(pid)
        Process.sleep(10)
      end
    end
  end

  describe "concurrent update properties" do
    property "concurrent scene updates maintain consistency" do
      check all(
              session_id <- session_id_gen(),
              scenes <- non_empty_scene_list_gen(),
              updates <- concurrent_updates_gen(scenes)
            ) do
        name = :"scene_concurrent_#{session_id}_#{:rand.uniform(10000)}"
        opts = [session_id: session_id, name: name]
        {:ok, pid} = SceneManager.start_link(opts)

        # Set initial scene list
        send(
          pid,
          {:obs_event,
           %{
             eventType: "SceneListChanged",
             eventData: %{scenes: scenes}
           }}
        )

        # Apply updates concurrently
        tasks =
          for update <- updates do
            Task.async(fn -> send(pid, {:obs_event, update}) end)
          end

        Task.await_many(tasks)
        Process.sleep(50)

        # State should be consistent
        state = SceneManager.get_state(pid)

        # All fields should have valid values
        assert is_list(state.scene_list)
        assert is_nil(state.current_scene) or is_binary(state.current_scene)
        assert is_nil(state.preview_scene) or is_binary(state.preview_scene)
        assert is_boolean(state.studio_mode_enabled)

        GenServer.stop(pid)
        Process.sleep(10)
      end
    end
  end

  describe "ETS cache consistency properties" do
    property "ETS cache stays synchronized with GenServer state" do
      check all(
              session_id <- session_id_gen(),
              operations <- scene_operations_gen()
            ) do
        name = :"scene_ets_#{session_id}_#{:rand.uniform(10000)}"
        opts = [session_id: session_id, name: name]
        {:ok, pid} = SceneManager.start_link(opts)
        table_name = :"obs_scenes_#{session_id}"

        # Apply all operations
        for op <- operations do
          send(pid, {:obs_event, op})
        end

        Process.sleep(30)

        # Compare state with ETS
        state = SceneManager.get_state(pid)

        # Check scenes
        case :ets.lookup(table_name, :scenes) do
          [{:scenes, ets_scenes}] ->
            assert ets_scenes == state.scene_list

          [] ->
            assert state.scene_list == []
        end

        # Check current scene if set
        if state.current_scene do
          assert [{:current_scene, scene}] = :ets.lookup(table_name, :current_scene)
          assert scene == state.current_scene
        end

        # Check preview scene if set
        if state.preview_scene do
          assert [{:preview_scene, scene}] = :ets.lookup(table_name, :preview_scene)
          assert scene == state.preview_scene
        end

        GenServer.stop(pid)
        Process.sleep(10)
      end
    end
  end

  describe "get_scenes_cached/1 properties" do
    property "cached scenes match current state" do
      check all(
              session_id <- session_id_gen(),
              scenes <- scene_list_gen()
            ) do
        name = :"scene_cache_prop_#{session_id}_#{:rand.uniform(10000)}"
        opts = [session_id: session_id, name: name]
        {:ok, pid} = SceneManager.start_link(opts)

        if scenes != [] do
          send(
            pid,
            {:obs_event,
             %{
               eventType: "SceneListChanged",
               eventData: %{scenes: scenes}
             }}
          )

          Process.sleep(10)

          assert {:ok, cached_scenes} = SceneManager.get_scenes_cached(session_id)
          assert cached_scenes == scenes
        else
          assert {:error, :not_found} = SceneManager.get_scenes_cached(session_id)
        end

        GenServer.stop(pid)
        Process.sleep(10)
      end
    end
  end

  # Generator functions

  defp session_id_gen do
    map(string(:alphanumeric, min_length: 1, max_length: 10), fn prefix ->
      "#{prefix}_#{System.unique_integer([:positive])}_#{:erlang.phash2(make_ref())}"
    end)
  end

  defp scene_name_gen do
    one_of([
      constant("Main Scene"),
      constant("BRB Scene"),
      constant("Starting Scene"),
      constant("Ending Scene"),
      constant("Game Scene"),
      constant("Chat Scene"),
      map({string(:alphanumeric, min_length: 1), integer(1..100)}, fn {name, num} ->
        "#{name} #{num}"
      end)
    ])
  end

  defp scene_gen do
    map({scene_name_gen(), integer(0..100)}, fn {name, index} ->
      %{sceneName: name, sceneIndex: index}
    end)
  end

  defp scene_list_gen do
    list_of(scene_gen(), max_length: 10)
  end

  defp non_empty_scene_list_gen do
    list_of(scene_gen(), min_length: 1, max_length: 10)
  end

  defp scene_event_data_gen do
    one_of([
      constant(%{}),
      constant(%{scenes: nil}),
      map(scene_list_gen(), fn scenes -> %{scenes: scenes} end)
    ])
  end

  defp concurrent_updates_gen(scenes) do
    scene_names = Enum.map(scenes, & &1.sceneName)

    list_of(
      one_of([
        map(member_of(scene_names), fn name ->
          %{
            eventType: "CurrentProgramSceneChanged",
            eventData: %{sceneName: name}
          }
        end),
        map(member_of(scene_names), fn name ->
          %{
            eventType: "CurrentPreviewSceneChanged",
            eventData: %{sceneName: name}
          }
        end),
        map(boolean(), fn enabled ->
          %{
            eventType: "StudioModeStateChanged",
            eventData: %{studioModeEnabled: enabled}
          }
        end)
      ]),
      min_length: 5,
      max_length: 20
    )
  end

  defp scene_operations_gen do
    list_of(
      frequency([
        {3,
         map(scene_list_gen(), fn scenes ->
           %{eventType: "SceneListChanged", eventData: %{scenes: scenes}}
         end)},
        {2,
         map(scene_name_gen(), fn name ->
           %{eventType: "CurrentProgramSceneChanged", eventData: %{sceneName: name}}
         end)},
        {2,
         map(scene_name_gen(), fn name ->
           %{eventType: "CurrentPreviewSceneChanged", eventData: %{sceneName: name}}
         end)},
        {1,
         map(boolean(), fn enabled ->
           %{eventType: "StudioModeStateChanged", eventData: %{studioModeEnabled: enabled}}
         end)}
      ]),
      min_length: 1,
      max_length: 20
    )
  end
end
