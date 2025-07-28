defmodule ServerWeb.TranscriptionChannelSubmitTest do
  use ServerWeb.ChannelCase, async: true
  alias ServerWeb.TranscriptionChannel
  alias Server.Transcription

  setup do
    # Create a test socket and join the channel
    {:ok, socket} = connect(ServerWeb.UserSocket, %{})
    {:ok, _, socket} = subscribe_and_join(socket, TranscriptionChannel, "transcription:live")

    {:ok, socket: socket}
  end

  describe "handle_in(\"submit_transcription\", _, socket)" do
    test "accepts valid transcription and broadcasts", %{socket: socket} do
      valid_payload = %{
        "timestamp" => "2024-01-01T00:00:00Z",
        "duration" => 1.5,
        "text" => "Hello from WebSocket",
        "source_id" => "phononmaser",
        "stream_session_id" => "stream_2024_01_01",
        "confidence" => 0.95,
        "metadata" => %{"language" => "en"}
      }

      # Subscribe to PubSub to receive broadcasts
      Phoenix.PubSub.subscribe(Server.PubSub, "transcription:live")

      # Push the message and expect a reply
      ref = push(socket, "submit_transcription", valid_payload)

      assert_reply ref, :ok, %{transcription_id: transcription_id}
      assert is_binary(transcription_id)

      # Verify the transcription was persisted
      transcription = Transcription.get_transcription!(transcription_id)
      assert transcription.text == "Hello from WebSocket"
      assert transcription.duration == 1.5
      assert transcription.source_id == "phononmaser"
      assert transcription.confidence == 0.95

      # Verify PubSub broadcast was sent
      assert_receive {:new_transcription, broadcast_payload}
      assert broadcast_payload.id == transcription_id
      assert broadcast_payload.text == "Hello from WebSocket"
    end

    test "accepts minimal valid payload", %{socket: socket} do
      minimal_payload = %{
        "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "duration" => 2.0,
        "text" => "Minimal transcription"
      }

      # Subscribe to PubSub to receive broadcasts
      Phoenix.PubSub.subscribe(Server.PubSub, "transcription:live")

      ref = push(socket, "submit_transcription", minimal_payload)

      assert_reply ref, :ok, %{transcription_id: transcription_id}
      assert is_binary(transcription_id)

      # Verify defaults were applied
      transcription = Transcription.get_transcription!(transcription_id)
      assert transcription.text == "Minimal transcription"
      assert is_nil(transcription.source_id)
      assert is_nil(transcription.confidence)

      # Verify PubSub broadcast was sent
      assert_receive {:new_transcription, broadcast_payload}
      assert broadcast_payload.text == "Minimal transcription"
    end

    test "rejects missing required fields", %{socket: socket} do
      invalid_payload = %{
        "text" => "Missing timestamp and duration"
      }

      ref = push(socket, "submit_transcription", invalid_payload)

      assert_reply ref, :error, %{errors: errors}

      # Check error format
      assert is_list(errors)
      assert length(errors) == 2

      error_fields = Enum.map(errors, & &1.field)
      assert "duration" in error_fields
      assert "timestamp" in error_fields
    end

    test "rejects empty text", %{socket: socket} do
      payload = %{
        "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "duration" => 1.0,
        "text" => ""
      }

      ref = push(socket, "submit_transcription", payload)

      assert_reply ref, :error, %{errors: errors}

      text_error = Enum.find(errors, &(&1.field == "text"))
      assert text_error
      assert "is required" in text_error.messages
    end

    test "rejects invalid timestamp format", %{socket: socket} do
      payload = %{
        "timestamp" => "not-a-timestamp",
        "duration" => 1.0,
        "text" => "Test"
      }

      ref = push(socket, "submit_transcription", payload)

      assert_reply ref, :error, %{errors: errors}

      timestamp_error = Enum.find(errors, &(&1.field == "timestamp"))
      assert timestamp_error
      assert "must be a valid ISO 8601 datetime" in timestamp_error.messages
    end

    test "rejects negative duration", %{socket: socket} do
      payload = %{
        "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "duration" => -1.0,
        "text" => "Test"
      }

      ref = push(socket, "submit_transcription", payload)

      assert_reply ref, :error, %{errors: errors}

      duration_error = Enum.find(errors, &(&1.field == "duration"))
      assert duration_error
      assert "must be greater than 0" in duration_error.messages
    end

    test "rejects text that is too long", %{socket: socket} do
      long_text = String.duplicate("a", 10_001)

      payload = %{
        "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "duration" => 1.0,
        "text" => long_text
      }

      ref = push(socket, "submit_transcription", payload)

      assert_reply ref, :error, %{errors: errors}

      text_error = Enum.find(errors, &(&1.field == "text"))
      assert text_error
      assert "is too long (maximum is 10000 characters)" in text_error.messages
    end

    test "rejects invalid confidence value", %{socket: socket} do
      payload = %{
        "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "duration" => 1.0,
        "text" => "Test",
        "confidence" => 1.5
      }

      ref = push(socket, "submit_transcription", payload)

      assert_reply ref, :error, %{errors: errors}

      confidence_error = Enum.find(errors, &(&1.field == "confidence"))
      assert confidence_error
      assert "must be between 0.0 and 1.0" in confidence_error.messages
    end

    test "handles multiple validation errors", %{socket: socket} do
      payload = %{
        "timestamp" => "invalid",
        "duration" => -1.0,
        "text" => "",
        "confidence" => 2.0
      }

      ref = push(socket, "submit_transcription", payload)

      assert_reply ref, :error, %{errors: errors}

      assert length(errors) >= 4
      error_fields = Enum.map(errors, & &1.field)
      assert "timestamp" in error_fields
      assert "duration" in error_fields
      assert "text" in error_fields
      assert "confidence" in error_fields
    end

    test "broadcasts to session-specific channel when session_id present", %{socket: socket} do
      # Subscribe to both channels via PubSub
      session_id = "stream_2024_01_01"
      Phoenix.PubSub.subscribe(Server.PubSub, "transcription:live")
      Phoenix.PubSub.subscribe(Server.PubSub, "transcription:session:#{session_id}")

      payload = %{
        "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "duration" => 1.0,
        "text" => "Session-specific transcription",
        "stream_session_id" => session_id
      }

      ref = push(socket, "submit_transcription", payload)

      assert_reply ref, :ok, %{transcription_id: _}

      # Should receive broadcast on both channels
      assert_receive {:new_transcription, broadcast_payload}
      assert broadcast_payload.text == "Session-specific transcription"

      # Should receive the same message again from session channel
      assert_receive {:new_transcription, session_broadcast}
      assert session_broadcast.text == "Session-specific transcription"
    end

    test "handles multiple submissions", %{socket: socket} do
      # Subscribe to receive broadcasts
      Phoenix.PubSub.subscribe(Server.PubSub, "transcription:live")

      # Submit 5 transcriptions
      transcription_ids =
        for i <- 1..5 do
          payload = %{
            "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
            "duration" => 1.0,
            "text" => "Test transcription #{i}"
          }

          ref = push(socket, "submit_transcription", payload)
          assert_reply ref, :ok, %{transcription_id: transcription_id}
          transcription_id
        end

      # Verify all transcriptions were created with unique IDs
      assert length(transcription_ids) == 5
      assert length(Enum.uniq(transcription_ids)) == 5

      # Verify all transcriptions were persisted
      for id <- transcription_ids do
        assert Transcription.get_transcription!(id)
      end

      # Verify we received broadcasts
      received_count =
        Enum.reduce_while(1..5, 0, fn _, count ->
          receive do
            {:new_transcription, _payload} -> {:cont, count + 1}
          after
            100 -> {:halt, count}
          end
        end)

      assert received_count == 5
    end
  end

  describe "handle_in(unknown_event, _, socket)" do
    test "returns error for unknown events", %{socket: socket} do
      ref = push(socket, "unknown_event", %{})

      assert_reply ref, :error, %{message: "Unknown command: unknown_event"}
    end
  end
end
