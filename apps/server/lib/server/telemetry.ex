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
  end

  @doc """
  Measures Twitch service status and emits telemetry events.
  """
  def measure_twitch_status do
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
  end

  @doc """
  Measures overall system health and emits telemetry events.
  """
  def measure_system_health do
    # Measure memory usage
    memory_info = :erlang.memory()
    total_memory = memory_info[:total]
    process_memory = memory_info[:processes]

    :telemetry.execute(
      [:server, :system, :memory],
      %{
        total: total_memory,
        processes: process_memory
      },
      %{}
    )

    # Measure process count
    process_count = :erlang.system_info(:process_count)
    :telemetry.execute([:server, :system, :processes], %{count: process_count}, %{})

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
