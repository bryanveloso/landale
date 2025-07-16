defmodule Server.Domains.EventSourcing do
  @moduledoc """
  Pure functional core for event sourcing logic.

  Contains no side effects - all functions are pure and deterministic.
  Handles event application, state projection, and event stream processing.

  Business rules:
  - Events are immutable and contain type, timestamp, and data
  - State is built by applying events in chronological order
  - Each event type has specific application logic
  - Event validation ensures structural integrity
  """

  @doc """
  Applies a single event to a state, returning the new state.

  Event structure:
  - type: atom representing the event type
  - timestamp: ISO8601 string timestamp
  - data: map containing event-specific data

  Supported event types:
  - :stream_online - sets stream status and metadata
  - :stream_offline - updates stream status to offline
  - :alert_created - adds a new alert to the alerts list
  - :alert_dismissed - removes an alert by ID
  """
  def apply_event(state, %{type: :stream_online, timestamp: timestamp, data: data}) do
    state
    |> Map.put(:status, :online)
    |> Map.put(:started_at, timestamp)
    |> Map.put(:title, Map.get(data, :title))
    |> Map.put(:game, Map.get(data, :game))
  end

  def apply_event(state, %{type: :stream_offline, timestamp: timestamp, data: _data}) do
    state
    |> Map.put(:status, :offline)
    |> Map.put(:ended_at, timestamp)
  end

  def apply_event(state, %{type: :alert_created, timestamp: _timestamp, data: data}) do
    alert = %{
      id: Map.get(data, :id, generate_id()),
      type: Map.get(data, :alert_type),
      priority: Map.get(data, :priority),
      message: Map.get(data, :message)
    }

    existing_alerts = Map.get(state, :alerts, [])
    Map.put(state, :alerts, [alert | existing_alerts])
  end

  def apply_event(state, %{type: :alert_dismissed, timestamp: _timestamp, data: %{alert_id: alert_id}}) do
    existing_alerts = Map.get(state, :alerts, [])
    updated_alerts = Enum.reject(existing_alerts, &(&1.id == alert_id))
    Map.put(state, :alerts, updated_alerts)
  end

  def apply_event(state, _unknown_event) do
    # Ignore unknown event types - this provides forward compatibility
    state
  end

  @doc """
  Projects a final state from a list of events by applying them in order.

  Takes an initial state and a chronologically ordered list of events,
  applying each event to build the final state.
  """
  def project_from_events(events, initial_state) do
    Enum.reduce(events, initial_state, fn event, acc_state ->
      apply_event(acc_state, event)
    end)
  end

  @doc """
  Validates an event structure for required fields and correct types.

  Returns :ok for valid events, {:error, reason} for invalid events.

  Required fields:
  - type: must be an atom
  - timestamp: must be a valid ISO8601 string
  - data: must be a map
  """
  def validate_event(event) do
    cond do
      not Map.has_key?(event, :type) ->
        {:error, :missing_type}

      not Map.has_key?(event, :timestamp) ->
        {:error, :missing_timestamp}

      not Map.has_key?(event, :data) ->
        {:error, :missing_data}

      not is_atom(event.type) ->
        {:error, :invalid_type}

      not is_binary(event.timestamp) ->
        {:error, :invalid_timestamp}

      not valid_iso8601?(event.timestamp) ->
        {:error, :invalid_timestamp}

      not is_map(event.data) ->
        {:error, :invalid_data}

      true ->
        :ok
    end
  end

  @doc """
  Filters events to return only those that occurred after the given timestamp.

  If since_timestamp is nil, returns all events.
  Events are compared using string comparison of ISO8601 timestamps.
  """
  def get_events_since(events, nil), do: events

  def get_events_since(events, since_timestamp) do
    Enum.filter(events, fn event ->
      event.timestamp > since_timestamp
    end)
  end

  # Private helper functions

  defp valid_iso8601?(timestamp) when is_binary(timestamp) do
    case DateTime.from_iso8601(timestamp) do
      {:ok, _dt, _offset} -> true
      {:error, _reason} -> false
    end
  end

  defp valid_iso8601?(_), do: false

  defp generate_id do
    # Simple UUID-like ID generation
    :crypto.strong_rand_bytes(16)
    |> Base.encode16(case: :lower)
    |> String.slice(0, 12)
  end
end
