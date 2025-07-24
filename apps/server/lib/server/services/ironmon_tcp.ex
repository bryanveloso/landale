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

  ## Events Published

  All processed messages are published via Phoenix.PubSub on the
  "ironmon:events" topic for consumption by the dashboard and overlays.
  """

  use Server.Service,
    service_name: "ironmon-tcp",
    behaviour: Server.Services.IronmonTCPBehaviour

  use Server.Service.StatusReporter

  @behaviour Server.ServiceBehaviour

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

  @impl Server.ServiceBehaviour
  def get_health do
    GenServer.call(__MODULE__, :get_health)
  end

  @impl Server.ServiceBehaviour
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
      cond do
        state[:listen_socket] == nil -> :unhealthy
        true -> :healthy
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
        socket: inspect(socket),
        data_size: byte_size(data),
        raw_data: inspect(data)
      )

      case handle_tcp_data(socket, data, state) do
        {:ok, new_state} ->
          {:noreply, new_state}
      end
    end)
  end

  @impl GenServer
  def handle_info({:tcp_closed, socket}, state) do
    Logger.info("Client disconnected", socket: inspect(socket))

    new_connections = Map.delete(state.connections, socket)
    {:noreply, %{state | connections: new_connections}}
  end

  @impl GenServer
  def handle_info({:tcp_error, socket, reason}, state) do
    Logger.warning("Socket error", error: inspect(reason), socket: inspect(socket))

    new_connections = Map.delete(state.connections, socket)
    {:noreply, %{state | connections: new_connections}}
  end

  @impl GenServer
  def handle_info({:tcp_accept, listen_socket, client_socket}, %{listen_socket: listen_socket} = state) do
    Logger.info("Client connected", socket: inspect(client_socket))

    # Accept the connection
    :gen_tcp.controlling_process(client_socket, self())
    :inet.setopts(client_socket, active: true)

    # Add to connections with empty buffer
    new_connections = Map.put(state.connections, client_socket, "")
    {:noreply, %{state | connections: new_connections}}
  end

  @impl GenServer
  def handle_info(message, state) do
    Logger.debug("Unhandled message received", message: inspect(message))
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
            # Start accepting connections
            spawn_link(fn -> accept_connections(listen_socket, self()) end)
            {:ok, %{state | listen_socket: listen_socket}}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, {:invalid_ip_address, reason}}
    end
  end

  defp accept_connections(listen_socket, server_pid) do
    case :gen_tcp.accept(listen_socket) do
      {:ok, client_socket} ->
        send(server_pid, {:tcp_accept, listen_socket, client_socket})
        accept_connections(listen_socket, server_pid)

      {:error, :closed} ->
        :ok

      {:error, reason} ->
        Logging.log_error("Connection accept failed", inspect(reason))
        accept_connections(listen_socket, server_pid)
    end
  end

  defp handle_tcp_data(socket, data, state) do
    # Get existing buffer for this socket
    buffer = Map.get(state.connections, socket, "")
    updated_buffer = buffer <> data

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
    case String.split(buffer, " ", parts: 2) do
      [length_str, rest] ->
        case Integer.parse(length_str) do
          {length, ""} when byte_size(rest) >= length ->
            # We have a complete message
            <<message::binary-size(length), remaining::binary>> = rest

            case process_message(message) do
              :ok ->
                Logger.debug("Message processed")

              {:error, reason} ->
                Logger.warning("Message processing failed",
                  error: inspect(reason)
                )
            end

            # Process any remaining messages
            process_messages(socket, remaining, state)

          {_length, ""} ->
            # Not enough data yet
            {buffer, state}

          :error ->
            Logging.log_error("Message length invalid", "parse failed", length_str: length_str)
            # Skip invalid data
            {rest, state}
        end

      [_] ->
        # No space found yet, need more data
        {buffer, state}
    end
  end

  defp process_message(message_str) do
    with {:ok, json} <- JSON.decode(message_str),
         {:ok, message} <- validate_message(json) do
      handle_ironmon_message(message)
    else
      {:error, _reason} ->
        {:error, "Invalid JSON or message format"}
    end
  end

  defp validate_message(%{"type" => type, "metadata" => metadata} = json)
       when is_non_struct_map(metadata) do
    case type do
      "init" ->
        validate_init_message(json)

      "seed" ->
        validate_seed_message(json)

      "checkpoint" ->
        validate_checkpoint_message(json)

      "location" ->
        validate_location_message(json)

      _ ->
        {:error, "Unknown message type: #{type}"}
    end
  end

  defp validate_message(_), do: {:error, "Invalid message format"}

  defp validate_init_message(%{"metadata" => %{"version" => version, "game" => game}})
       when is_binary(version) and is_integer(game) do
    if Map.has_key?(@games, game) do
      {:ok, %{type: "init", metadata: %{version: version, game: game}}}
    else
      {:error, "Invalid game ID: #{game}"}
    end
  end

  defp validate_init_message(_), do: {:error, "Invalid init message"}

  defp validate_seed_message(%{"metadata" => %{"count" => count}})
       when is_integer(count) do
    {:ok, %{type: "seed", metadata: %{count: count}}}
  end

  defp validate_seed_message(_), do: {:error, "Invalid seed message"}

  defp validate_checkpoint_message(%{"metadata" => metadata}) do
    with %{"id" => id, "name" => name} <- metadata,
         true <- is_integer(id) and is_binary(name) do
      seed = Map.get(metadata, "seed")
      validated_metadata = %{id: id, name: name}

      validated_metadata =
        if is_integer(seed),
          do: Map.put(validated_metadata, :seed, seed),
          else: validated_metadata

      {:ok, %{type: "checkpoint", metadata: validated_metadata}}
    else
      _ -> {:error, "Invalid checkpoint message"}
    end
  end

  defp validate_location_message(%{"metadata" => %{"id" => id}})
       when is_integer(id) do
    {:ok, %{type: "location", metadata: %{id: id}}}
  end

  defp validate_location_message(_), do: {:error, "Invalid location message"}

  defp handle_ironmon_message(%{type: type, metadata: metadata}) do
    correlation_id = CorrelationId.get_logger_metadata()

    event_data = %{
      type: type,
      metadata: metadata,
      source: "tcp",
      correlation_id: correlation_id,
      timestamp: System.system_time(:second)
    }

    Logger.info("Message processing started", type: type, metadata: metadata)

    case type do
      "init" ->
        game_name = Map.get(@games, metadata.game, "Unknown")
        Logger.info("Game initialized", version: metadata.version, game: game_name)
        Events.publish_ironmon_event(type, event_data, batch: false)

      "seed" ->
        Logger.debug("Seed count updated", count: metadata.count)
        # Create new seed in database (new attempt started)
        # Get the first (and currently only) challenge
        challenge_id =
          case Server.Ironmon.list_challenges() do
            [challenge | _] ->
              challenge.id

            [] ->
              Logger.error("No challenges found in database - cannot create seed")
              nil
          end

        if challenge_id do
          # Use the seed count from IronMON as the seed ID
          case Server.Ironmon.RunTracker.new_seed(challenge_id, metadata.count) do
            {:ok, seed_id} ->
              Logger.info("New IronMON attempt started", seed_id: seed_id, count: metadata.count)

            {:error, reason} ->
              Logger.error("Failed to create new seed", reason: inspect(reason))
          end
        end

        Events.publish_ironmon_event(type, event_data, batch: false)

      "checkpoint" ->
        Logger.info("Checkpoint cleared", id: metadata.id, name: metadata.name, seed: Map.get(metadata, :seed))
        # Record checkpoint result (always true since we only get notified when cleared)
        case Server.Ironmon.RunTracker.record_checkpoint(metadata.name, true) do
          :ok ->
            Logger.debug("Checkpoint recorded in database", name: metadata.name)

          {:error, reason} ->
            Logger.error("Failed to record checkpoint", name: metadata.name, reason: inspect(reason))
        end

        Events.publish_ironmon_event(type, event_data, batch: false)

      "location" ->
        Logger.debug("Location changed", id: metadata.id)
        Events.publish_ironmon_event(type, event_data, batch: false)
    end

    :ok
  end
end
