defmodule Server.Transcription.BroadcasterTest do
  use ExUnit.Case, async: true

  alias Server.Transcription.Broadcaster

  describe "broadcast_transcription/1" do
    test "rejects nil transcription" do
      assert {:error, :invalid_transcription} = Broadcaster.broadcast_transcription(nil)
    end

    test "rejects transcription missing required fields" do
      incomplete_transcription = %{
        id: "test-id",
        # Missing timestamp and text
        duration: 1.5
      }

      assert {:error, {:missing_required_fields, fields}} =
               Broadcaster.broadcast_transcription(incomplete_transcription)

      assert :timestamp in fields
      assert :text in fields
    end

    test "rejects transcription with empty text" do
      transcription_with_empty_text = %{
        id: "test-id",
        timestamp: DateTime.utc_now(),
        text: "   ",
        duration: 1.5
      }

      assert {:error, {:missing_required_fields, [:text]}} =
               Broadcaster.broadcast_transcription(transcription_with_empty_text)
    end

    test "successfully broadcasts valid transcription" do
      # Subscribe to PubSub to verify broadcasts
      Phoenix.PubSub.subscribe(Server.PubSub, "transcription:live")

      valid_transcription = %{
        id: "test-id",
        timestamp: DateTime.utc_now(),
        text: "Hello from broadcaster test",
        duration: 1.5,
        source_id: "test_source",
        stream_session_id: nil,
        confidence: 0.95
      }

      assert :ok = Broadcaster.broadcast_transcription(valid_transcription)

      # Verify broadcast was sent
      assert_receive {:new_transcription, event}
      assert event.id == "test-id"
      assert event.text == "Hello from broadcaster test"
      assert event.confidence == 0.95
    end

    test "broadcasts to both live and session channels when session_id present" do
      session_id = "test_session_123"

      # Subscribe to both channels
      Phoenix.PubSub.subscribe(Server.PubSub, "transcription:live")
      Phoenix.PubSub.subscribe(Server.PubSub, "transcription:session:#{session_id}")

      transcription_with_session = %{
        id: "test-id",
        timestamp: DateTime.utc_now(),
        text: "Session-specific transcription",
        duration: 2.0,
        source_id: "test_source",
        stream_session_id: session_id,
        confidence: 0.88
      }

      assert :ok = Broadcaster.broadcast_transcription(transcription_with_session)

      # Should receive message on both channels
      assert_receive {:new_transcription, live_event}
      assert_receive {:new_transcription, session_event}

      # Events should be identical
      assert live_event == session_event
      assert live_event.stream_session_id == session_id
      assert live_event.text == "Session-specific transcription"
    end

    test "transforms transcription struct correctly" do
      Phoenix.PubSub.subscribe(Server.PubSub, "transcription:live")

      transcription = %{
        id: "test-id",
        timestamp: ~U[2024-01-15 10:30:00Z],
        text: "Test transcription",
        duration: 3.5,
        source_id: "phononmaser",
        stream_session_id: "stream_20240115",
        confidence: 0.92
      }

      assert :ok = Broadcaster.broadcast_transcription(transcription)

      assert_receive {:new_transcription, event}

      # Verify all fields are correctly transformed
      assert event.id == "test-id"
      assert event.timestamp == ~U[2024-01-15 10:30:00Z]
      assert event.text == "Test transcription"
      assert event.duration == 3.5
      assert event.source_id == "phononmaser"
      assert event.stream_session_id == "stream_20240115"
      assert event.confidence == 0.92
      # correlation_id should be present (may be nil if no context)
      assert Map.has_key?(event, :correlation_id)
    end
  end
end
