defmodule Server.Services.OBS.SceneManager do
  @moduledoc """
  Manages OBS scene state.

  Maintains the list of scenes, current scene, and preview scene.
  Updates state based on OBS events.
  """
  use GenServer
  require Logger

  defstruct [
    :session_id,
    :ets_table,
    current_scene: nil,
    preview_scene: nil,
    scene_list: [],
    studio_mode_enabled: false
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  @doc """
  Get the current state.
  """
  def get_state(manager) do
    GenServer.call(manager, :get_state)
  end

  @doc """
  Get scenes from ETS cache (fast read).
  """
  def get_scenes_cached(session_id) do
    table_name = :"obs_scenes_#{session_id}"

    case :ets.lookup(table_name, :scenes) do
      [{:scenes, scenes}] -> {:ok, scenes}
      [] -> {:error, :not_found}
    end
  end

  @impl true
  def init(opts) do
    session_id = Keyword.fetch!(opts, :session_id)

    # Create ETS table for fast reads
    table_name = :"obs_scenes_#{session_id}"
    table = :ets.new(table_name, [:set, :protected, :named_table])

    # Subscribe to OBS events
    Phoenix.PubSub.subscribe(Server.PubSub, "obs_events:#{session_id}")

    state = %__MODULE__{
      session_id: session_id,
      ets_table: table
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_info({:obs_event, %{eventType: "SceneListChanged", eventData: data}}, state) do
    scenes = data[:scenes] || []
    state = %{state | scene_list: scenes}

    # Update ETS cache
    :ets.insert(state.ets_table, {:scenes, scenes})

    Logger.info("Scene list updated",
      service: "obs",
      session_id: state.session_id,
      scene_count: length(scenes)
    )

    {:noreply, state}
  end

  def handle_info({:obs_event, %{eventType: "CurrentProgramSceneChanged", eventData: data}}, state) do
    scene_name = data[:sceneName]
    state = %{state | current_scene: scene_name}

    # Update ETS cache
    :ets.insert(state.ets_table, {:current_scene, scene_name})

    # Broadcast scene change
    Phoenix.PubSub.broadcast(
      Server.PubSub,
      "obs:events",
      {:scene_current_changed,
       %{
         session_id: state.session_id,
         scene_name: scene_name
       }}
    )

    {:noreply, state}
  end

  def handle_info({:obs_event, %{eventType: "CurrentPreviewSceneChanged", eventData: data}}, state) do
    scene_name = data[:sceneName]
    state = %{state | preview_scene: scene_name}

    # Update ETS cache
    :ets.insert(state.ets_table, {:preview_scene, scene_name})

    {:noreply, state}
  end

  def handle_info({:obs_event, %{eventType: "StudioModeStateChanged", eventData: data}}, state) do
    enabled = data[:studioModeEnabled]
    state = %{state | studio_mode_enabled: enabled}

    {:noreply, state}
  end

  def handle_info({:obs_event, _event}, state) do
    # Ignore other events
    {:noreply, state}
  end
end
