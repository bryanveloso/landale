defmodule Server.PropertyTestHelpers do
  @moduledoc """
  Helper functions and generators for property-based testing with StreamData.

  This module provides common generators and utilities for testing
  GenServer state machines, connection logic, and protocol handling.
  """

  use ExUnitProperties

  @doc """
  Generate valid WebSocket connection states for OBS/Twitch services.
  """
  def connection_state_gen do
    one_of([
      constant(:disconnected),
      constant(:connecting),
      constant(:authenticating),
      constant(:ready),
      constant(:reconnecting),
      constant(:error)
    ])
  end

  @doc """
  Generate a sequence of connection events to test state transitions.
  """
  def connection_event_gen do
    one_of([
      constant({:connect, "ws://localhost:4455"}),
      constant({:connected, self()}),
      constant({:authenticate, %{password: "secret"}}),
      constant({:authenticated, %{version: "5.0.0"}}),
      constant({:disconnect, :normal}),
      constant({:error, :connection_lost}),
      constant({:error, :auth_failed}),
      constant({:reconnect, 1000})
    ])
  end

  @doc """
  Generate valid OBS request names.
  """
  def obs_request_name_gen do
    one_of([
      constant("GetVersion"),
      constant("GetSceneList"),
      constant("SetCurrentProgramScene"),
      constant("StartStream"),
      constant("StopStream"),
      constant("StartRecord"),
      constant("StopRecord"),
      constant("GetStreamStatus"),
      constant("GetRecordStatus")
    ])
  end

  @doc """
  Generate request IDs for tracking.
  """
  def request_id_gen do
    map(positive_integer(), &"req_#{&1}")
  end

  @doc """
  Generate a batch of events for testing event batching.
  """
  def event_batch_gen(max_size \\ 100) do
    list_of(event_gen(), min_length: 1, max_length: max_size)
  end

  @doc """
  Generate individual events.
  """
  def event_gen do
    map({string(:alphanumeric), positive_integer(), map_of(atom(:alphanumeric), term())}, fn {type, timestamp, data} ->
      %{
        type: type,
        timestamp: timestamp,
        data: data
      }
    end)
  end

  @doc """
  Generate correlation IDs.
  """
  def correlation_id_gen do
    string(:alphanumeric, min_length: 8, max_length: 8)
  end

  @doc """
  Generate circuit breaker configurations.
  """
  def circuit_breaker_config_gen do
    map({positive_integer(), positive_integer()}, fn {threshold, timeout} ->
      %{
        failure_threshold: min(threshold, 10),
        timeout_ms: min(timeout, 60_000)
      }
    end)
  end

  @doc """
  Property to test that state transitions are valid.
  """
  def valid_state_transition?(current_state, event) do
    case {current_state, event} do
      {:disconnected, {:connect, _}} -> true
      {:connecting, {:connected, _}} -> true
      {:connecting, {:error, _}} -> true
      {:connected, {:authenticate, _}} -> true
      {:authenticating, {:authenticated, _}} -> true
      {:authenticating, {:error, _}} -> true
      {:ready, {:disconnect, _}} -> true
      {:ready, {:error, _}} -> true
      {_, {:reconnect, _}} -> true
      _ -> false
    end
  end

  @doc """
  Generate a sequence of valid state transitions.
  """
  def valid_transition_sequence_gen(length \\ 10) do
    # Start with disconnected state
    bind(constant(:disconnected), fn initial_state ->
      generate_transitions(initial_state, length, [])
    end)
  end

  defp generate_transitions(_state, 0, acc), do: constant(Enum.reverse(acc))

  defp generate_transitions(state, remaining, acc) do
    valid_events = valid_events_for_state(state)

    if Enum.empty?(valid_events) do
      constant(Enum.reverse(acc))
    else
      bind(one_of(valid_events), fn event ->
        next_state = next_state(state, event)
        generate_transitions(next_state, remaining - 1, [{state, event, next_state} | acc])
      end)
    end
  end

  defp valid_events_for_state(state) do
    case state do
      :disconnected -> [constant({:connect, "ws://localhost:4455"})]
      :connecting -> [constant({:connected, self()}), constant({:error, :connection_failed})]
      :connected -> [constant({:authenticate, %{password: "secret"}})]
      :authenticating -> [constant({:authenticated, %{}}), constant({:error, :auth_failed})]
      :ready -> [constant({:disconnect, :normal}), constant({:error, :connection_lost})]
      :error -> [constant({:reconnect, 1000})]
      # reconnecting goes to disconnected via timeout, not directly to connecting
      :reconnecting -> []
    end
  end

  defp next_state(state, {event_type, _}) do
    case {state, event_type} do
      {:disconnected, :connect} -> :connecting
      {:connecting, :connected} -> :connected
      {:connecting, :error} -> :error
      {:connected, :authenticate} -> :authenticating
      {:authenticating, :authenticated} -> :ready
      {:authenticating, :error} -> :error
      {:ready, :disconnect} -> :disconnected
      {:ready, :error} -> :error
      {:error, :reconnect} -> :reconnecting
      # :reconnecting transitions to :disconnected on timeout
      {:reconnecting, :timeout} -> :disconnected
      _ -> state
    end
  end
end
