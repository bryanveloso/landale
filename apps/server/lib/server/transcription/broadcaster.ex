defmodule Server.Transcription.Broadcaster do
  @moduledoc """
  Dedicated broadcaster for transcription events.

  Handles the specialized broadcasting requirements for transcription data,
  including dual topic routing (live + session-specific) and data integrity
  validation for the caption overlay system.

  This module represents legitimate domain separation from the main event
  system due to transcription's specialized requirements:
  - Live caption streaming to OBS
  - Session-aware correlation for replay/analysis
  - High-frequency data optimized for TimescaleDB
  """

  require Logger

  @doc """
  Broadcasts a transcription to appropriate channels.

  Performs basic data integrity validation and broadcasts to:
  - `transcription:live` - All live transcription events
  - `transcription:session:{session_id}` - Session-specific events (if session_id present)

  ## Examples

      iex> broadcast_transcription(transcription)
      :ok

      iex> broadcast_transcription(nil)
      {:error, :invalid_transcription}
  """
  @spec broadcast_transcription(Server.Transcription.Transcription.t() | nil) :: :ok | {:error, atom()}
  def broadcast_transcription(nil) do
    Logger.warning("Attempted to broadcast nil transcription")
    {:error, :invalid_transcription}
  end

  def broadcast_transcription(transcription) do
    with :ok <- validate_transcription(transcription),
         transcription_event <- transform_to_event(transcription) do
      broadcast_to_live_channel(transcription_event)
      broadcast_to_session_channel(transcription_event)
      :ok
    else
      {:error, reason} ->
        Logger.warning("Failed to broadcast transcription",
          reason: reason,
          transcription_id: Map.get(transcription, :id)
        )

        {:error, reason}
    end
  end

  # Basic data integrity validation (not security - simple nil checks)
  defp validate_transcription(transcription) do
    required_fields = [:id, :timestamp, :text]

    missing_fields =
      required_fields
      |> Enum.filter(fn field ->
        value = Map.get(transcription, field)
        is_nil(value) or (is_binary(value) and String.trim(value) == "")
      end)

    case missing_fields do
      [] ->
        :ok

      fields ->
        {:error, {:missing_required_fields, fields}}
    end
  end

  # Transform transcription struct to event map for broadcasting
  defp transform_to_event(transcription) do
    %{
      id: transcription.id,
      correlation_id: Server.CorrelationId.get_logger_metadata(),
      timestamp: transcription.timestamp,
      duration: transcription.duration,
      text: transcription.text,
      source_id: transcription.source_id,
      stream_session_id: transcription.stream_session_id,
      confidence: transcription.confidence
    }
  end

  # Broadcast to the live transcription channel (always)
  defp broadcast_to_live_channel(transcription_event) do
    Phoenix.PubSub.broadcast(
      Server.PubSub,
      "transcription:live",
      {:new_transcription, transcription_event}
    )
  end

  # Broadcast to session-specific channel (if session_id exists)
  defp broadcast_to_session_channel(transcription_event) do
    if transcription_event.stream_session_id do
      Phoenix.PubSub.broadcast(
        Server.PubSub,
        "transcription:session:#{transcription_event.stream_session_id}",
        {:new_transcription, transcription_event}
      )
    end
  end
end
