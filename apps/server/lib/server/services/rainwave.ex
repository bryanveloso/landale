defmodule Server.Services.Rainwave do
  @behaviour Server.Services.RainwaveBehaviour

  @moduledoc """
  Rainwave music service integration.

  Polls the Rainwave API to track currently playing music and provides
  real-time updates to overlays via Phoenix channels.

  Features:
  - Multi-station support (Game, OCRemix, Covers, Chiptunes, All)
  - User-specific listening detection
  - Automatic station switching detection
  - Real-time overlay updates
  """

  use GenServer
  require Logger
  alias Server.{Events, Logging, ServiceError}

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

  # API configuration
  @api_base_url "https://rainwave.cc/api4"
  # 10 seconds
  @poll_interval 10_000

  # State structure
  defstruct [
    :api_key,
    :user_id,
    :station_id,
    :station_name,
    :current_song,
    :is_enabled,
    :is_listening,
    :poll_timer,
    :correlation_id
  ]

  @type t :: %__MODULE__{
          api_key: String.t() | nil,
          user_id: String.t() | nil,
          station_id: integer(),
          station_name: String.t() | nil,
          current_song: map() | nil,
          is_enabled: boolean(),
          is_listening: boolean(),
          poll_timer: reference() | nil,
          correlation_id: String.t()
        }

  ## Client API

  @doc "Start the Rainwave service"
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

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

  ## GenServer Callbacks

  @impl true
  def init(_opts) do
    correlation_id = Server.CorrelationId.generate()
    Logging.set_service_context(:rainwave, correlation_id: correlation_id)

    Logger.info("Service starting", correlation_id: correlation_id)

    state = %__MODULE__{
      api_key: System.get_env("RAINWAVE_API_KEY"),
      user_id: System.get_env("RAINWAVE_USER_ID"),
      # Default to Covers
      station_id: @stations.covers,
      station_name: @station_names[@stations.covers],
      current_song: nil,
      is_enabled: false,
      is_listening: false,
      poll_timer: nil,
      correlation_id: correlation_id
    }

    # Start polling if we have credentials
    if state.api_key && state.user_id do
      {:ok, schedule_poll(state)}
    else
      Logger.warning("Rainwave credentials not found in environment")

      {:ok, state}
    end
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    status = %{
      enabled: state.is_enabled,
      listening: state.is_listening,
      station_id: state.station_id,
      station_name: state.station_name,
      current_song: state.current_song,
      has_credentials: !!(state.api_key && state.user_id)
    }

    {:reply, {:ok, status}, state}
  end

  @impl true
  def handle_cast({:set_enabled, enabled}, state) do
    new_state = %{state | is_enabled: enabled}

    Logger.info("Service #{if enabled, do: "enabled", else: "disabled"}")

    if enabled do
      {:noreply, schedule_poll(new_state)}
    else
      {:noreply, cancel_poll(new_state)}
    end
  end

  @impl true
  def handle_cast({:set_station, station}, state) do
    station_id = normalize_station_id(station)
    station_name = @station_names[station_id]

    new_state = %{state | station_id: station_id, station_name: station_name}

    Logger.info("Station changed", station_id: station_id, station_name: station_name)

    # Immediate poll to get new station data
    if state.is_enabled do
      send(self(), :poll)
    end

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:update_config, config}, state) do
    new_state =
      state
      |> maybe_update_enabled(config["enabled"])
      |> maybe_update_station(config["station_id"])

    {:noreply, new_state}
  end

  @impl true
  def handle_info(:poll, state) do
    new_state =
      if state.is_enabled and not is_nil(state.api_key) and not is_nil(state.user_id) do
        fetch_now_playing(state)
      else
        state
      end

    {:noreply, schedule_poll(new_state)}
  end

  @impl true
  def handle_info({:EXIT, _pid, reason}, state) do
    Logger.warning("HTTP request process exited", reason: reason)

    {:noreply, state}
  end

  @impl true
  def handle_info(message, state) do
    Logger.debug("Unhandled message received", message: inspect(message))
    {:noreply, state}
  end

  ## Private Functions

  defp schedule_poll(state) do
    # Cancel existing timer
    state = cancel_poll(state)

    if state.is_enabled do
      timer_ref = Process.send_after(self(), :poll, @poll_interval)
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
    if station in 1..5, do: station, else: @stations.covers
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
        process_api_response(data, state)

      {:error, reason} ->
        service_error = ServiceError.from_error_tuple(:rainwave, "fetch_now_playing", {:error, reason})
        Logger.error("Failed to fetch Rainwave data", error: service_error)

        # Clear current song on error but keep service running
        new_state = %{state | current_song: nil, is_listening: false}
        broadcast_update(new_state)
        new_state
    end
  end

  defp make_api_request(endpoint, state) do
    uri = URI.parse(@api_base_url <> endpoint)

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

    http_config = Server.NetworkConfig.http_config()

    with {:ok, conn_pid} <- :gun.open(String.to_charlist(uri.host), uri.port, gun_opts(uri)),
         {:ok, protocol} when protocol in [:http, :http2] <- :gun.await_up(conn_pid, http_config.timeout),
         stream_ref <- :gun.post(conn_pid, String.to_charlist(uri.path), headers, body),
         {:ok, response} <- await_response(conn_pid, stream_ref, http_config.receive_timeout) do
      :gun.close(conn_pid)
      parse_api_response(response)
    else
      {:error, reason} ->
        Logger.error("Rainwave API request failed",
          service: :rainwave,
          correlation_id: state.correlation_id,
          reason: inspect(reason)
        )

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
        service: :rainwave,
        correlation_id: state.correlation_id,
        listening: new_state.is_listening,
        has_song: !!new_state.current_song
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

    Events.emit("rainwave:update", event_data, state.correlation_id)
  end
end
