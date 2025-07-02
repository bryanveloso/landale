defmodule Server.Telemetry do
  @moduledoc """
  Telemetry integration for Server application.

  Provides custom telemetry measurements and events for monitoring
  OBS connections, Twitch EventSub subscriptions, and system health.
  """

  require Logger

  @doc """
  Measures OBS service status and emits telemetry events.
  """
  def measure_obs_status do
    # Only measure if OBS service is started
    if Process.whereis(Server.Services.OBS) do
      case Server.Services.OBS.get_status() do
        {:ok, status} ->
          # Emit connection status
          connection_value = if status.connected, do: 1, else: 0

          :telemetry.execute([:server, :obs, :connection, :status], %{value: connection_value}, %{
            state: status.connection_state
          })

          # Get detailed state for additional metrics
          state = Server.Services.OBS.get_state()

          # Emit streaming status
          streaming_value = if state.streaming.active, do: 1, else: 0
          :telemetry.execute([:server, :obs, :streaming, :status], %{value: streaming_value}, %{})

          # Emit recording status
          recording_value = if state.recording.active, do: 1, else: 0
          :telemetry.execute([:server, :obs, :recording, :status], %{value: recording_value}, %{})

        {:error, _reason} ->
          :telemetry.execute([:server, :obs, :connection, :status], %{value: 0}, %{state: "error"})
      end
    else
      # Service not started yet, emit unavailable status
      :telemetry.execute([:server, :obs, :connection, :status], %{value: 0}, %{state: "service_not_started"})
    end
  end

  @doc """
  Measures Twitch service status and emits telemetry events.
  """
  def measure_twitch_status do
    # Only measure if Twitch service is started
    if Process.whereis(Server.Services.Twitch) do
      case Server.Services.Twitch.get_status() do
        {:ok, status} ->
          # Emit connection status
          connection_value = if status.connected, do: 1, else: 0

          :telemetry.execute([:server, :twitch, :connection, :status], %{value: connection_value}, %{
            state: status.connection_state
          })

          # Emit subscription metrics
          :telemetry.execute([:server, :twitch, :subscriptions, :active], %{value: status.subscription_count}, %{})
          :telemetry.execute([:server, :twitch, :subscriptions, :cost], %{value: status.subscription_cost}, %{})

        {:error, _reason} ->
          :telemetry.execute([:server, :twitch, :connection, :status], %{value: 0}, %{state: "error"})
      end
    else
      # Service not started yet, emit unavailable status
      :telemetry.execute([:server, :twitch, :connection, :status], %{value: 0}, %{state: "service_not_started"})
    end
  end

  @doc """
  Measures overall system health and emits telemetry events.
  """
  def measure_system_health do
    # Measure memory usage
    memory_info = :erlang.memory()
    total_memory = memory_info[:total]
    process_memory = memory_info[:processes]
    ets_memory = memory_info[:ets]

    :telemetry.execute(
      [:server, :system, :memory],
      %{
        total: total_memory,
        processes: process_memory,
        ets: ets_memory
      },
      %{}
    )

    # Measure process count
    process_count = :erlang.system_info(:process_count)
    :telemetry.execute([:server, :system, :processes], %{count: process_count}, %{})

    # Measure service GenServer status
    measure_genserver_health()

    # Measure database connection pool usage
    measure_database_pool()

    # Measure ETS table metrics
    measure_ets_tables()

    # Measure scheduler utilization
    case :scheduler.sample_all() do
      {:scheduler_wall_time_all, scheduler_list} when is_list(scheduler_list) ->
        total_usage =
          Enum.reduce(scheduler_list, 0, fn
            {_id, usage, _}, acc -> acc + usage
            {_id, usage, _, _}, acc -> acc + usage
            _, acc -> acc
          end)

        avg_usage = total_usage / length(scheduler_list)
        :telemetry.execute([:server, :system, :scheduler_usage], %{average: avg_usage}, %{})

      _ ->
        # Skip measurement if scheduler data format is unexpected
        :ok
    end
  end

  @doc """
  Measures GenServer health for core services.
  """
  def measure_genserver_health do
    services = [
      {Server.Services.OBS, :obs},
      {Server.Services.Twitch, :twitch},
      {Server.Services.IronmonTCP, :ironmon_tcp},
      {Server.Services.Rainwave, :rainwave}
    ]

    Enum.each(services, fn {module, service_name} ->
      case Process.whereis(module) do
        nil ->
          :telemetry.execute([:server, :genserver, :status], %{value: 0}, %{service: service_name})

        pid when is_pid(pid) ->
          :telemetry.execute([:server, :genserver, :status], %{value: 1}, %{service: service_name})

          # Measure mailbox size
          {:message_queue_len, mailbox_size} = Process.info(pid, :message_queue_len)
          :telemetry.execute([:server, :genserver, :mailbox_size], %{size: mailbox_size}, %{service: service_name})

          # Measure memory usage
          {:memory, memory_usage} = Process.info(pid, :memory)
          :telemetry.execute([:server, :genserver, :memory], %{bytes: memory_usage}, %{service: service_name})
      end
    end)
  end

  @doc """
  Measures database connection pool metrics.
  """
  def measure_database_pool do
    # Get pool status directly from DBConnection
    case DBConnection.status(Server.Repo) do
      :ok ->
        # Repo is running, emit basic health metric
        :telemetry.execute([:server, :database, :status], %{value: 1}, %{})

        # For more detailed pool metrics, we'd need to access internal pool state
        # For single-user system, basic connectivity is sufficient
        :ok

      _ ->
        :telemetry.execute([:server, :database, :status], %{value: 0}, %{})
    end
  rescue
    _ ->
      # Fallback measurement - check if repo process is alive
      repo_alive = if Process.whereis(Server.Repo), do: 1, else: 0
      :telemetry.execute([:server, :database, :status], %{value: repo_alive}, %{})
  end

  @doc """
  Measures ETS table metrics for performance monitoring.
  """
  def measure_ets_tables do
    # List all ETS tables owned by the application
    all_tables = :ets.all()

    app_tables =
      Enum.filter(all_tables, fn table ->
        try do
          info = :ets.info(table)
          owner = info[:owner]
          # Check if owner process is part of our application
          case Process.info(owner, :dictionary) do
            {:dictionary, dict} ->
              # Look for application context in process dictionary
              Enum.any?(dict, fn {key, _} ->
                is_atom(key) and Atom.to_string(key) =~ "server"
              end)

            _ ->
              false
          end
        rescue
          _ -> false
        end
      end)

    total_memory =
      Enum.reduce(app_tables, 0, fn table, acc ->
        case :ets.info(table, :memory) do
          :undefined -> acc
          memory when is_integer(memory) -> acc + memory * :erlang.system_info(:wordsize)
          _ -> acc
        end
      end)

    :telemetry.execute(
      [:server, :ets, :tables],
      %{
        count: length(app_tables),
        total_memory: total_memory
      },
      %{}
    )
  end

  @doc """
  Emits telemetry event for OBS connection attempts.
  """
  def obs_connection_attempt do
    :telemetry.execute([:server, :obs, :connection, :attempts], %{count: 1}, %{})
  end

  @doc """
  Emits telemetry event for successful OBS connections.
  """
  def obs_connection_success(duration_ms) do
    :telemetry.execute([:server, :obs, :connection, :successes], %{count: 1}, %{})
    :telemetry.execute([:server, :obs, :connection, :duration], %{duration: duration_ms}, %{result: "success"})
  end

  @doc """
  Emits telemetry event for failed OBS connections.
  """
  def obs_connection_failure(duration_ms, reason) do
    :telemetry.execute([:server, :obs, :connection, :failures], %{count: 1}, %{reason: reason})
    :telemetry.execute([:server, :obs, :connection, :duration], %{duration: duration_ms}, %{result: "failure"})
  end

  @doc """
  Emits telemetry event for OBS requests.
  """
  def obs_request(request_type, duration_ms, success?) do
    result = if success?, do: "success", else: "failure"

    :telemetry.execute([:server, :obs, :requests, :total], %{count: 1}, %{request_type: request_type})

    if success? do
      :telemetry.execute([:server, :obs, :requests, :success], %{count: 1}, %{request_type: request_type})
    else
      :telemetry.execute([:server, :obs, :requests, :failure], %{count: 1}, %{request_type: request_type})
    end

    :telemetry.execute([:server, :obs, :requests, :duration], %{duration: duration_ms}, %{
      request_type: request_type,
      result: result
    })
  end

  @doc """
  Emits telemetry event for Twitch connection attempts.
  """
  def twitch_connection_attempt do
    :telemetry.execute([:server, :twitch, :connection, :attempts], %{count: 1}, %{})
  end

  @doc """
  Emits telemetry event for successful Twitch connections.
  """
  def twitch_connection_success(duration_ms) do
    :telemetry.execute([:server, :twitch, :connection, :successes], %{count: 1}, %{})
    :telemetry.execute([:server, :twitch, :connection, :duration], %{duration: duration_ms}, %{result: "success"})
  end

  @doc """
  Emits telemetry event for failed Twitch connections.
  """
  def twitch_connection_failure(duration_ms, reason) do
    :telemetry.execute([:server, :twitch, :connection, :failures], %{count: 1}, %{reason: reason})
    :telemetry.execute([:server, :twitch, :connection, :duration], %{duration: duration_ms}, %{result: "failure"})
  end

  @doc """
  Emits telemetry event for Twitch subscription creation.
  """
  def twitch_subscription_created(event_type) do
    :telemetry.execute([:server, :twitch, :subscriptions, :created], %{count: 1}, %{event_type: event_type})
  end

  @doc """
  Emits telemetry event for Twitch subscription deletion.
  """
  def twitch_subscription_deleted(event_type) do
    :telemetry.execute([:server, :twitch, :subscriptions, :deleted], %{count: 1}, %{event_type: event_type})
  end

  @doc """
  Emits telemetry event for failed Twitch subscription creation.
  """
  def twitch_subscription_failed(event_type, reason) do
    :telemetry.execute([:server, :twitch, :subscriptions, :failed], %{count: 1}, %{
      event_type: event_type,
      reason: reason
    })
  end

  @doc """
  Emits telemetry event for received Twitch events.
  """
  def twitch_event_received(event_type) do
    :telemetry.execute([:server, :twitch, :events, :received], %{count: 1}, %{event_type: event_type})
  end

  @doc """
  Emits telemetry event for OAuth token refresh attempts.
  """
  def twitch_oauth_refresh_attempt do
    :telemetry.execute([:server, :twitch, :oauth, :refresh, :attempts], %{count: 1}, %{})
  end

  @doc """
  Emits telemetry event for successful OAuth token refresh.
  """
  def twitch_oauth_refresh_success do
    :telemetry.execute([:server, :twitch, :oauth, :refresh, :successes], %{count: 1}, %{})
  end

  @doc """
  Emits telemetry event for failed OAuth token refresh.
  """
  def twitch_oauth_refresh_failure(reason) do
    :telemetry.execute([:server, :twitch, :oauth, :refresh, :failures], %{count: 1}, %{reason: reason})
  end

  @doc """
  Emits telemetry event for published events.
  """
  def event_published(event_type, topic) do
    :telemetry.execute([:server, :events, :published], %{count: 1}, %{
      event_type: event_type,
      topic: topic
    })
  end

  @doc """
  Emits telemetry event for health check requests.
  """
  def health_check(endpoint, duration_ms, status) do
    :telemetry.execute([:server, :health, :checks], %{count: 1}, %{endpoint: endpoint})
    :telemetry.execute([:server, :health, :response_time], %{duration: duration_ms}, %{endpoint: endpoint})

    # Emit service health status
    status_value = if status == "healthy", do: 1, else: 0
    :telemetry.execute([:server, :health, :status], %{value: status_value}, %{service: endpoint})
  end
end
