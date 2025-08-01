defmodule Server.Services.IronmonTCP do
  @moduledoc """
  IronMON TCP server integration using Elixir GenServer.

  Receives length-prefixed JSON messages from IronMON Connect client
  for tracking Pokemon game state and checkpoints. Replaces the TypeScript
  implementation with native Elixir TCP handling.

  ## Message Format

  Messages are length-prefixed in the format: "LENGTH MESSAGE"
  Example: "23 {\"type\":\"init\",...}"

  ## Supported Message Types

  - `init` - Game initialization with version and game type
  - `seed` - Seed count updates
  - `checkpoint` - Checkpoint clears with ID and optional seed
  - `location` - Location changes with area ID
  - `battle_start` - Battle encounters with trainer and pokemon info
  - `battle_end` - Battle results with outcome and pokemon state
  - `pokemon_update` - Team composition changes
  - `item_update` - Inventory changes
  - `stats_update` - Trainer stats updates
  - `error` - Error notifications from the client
  - `heartbeat` - Keep-alive messages

  ## Events Published

  All processed messages are published via Phoenix.PubSub on the
  "ironmon:events" topic for consumption by the dashboard and overlays.
  """

  use Server.Service,
    service_name: "ironmon-tcp",
    behaviour: Server.Services.IronmonTCPBehaviour

  use Server.Service.StatusReporter

  # Default TCP server configuration
  @default_port 8080
  @default_hostname "0.0.0.0"

  # Game enumeration matching client-side
  @games %{
    1 => "Ruby/Sapphire",
    2 => "Emerald",
    3 => "FireRed/LeafGreen"
  }

  # Client API - start_link provided by Server.Service

  @doc """
  Gets the current status of the TCP server.

  ## Returns
  - `{:ok, status}` where status contains port, connection count, etc.
  """
  @spec get_status() :: {:ok, map()}
  @impl true
  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end

  @doc """
  Stops the TCP server gracefully.
  """
  @spec stop() :: :ok
  def stop do
    GenServer.stop(__MODULE__, :normal)
  end

  @doc """
  Lists all available IronMON challenges.
  """
  @spec list_challenges() :: {:ok, [map()]} | {:error, term()}
  @impl true
  def list_challenges do
    challenges = Server.Ironmon.list_challenges()
    {:ok, challenges}
  rescue
    error -> {:error, inspect(error)}
  end

  @doc """
  Lists checkpoints for a specific challenge.
  """
  @spec list_checkpoints(integer()) :: {:ok, [map()]} | {:error, term()}
  @impl true
  def list_checkpoints(challenge_id) do
    checkpoints = Server.Ironmon.list_checkpoints_for_challenge(challenge_id)
    {:ok, checkpoints}
  rescue
    error -> {:error, inspect(error)}
  end

  @doc """
  Gets statistics for a specific checkpoint.
  """
  @spec get_checkpoint_stats(integer()) :: {:ok, map()} | {:error, term()}
  @impl true
  def get_checkpoint_stats(checkpoint_id) do
    stats = Server.Ironmon.get_checkpoint_stats(checkpoint_id)
    {:ok, stats}
  rescue
    error -> {:error, inspect(error)}
  end

  @doc """
  Gets recent IronMON run results.
  """
  @spec get_recent_results(integer()) :: {:ok, [map()]} | {:error, term()}
  @impl true
  def get_recent_results(limit \\ 10) do
    results = Server.Ironmon.get_recent_results(limit, nil)
    {:ok, results}
  rescue
    error -> {:error, inspect(error)}
  end

  @doc """
  Gets the active challenge for a specific seed.
  """
  @spec get_active_challenge(integer()) :: {:ok, map()} | {:error, term()}
  @impl true
  def get_active_challenge(seed_id) do
    case Server.Ironmon.get_active_challenge(seed_id) do
      {:ok, challenge} -> {:ok, challenge}
      {:error, reason} -> {:error, reason}
    end
  rescue
    error -> {:error, inspect(error)}
  end

  # Service Implementation

  @impl Server.Services.IronmonTCPBehaviour
  def get_health do
    GenServer.call(__MODULE__, :get_health)
  end

  @impl Server.Services.IronmonTCPBehaviour
  def get_info do
    %{
      name: "ironmon-tcp",
      version: "1.0.0",
      capabilities: [:tcp_server, :json_protocol, :game_tracking, :checkpoint_tracking],
      description: "IronMON TCP server for tracking Pokemon game state and checkpoints"
    }
  end

  @impl Server.Service
  def do_init(opts) do
    port = Keyword.get(opts, :port, @default_port)
    hostname = Keyword.get(opts, :hostname, @default_hostname)

    state = %{
      port: port,
      hostname: hostname,
      connections: %{},
      listen_socket: nil
    }

    case start_tcp_server(state) do
      {:ok, new_state} ->
        Logger.info("TCP server started", port: port, hostname: hostname)
        {:ok, new_state}

      {:error, reason} ->
        {:stop, {:tcp_startup_failed, reason}}
    end
  end

  @impl Server.Service
  def do_terminate(_reason, state) do
    if state[:listen_socket] do
      :gen_tcp.close(state.listen_socket)
    end

    # Close all client connections
    Enum.each(state.connections, fn {socket, _buffer} ->
      :gen_tcp.close(socket)
    end)

    :ok
  end

  @impl Server.Service.StatusReporter
  def do_build_status(state) do
    %{
      listening: state[:listen_socket] != nil,
      port: state.port,
      hostname: state.hostname,
      connection_count: map_size(state.connections),
      connections: Map.keys(state.connections)
    }
  end

  # GenServer Callbacks

  @impl GenServer
  def handle_call(:get_health, _from, state) do
    # Determine health status based on service state
    health_status =
      if state[:listen_socket] == nil do
        :unhealthy
      else
        :healthy
      end

    health_response = %{
      status: health_status,
      checks: %{
        tcp_socket: if(state[:listen_socket] != nil, do: :pass, else: :fail),
        listening: if(state[:listen_socket] != nil, do: :pass, else: :fail)
      },
      details: %{
        port: state.port,
        hostname: state.hostname,
        connection_count: map_size(state.connections),
        listening: state[:listen_socket] != nil
      }
    }

    {:reply, {:ok, health_response}, state}
  end

  @impl GenServer
  def handle_info({:tcp, socket, data}, state) do
    correlation_id = CorrelationId.generate()

    CorrelationId.with_context(correlation_id, fn ->
      Logger.debug("TCP data received",
        service: "ironmon_tcp",
        correlation_id: correlation_id,
        data_size: byte_size(data)
      )

      case handle_tcp_data(socket, data, state) do
        {:ok, new_state} ->
          {:noreply, new_state}
      end
    end)
  end

  @impl GenServer
  def handle_info({:tcp_closed, socket}, state) do
    Logger.info("Client disconnected",
      service: "ironmon_tcp"
    )

    new_connections = Map.delete(state.connections, socket)
    {:noreply, %{state | connections: new_connections}}
  end

  @impl GenServer
  def handle_info({:tcp_error, socket, reason}, state) do
    Logger.warning("TCP socket error",
      service: "ironmon_tcp",
      error: inspect(reason)
    )

    new_connections = Map.delete(state.connections, socket)
    {:noreply, %{state | connections: new_connections}}
  end

  @impl GenServer
  def handle_info({:tcp_accept, listen_socket, client_socket}, %{listen_socket: listen_socket} = state) do
    # Accept the connection
    :gen_tcp.controlling_process(client_socket, self())
    :inet.setopts(client_socket, active: true)

    # Add to connections with empty buffer
    new_connections = Map.put(state.connections, client_socket, "")
    {:noreply, %{state | connections: new_connections}}
  end

  @impl GenServer
  def handle_info(message, state) do
    Logger.debug("Unhandled message",
      service: "ironmon_tcp",
      message: inspect(message)
    )

    {:noreply, state}
  end

  # Private Functions

  defp start_tcp_server(state) do
    case :inet.parse_address(to_charlist(state.hostname)) do
      {:ok, ip_address} ->
        tcp_options = [
          :binary,
          {:packet, :raw},
          {:active, true},
          {:reuseaddr, true},
          {:ip, ip_address}
        ]

        case :gen_tcp.listen(state.port, tcp_options) do
          {:ok, listen_socket} ->
            Logger.info("TCP socket bound successfully",
              service: "ironmon_tcp",
              port: state.port,
              ip: to_string(:inet.ntoa(ip_address))
            )

            # Start accepting connections
            pid = spawn_link(fn -> accept_connections(listen_socket, self()) end)

            Logger.info("TCP accept process spawned",
              service: "ironmon_tcp",
              accept_pid: inspect(pid)
            )

            {:ok, %{state | listen_socket: listen_socket}}

          {:error, reason} ->
            Logger.error("Failed to bind TCP socket",
              service: "ironmon_tcp",
              port: state.port,
              error: inspect(reason)
            )

            {:error, reason}
        end

      {:error, reason} ->
        {:error, {:invalid_ip_address, reason}}
    end
  end

  defp accept_connections(listen_socket, server_pid) do
    {:ok, port} = :inet.port(listen_socket)

    Logger.info("TCP server listening for connections",
      service: "ironmon_tcp",
      port: port
    )

    accept_loop(listen_socket, server_pid)
  end

  defp accept_loop(listen_socket, server_pid) do
    case :gen_tcp.accept(listen_socket) do
      {:ok, client_socket} ->
        {:ok, {ip, port}} = :inet.peername(client_socket)

        Logger.info("Client connected",
          service: "ironmon_tcp",
          client_ip: to_string(:inet.ntoa(ip)),
          client_port: port
        )

        send(server_pid, {:tcp_accept, listen_socket, client_socket})
        accept_loop(listen_socket, server_pid)

      {:error, :closed} ->
        :ok

      {:error, reason} ->
        Logger.error("TCP accept failed",
          service: "ironmon_tcp",
          error: inspect(reason)
        )

        accept_loop(listen_socket, server_pid)
    end
  end

  defp handle_tcp_data(socket, data, state) do
    # Get existing buffer for this socket
    buffer = Map.get(state.connections, socket, "")
    updated_buffer = buffer <> data

    Logger.info("TCP data buffered",
      service: "ironmon_tcp",
      buffer_size: byte_size(updated_buffer),
      new_data_size: byte_size(data),
      preview: String.slice(updated_buffer, 0, 100)
    )

    # Process all complete messages in the buffer
    {remaining_buffer, new_state} = process_messages(socket, updated_buffer, state)

    # Update the buffer for this socket
    new_connections = Map.put(state.connections, socket, remaining_buffer)
    final_state = %{new_state | connections: new_connections}

    {:ok, final_state}
  end

  defp process_messages(_socket, buffer, state) when byte_size(buffer) == 0 do
    {buffer, state}
  end

  defp process_messages(socket, buffer, state) do
    Logger.debug("Processing buffer",
      service: "ironmon_tcp",
      buffer_size: byte_size(buffer),
      preview: String.slice(buffer, 0, 50)
    )

    case String.split(buffer, " ", parts: 2) do
      [length_str, rest] ->
        case Integer.parse(length_str) do
          {length, ""} when byte_size(rest) >= length ->
            # We have a complete message
            <<message::binary-size(length), remaining::binary>> = rest

            Logger.info("Found complete message",
              service: "ironmon_tcp",
              message_length: length,
              remaining_buffer: byte_size(remaining)
            )

            case process_message(message) do
              :ok ->
                Logger.debug("Message processed successfully",
                  service: "ironmon_tcp"
                )

              {:error, reason} ->
                Logger.warning("Message processing failed",
                  service: "ironmon_tcp",
                  error: inspect(reason)
                )
            end

            # Process any remaining messages
            process_messages(socket, remaining, state)

          {_length, ""} ->
            # Not enough data yet
            {buffer, state}

          :error ->
            Logger.error("Invalid message length",
              service: "ironmon_tcp",
              length_str: length_str
            )

            # Skip invalid data
            {rest, state}
        end

      [_] ->
        # No space found yet, need more data
        {buffer, state}
    end
  end

  defp process_message(message_str) do
    Logger.debug("Processing IronMON message",
      service: "ironmon_tcp",
      message_size: byte_size(message_str)
    )

    with {:ok, json} <- JSON.decode(message_str),
         {:ok, validated} <- validate_message(json) do
      # Extract v2.0 fields if present
      timestamp = Map.get(json, "timestamp")
      frame = Map.get(json, "frame")

      # Enhance the validated message with v2.0 fields
      message =
        if timestamp do
          validated
          |> Map.put(:timestamp, timestamp)
          |> Map.put(:frame, frame)
        else
          validated
        end

      handle_ironmon_message(message, json)
    else
      {:error, reason} ->
        Logger.warning("Invalid IronMON message",
          service: "ironmon_tcp",
          error: inspect(reason),
          raw_message: message_str
        )

        {:error, "Invalid JSON or message format"}
    end
  end

  # Support both old format (metadata) and new v2.0 format (data)
  defp validate_message(%{"type" => type} = json) do
    # Try new format first, fall back to old format
    data = Map.get(json, "data") || Map.get(json, "metadata")

    if is_non_struct_map(data) do
      validate_message_by_type(type, data, json)
    else
      {:error, "Invalid message format: missing data or metadata"}
    end
  end

  defp validate_message_by_type(type, data, _json) when is_non_struct_map(data) do
    validator = get_message_validator(type)

    if validator do
      validator.(data)
    else
      {:error, "Unknown message type: #{type}"}
    end
  end

  defp get_message_validator("init"), do: &validate_init_data/1
  defp get_message_validator("seed"), do: &validate_seed_data/1
  defp get_message_validator("checkpoint"), do: &validate_checkpoint_data/1
  defp get_message_validator("location"), do: &validate_location_data/1
  defp get_message_validator("battle_start"), do: &validate_battle_start_data/1
  defp get_message_validator("battle_end"), do: &validate_battle_end_data/1
  defp get_message_validator("pokemon_update"), do: &validate_pokemon_update_data/1
  defp get_message_validator("item_update"), do: &validate_item_update_data/1
  defp get_message_validator("stats_update"), do: &validate_stats_update_data/1
  defp get_message_validator("error"), do: &validate_error_data/1
  defp get_message_validator("heartbeat"), do: &validate_heartbeat_data/1
  defp get_message_validator(_), do: nil

  defp validate_init_data(%{"version" => version, "game" => game})
       when is_binary(version) and is_integer(game) do
    if Map.has_key?(@games, game) do
      {:ok, %{type: "init", metadata: %{version: version, game: game}}}
    else
      {:error, "Invalid game ID: #{game}"}
    end
  end

  defp validate_init_data(_), do: {:error, "Invalid init data"}

  defp validate_seed_data(%{"count" => count})
       when is_integer(count) do
    {:ok, %{type: "seed", metadata: %{count: count}}}
  end

  defp validate_seed_data(_), do: {:error, "Invalid seed data"}

  defp validate_checkpoint_data(data) do
    with %{"id" => id, "name" => name} <- data,
         true <- is_integer(id) and is_binary(name) do
      seed = Map.get(data, "seed")
      validated_metadata = %{id: id, name: name}

      validated_metadata =
        if is_integer(seed),
          do: Map.put(validated_metadata, :seed, seed),
          else: validated_metadata

      {:ok, %{type: "checkpoint", metadata: validated_metadata}}
    else
      _ -> {:error, "Invalid checkpoint data"}
    end
  end

  defp validate_location_data(%{"id" => id})
       when is_integer(id) do
    {:ok, %{type: "location", metadata: %{id: id}}}
  end

  defp validate_location_data(_), do: {:error, "Invalid location data"}

  defp validate_battle_start_data(%{"trainer" => trainer, "pokemon" => pokemon})
       when is_binary(trainer) and is_list(pokemon) do
    {:ok, %{type: "battle_start", metadata: %{trainer: trainer, pokemon: pokemon}}}
  end

  defp validate_battle_start_data(_), do: {:error, "Invalid battle_start data"}

  defp validate_battle_end_data(%{"result" => result, "pokemon" => pokemon})
       when result in ["win", "loss", "run"] and is_list(pokemon) do
    {:ok, %{type: "battle_end", metadata: %{result: result, pokemon: pokemon}}}
  end

  defp validate_battle_end_data(_), do: {:error, "Invalid battle_end data"}

  defp validate_pokemon_update_data(%{"team" => team})
       when is_list(team) do
    {:ok, %{type: "pokemon_update", metadata: %{team: team}}}
  end

  defp validate_pokemon_update_data(_), do: {:error, "Invalid pokemon_update data"}

  defp validate_item_update_data(%{"items" => items})
       when is_list(items) do
    {:ok, %{type: "item_update", metadata: %{items: items}}}
  end

  defp validate_item_update_data(_), do: {:error, "Invalid item_update data"}

  defp validate_stats_update_data(%{"stats" => stats})
       when is_map(stats) do
    {:ok, %{type: "stats_update", metadata: %{stats: stats}}}
  end

  defp validate_stats_update_data(_), do: {:error, "Invalid stats_update data"}

  defp validate_error_data(%{"code" => code, "message" => message})
       when is_binary(code) and is_binary(message) do
    {:ok, %{type: "error", metadata: %{code: code, message: message}}}
  end

  defp validate_error_data(_), do: {:error, "Invalid error data"}

  defp validate_heartbeat_data(_data) do
    # Heartbeat can have any data or none
    {:ok, %{type: "heartbeat", metadata: %{}}}
  end

  defp handle_ironmon_message(%{type: type, metadata: metadata} = message, raw_json) do
    correlation_id = CorrelationId.get_logger_metadata()

    # Build event data with v2.0 fields if available
    event_data = %{
      type: type,
      metadata: metadata,
      source: "tcp",
      correlation_id: correlation_id,
      timestamp: Map.get(message, :timestamp, System.system_time(:second))
    }

    # Add frame if present
    event_data =
      if Map.has_key?(message, :frame) do
        Map.put(event_data, :frame, message.frame)
      else
        event_data
      end

    # Add raw data field for v2.0 compatibility
    event_data =
      if Map.has_key?(raw_json, "data") do
        Map.put(event_data, :data, raw_json["data"])
      else
        event_data
      end

    Logger.info("IronMON event received",
      service: "ironmon_tcp",
      correlation_id: correlation_id,
      event_type: type,
      frame: Map.get(message, :frame)
    )

    handle_event_by_type(type, event_data, metadata, correlation_id)
    :ok
  end

  defp handle_event_by_type("init", event_data, metadata, correlation_id) do
    game_name = Map.get(@games, metadata.game, "Unknown")

    Logger.info("IronMON game initialized",
      service: "ironmon_tcp",
      correlation_id: correlation_id,
      version: metadata.version,
      game: game_name
    )

    Events.publish_ironmon_event("init", event_data, batch: false)
  end

  defp handle_event_by_type("seed", event_data, metadata, correlation_id) do
    Logger.info("IronMON seed updated",
      service: "ironmon_tcp",
      correlation_id: correlation_id,
      seed_count: metadata.count
    )

    handle_seed_creation(metadata, correlation_id)
    Events.publish_ironmon_event("seed", event_data, batch: false)
  end

  defp handle_event_by_type("checkpoint", event_data, metadata, correlation_id) do
    Logger.info("IronMON checkpoint cleared",
      service: "ironmon_tcp",
      correlation_id: correlation_id,
      checkpoint_id: metadata.id,
      checkpoint_name: metadata.name,
      seed: Map.get(metadata, :seed)
    )

    handle_checkpoint_recording(metadata, correlation_id)
    Events.publish_ironmon_event("checkpoint", event_data, batch: false)
  end

  defp handle_event_by_type("location", event_data, metadata, correlation_id) do
    Logger.debug("IronMON location changed",
      service: "ironmon_tcp",
      correlation_id: correlation_id,
      location_id: metadata.id
    )

    Events.publish_ironmon_event("location", event_data, batch: false)
  end

  defp handle_event_by_type("battle_start", event_data, metadata, correlation_id) do
    Logger.info("IronMON battle started",
      service: "ironmon_tcp",
      correlation_id: correlation_id,
      trainer: metadata.trainer,
      pokemon_count: length(metadata.pokemon)
    )

    Events.publish_ironmon_event("battle_start", event_data, batch: false)
  end

  defp handle_event_by_type("battle_end", event_data, metadata, correlation_id) do
    Logger.info("IronMON battle ended",
      service: "ironmon_tcp",
      correlation_id: correlation_id,
      result: metadata.result,
      pokemon_count: length(metadata.pokemon)
    )

    Events.publish_ironmon_event("battle_end", event_data, batch: false)
  end

  defp handle_event_by_type("pokemon_update", event_data, metadata, correlation_id) do
    Logger.debug("IronMON team updated",
      service: "ironmon_tcp",
      correlation_id: correlation_id,
      team_size: length(metadata.team)
    )

    Events.publish_ironmon_event("pokemon_update", event_data, batch: false)
  end

  defp handle_event_by_type("item_update", event_data, metadata, correlation_id) do
    Logger.debug("IronMON inventory updated",
      service: "ironmon_tcp",
      correlation_id: correlation_id,
      item_count: length(metadata.items)
    )

    Events.publish_ironmon_event("item_update", event_data, batch: false)
  end

  defp handle_event_by_type("stats_update", event_data, _metadata, correlation_id) do
    Logger.debug("IronMON stats updated",
      service: "ironmon_tcp",
      correlation_id: correlation_id
    )

    Events.publish_ironmon_event("stats_update", event_data, batch: false)
  end

  defp handle_event_by_type("error", event_data, metadata, correlation_id) do
    Logger.warning("IronMON error received",
      service: "ironmon_tcp",
      correlation_id: correlation_id,
      error_code: metadata.code,
      error_message: metadata.message
    )

    Events.publish_ironmon_event("error", event_data, batch: false)
  end

  defp handle_event_by_type("heartbeat", _event_data, _metadata, correlation_id) do
    Logger.debug("IronMON heartbeat",
      service: "ironmon_tcp",
      correlation_id: correlation_id
    )

    # Don't publish heartbeats to avoid flooding the event stream
    :ok
  end

  defp handle_seed_creation(metadata, correlation_id) do
    # Get the first (and currently only) challenge
    challenge_id =
      case Server.Ironmon.list_challenges() do
        [challenge | _] ->
          challenge.id

        [] ->
          Logger.error("No IronMON challenges found",
            service: "ironmon_tcp",
            correlation_id: correlation_id
          )

          nil
      end

    if challenge_id do
      # Use the seed count from IronMON as the seed ID
      case Server.Ironmon.RunTracker.new_seed(challenge_id, metadata.count) do
        {:ok, seed_id} ->
          Logger.info("IronMON attempt started",
            service: "ironmon_tcp",
            correlation_id: correlation_id,
            seed_id: seed_id,
            seed_count: metadata.count
          )

        {:error, reason} ->
          Logger.error("Failed to create IronMON seed",
            service: "ironmon_tcp",
            correlation_id: correlation_id,
            error: inspect(reason)
          )
      end
    end
  end

  defp handle_checkpoint_recording(metadata, correlation_id) do
    # Record checkpoint result (always true since we only get notified when cleared)
    case Server.Ironmon.RunTracker.record_checkpoint(metadata.name, true) do
      :ok ->
        Logger.debug("Checkpoint recorded",
          service: "ironmon_tcp",
          correlation_id: correlation_id,
          checkpoint_name: metadata.name
        )

      {:error, reason} ->
        Logger.error("Failed to record checkpoint",
          service: "ironmon_tcp",
          correlation_id: correlation_id,
          checkpoint_name: metadata.name,
          error: inspect(reason)
        )
    end
  end
end
