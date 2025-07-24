defmodule Server.Services.Rainwave do
  @moduledoc """
  Rainwave music service integration using Server.Service abstraction.

  Polls the Rainwave API to track currently playing music and provides
  real-time updates to overlays via Phoenix channels.

  Features:
  - Multi-station support (Game, OCRemix, Covers, Chiptunes, All)
  - User-specific listening detection
  - Automatic station switching detection
  - Real-time overlay updates
  - Health tracking and error recovery
  """

  use Server.Service,
    service_name: "rainwave",
    behaviour: Server.Services.RainwaveBehaviour

  use Server.Service.StatusReporter

  alias Server.Services.Rainwave.State

  # Rainwave station constants
  @stations %{
    game: 1,
    ocremix: 2,
    covers: 3,
    chiptunes: 4,
    all: 5
  }

  @station_names %{
    1 => "Video Game Music",
    2 => "OCR Radio",
    3 => "Covers",
    4 => "Chiptunes",
    5 => "All"
  }

  ## Client API (behaviour implementation)

  @doc "Get current service status"
  @spec get_status() :: {:ok, map()} | {:error, term()}
  @impl true
  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end

  @doc "Enable/disable the service"
  @spec set_enabled(boolean()) :: :ok
  def set_enabled(enabled) do
    GenServer.cast(__MODULE__, {:set_enabled, enabled})
  end

  @doc "Change active station"
  @spec set_station(atom() | integer()) :: :ok
  def set_station(station) do
    GenServer.cast(__MODULE__, {:set_station, station})
  end

  @doc "Update configuration"
  @spec update_config(map()) :: :ok
  def update_config(config) do
    GenServer.cast(__MODULE__, {:update_config, config})
  end

  ## Server.Service Callbacks

  @impl Server.Service
  def do_init(opts) do
    Logger.debug("Initializing Rainwave service with config", opts: opts)

    try do
      # Build initial state from environment and options
      initial_state =
        State.new(
          api_key: Keyword.get(opts, :api_key, System.get_env("RAINWAVE_API_KEY")),
          user_id: Keyword.get(opts, :user_id, System.get_env("RAINWAVE_USER_ID")),
          api_base_url: Keyword.get(opts, :api_base_url, "https://rainwave.cc/api4"),
          poll_interval: Keyword.get(opts, :poll_interval, 10_000),
          station_id: Keyword.get(opts, :station_id, @stations.covers)
        )

      # Set initial station name
      initial_state = %{initial_state | station_name: @station_names[initial_state.station_id]}

      # Convert to plain map for Server.Service compatibility
      state = Map.from_struct(initial_state)

      # Start polling if we have credentials
      if State.has_credentials?(as_struct(state)) do
        Logger.info("Rainwave service initialized with valid credentials",
          station: state.station_name
        )

        {:ok, schedule_poll(state)}
      else
        Logger.warning("Rainwave credentials not found - service will run in degraded mode")
        {:ok, state}
      end
    rescue
      error ->
        Logger.error("Failed to initialize Rainwave service", error: inspect(error))
        {:stop, {:initialization_error, error}}
    end
  end

  @impl Server.Service
  def do_terminate(_reason, state) do
    # Cancel any pending timer
    if state.poll_timer do
      Process.cancel_timer(state.poll_timer)
    end

    Logger.debug("Rainwave service terminated")
    :ok
  end

  @impl Server.Service.StatusReporter
  def do_build_status(state) do
    %{
      # Service configuration
      enabled: state.is_enabled,
      has_credentials: State.has_credentials?(as_struct(state)),

      # Current state
      listening: state.is_listening,
      station: %{
        id: state.station_id,
        name: state.station_name
      },
      current_song: state.current_song,

      # API health metrics
      api_health: %{
        status: state.api_health_status,
        last_call_at: state.last_api_call_at,
        last_success_at: state.last_successful_at,
        error_count: state.api_error_count,
        consecutive_errors: state.consecutive_errors,
        error_rate: State.error_rate(as_struct(state))
      },

      # Configuration
      api_endpoint: state.api_base_url,
      poll_interval_ms: state.poll_interval
    }
  end

  def service_healthy?(state) do
    # Service is healthy if it has credentials and isn't in a down state
    State.has_credentials?(as_struct(state)) and state.api_health_status != :down
  end

  ## GenServer Callbacks

  @impl GenServer
  def handle_cast({:set_enabled, enabled}, state) do
    new_state = %{state | is_enabled: enabled}

    Logger.info("Rainwave service #{if enabled, do: "enabled", else: "disabled"}")

    if enabled do
      {:noreply, schedule_poll(new_state)}
    else
      {:noreply, cancel_poll(new_state)}
    end
  end

  @impl GenServer
  def handle_cast({:set_station, station}, state) do
    station_id = normalize_station_id(station)
    station_name = @station_names[station_id]

    new_state = %{state | station_id: station_id, station_name: station_name}

    Logger.info("Rainwave station changed",
      station_id: station_id,
      station_name: station_name
    )

    # Immediate poll to get new station data
    if state.is_enabled do
      send(self(), :poll)
    end

    {:noreply, new_state}
  end

  @impl GenServer
  def handle_cast({:update_config, config}, state) do
    new_state =
      state
      |> maybe_update_enabled(config["enabled"])
      |> maybe_update_station(config["station_id"])

    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info(:poll, state) do
    new_state =
      if state.is_enabled and State.has_credentials?(as_struct(state)) do
        fetch_now_playing(state)
      else
        state
      end

    {:noreply, schedule_poll(new_state)}
  end

  ## Private Functions

  # Helper to work with state as struct when needed
  defp as_struct(state) when is_map(state) do
    struct(State, state)
  end

  defp schedule_poll(state) do
    # Cancel existing timer
    state = cancel_poll(state)

    if state.is_enabled do
      timer_ref = Process.send_after(self(), :poll, state.poll_interval)
      %{state | poll_timer: timer_ref}
    else
      state
    end
  end

  defp cancel_poll(state) do
    if state.poll_timer do
      Process.cancel_timer(state.poll_timer)
    end

    %{state | poll_timer: nil}
  end

  defp normalize_station_id(station) when is_atom(station) do
    @stations[station] || @stations.covers
  end

  defp normalize_station_id(station) when is_integer(station) do
    if station >= 1 and station <= 5, do: station, else: @stations.covers
  end

  defp normalize_station_id(_), do: @stations.covers

  defp maybe_update_enabled(state, nil), do: state

  defp maybe_update_enabled(state, enabled) when is_boolean(enabled) do
    %{state | is_enabled: enabled}
  end

  defp maybe_update_enabled(state, _), do: state

  defp maybe_update_station(state, nil), do: state

  defp maybe_update_station(state, station_id) do
    normalized_id = normalize_station_id(station_id)
    %{state | station_id: normalized_id, station_name: @station_names[normalized_id]}
  end

  defp fetch_now_playing(state) do
    case make_api_request("/info", state) do
      {:ok, data} ->
        new_state = process_api_response(data, state)
        struct_state = as_struct(new_state)
        updated_struct = State.record_success(struct_state)
        Map.from_struct(updated_struct)

      {:error, reason} ->
        Logger.error("Failed to fetch Rainwave data",
          service: :rainwave,
          error: reason,
          consecutive_errors: state.consecutive_errors + 1
        )

        # Clear current song on error but keep service running
        struct_state = as_struct(state)
        updated_struct = State.record_failure(struct_state)

        new_state =
          updated_struct
          |> Map.from_struct()
          |> Map.put(:current_song, nil)
          |> Map.put(:is_listening, false)

        broadcast_update(new_state)
        new_state
    end
  end

  defp make_api_request(endpoint, state) do
    uri = URI.parse(state.api_base_url <> endpoint)

    body =
      URI.encode_query(%{
        "sid" => state.station_id,
        "key" => state.api_key,
        "user_id" => state.user_id
      })

    headers = [
      {"content-type", "application/x-www-form-urlencoded"},
      {"accept", "application/json"}
    ]

    timeout_ms = NetworkConfig.http_timeout_ms()
    receive_timeout_ms = NetworkConfig.http_receive_timeout_ms()

    with {:ok, conn_pid} <- :gun.open(String.to_charlist(uri.host), uri.port, gun_opts(uri)),
         {:ok, protocol} when protocol in [:http, :http2] <- :gun.await_up(conn_pid, timeout_ms),
         stream_ref <- :gun.post(conn_pid, String.to_charlist(uri.path), headers, body),
         {:ok, response} <- await_response(conn_pid, stream_ref, receive_timeout_ms) do
      :gun.close(conn_pid)
      parse_api_response(response)
    else
      {:error, reason} ->
        {:error, {:network_error, reason}}
    end
  end

  defp gun_opts(%URI{scheme: "https"}), do: %{transport: :tls}
  defp gun_opts(_), do: %{}

  defp await_response(conn_pid, stream_ref, timeout) do
    case :gun.await(conn_pid, stream_ref, timeout) do
      {:response, :fin, status, headers} ->
        {:ok, {status, headers, ""}}

      {:response, :nofin, status, headers} ->
        case :gun.await_body(conn_pid, stream_ref, timeout) do
          {:ok, body} -> {:ok, {status, headers, body}}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_api_response({200, _headers, body}) do
    case JSON.decode(body) do
      {:ok, data} -> {:ok, data}
      {:error, reason} -> {:error, {:json_decode_error, reason}}
    end
  end

  defp parse_api_response({status, _headers, body}) when status >= 400 do
    case JSON.decode(body) do
      {:ok, %{"error" => error}} ->
        {:error, String.to_atom(error)}

      {:ok, data} ->
        {:error, {:http_error, status, data}}

      {:error, _} ->
        {:error, {:http_error, status, body}}
    end
  end

  defp process_api_response(data, state) do
    # Check if user is currently listening
    user_listening = check_user_listening(data, state.user_id)

    new_state =
      if user_listening do
        # Extract current song information
        current_song = extract_current_song(data)
        station_name = Map.get(data, "station_name", state.station_name)

        %{state | current_song: current_song, station_name: station_name, is_listening: true}
      else
        # User not listening, clear current song
        %{state | current_song: nil, is_listening: false}
      end

    # Broadcast update if something changed
    if state_changed?(state, new_state) do
      Logger.debug("Rainwave state updated",
        listening: new_state.is_listening,
        has_song: not is_nil(new_state.current_song)
      )

      broadcast_update(new_state)
    end

    new_state
  end

  defp check_user_listening(data, user_id) do
    case Map.get(data, "user") do
      %{"id" => id} when is_binary(id) -> id == user_id
      %{"id" => id} when is_integer(id) -> Integer.to_string(id) == user_id
      _ -> false
    end
  end

  defp extract_current_song(data) do
    case Map.get(data, "sched_current") do
      %{"songs" => [song | _]} = sched when is_map(song) ->
        %{
          title: Map.get(song, "title", "Unknown"),
          artist: extract_artists(song),
          album: extract_album(song),
          length: Map.get(song, "length", 0),
          start_time: Map.get(sched, "start_actual") || Map.get(sched, "start", 0),
          end_time: Map.get(sched, "end", 0),
          url: Map.get(song, "url"),
          album_art: extract_album_art(song)
        }

      _ ->
        nil
    end
  end

  defp extract_artists(song) do
    case Map.get(song, "artists") do
      artists when is_list(artists) ->
        artists
        |> Enum.map(&Map.get(&1, "name", "Unknown"))
        |> Enum.join(", ")

      _ ->
        "Unknown"
    end
  end

  defp extract_album(song) do
    case Map.get(song, "albums") do
      [album | _] when is_map(album) -> Map.get(album, "name", "Unknown")
      _ -> "Unknown"
    end
  end

  defp extract_album_art(song) do
    case Map.get(song, "albums") do
      [album | _] when is_map(album) ->
        case Map.get(album, "art") do
          art when is_binary(art) -> "https://rainwave.cc#{art}_320.jpg"
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp state_changed?(old_state, new_state) do
    old_state.current_song != new_state.current_song or
      old_state.is_listening != new_state.is_listening or
      old_state.station_name != new_state.station_name
  end

  defp broadcast_update(state) do
    event_data = %{
      enabled: state.is_enabled,
      listening: state.is_listening,
      station_id: state.station_id,
      station_name: state.station_name,
      current_song: state.current_song
    }

    correlation_id = Map.get(state, :__service_meta__, %{}) |> Map.get(:correlation_id)
    Events.emit("rainwave:update", event_data, correlation_id)
  end
end
