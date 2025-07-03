defmodule Server.Transcription.TranscriptionTest do
  use Server.DataCase, async: true

  alias Server.Transcription.Transcription

  describe "changeset/2" do
    test "valid changeset with required fields" do
      attrs = %{
        timestamp: ~U[2024-01-01 12:00:00.000000Z],
        duration: 2.5,
        text: "Hello world"
      }

      changeset = Transcription.changeset(%Transcription{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :timestamp) == ~U[2024-01-01 12:00:00.000000Z]
      assert get_change(changeset, :duration) == 2.5
      assert get_change(changeset, :text) == "Hello world"
    end

    test "valid changeset with all fields" do
      attrs = %{
        timestamp: ~U[2024-01-01 12:00:00.000000Z],
        duration: 2.5,
        text: "Hello world",
        source_id: "phononmaser",
        stream_session_id: "stream_2024_01_01",
        confidence: 0.95,
        metadata: %{"language" => "en", "model" => "whisper"}
      }

      changeset = Transcription.changeset(%Transcription{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :source_id) == "phononmaser"
      assert get_change(changeset, :stream_session_id) == "stream_2024_01_01"
      assert get_change(changeset, :confidence) == 0.95
      assert get_change(changeset, :metadata) == %{"language" => "en", "model" => "whisper"}
    end

    test "invalid changeset when missing required fields" do
      changeset = Transcription.changeset(%Transcription{}, %{})

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).timestamp
      assert "can't be blank" in errors_on(changeset).duration
      assert "can't be blank" in errors_on(changeset).text
    end

    test "validates duration is positive" do
      attrs = %{
        timestamp: ~U[2024-01-01 12:00:00.000000Z],
        duration: -1.0,
        text: "Hello world"
      }

      changeset = Transcription.changeset(%Transcription{}, attrs)

      refute changeset.valid?
      assert "must be greater than 0.0" in errors_on(changeset).duration
    end

    test "validates duration is not zero" do
      attrs = %{
        timestamp: ~U[2024-01-01 12:00:00.000000Z],
        duration: 0.0,
        text: "Hello world"
      }

      changeset = Transcription.changeset(%Transcription{}, attrs)

      refute changeset.valid?
      assert "must be greater than 0.0" in errors_on(changeset).duration
    end

    test "validates confidence is between 0 and 1" do
      base_attrs = %{
        timestamp: ~U[2024-01-01 12:00:00.000000Z],
        duration: 2.5,
        text: "Hello world"
      }

      # Test negative confidence
      changeset1 = Transcription.changeset(%Transcription{}, Map.put(base_attrs, :confidence, -0.1))
      refute changeset1.valid?
      assert "must be greater than or equal to 0.0" in errors_on(changeset1).confidence

      # Test confidence > 1
      changeset2 = Transcription.changeset(%Transcription{}, Map.put(base_attrs, :confidence, 1.1))
      refute changeset2.valid?
      assert "must be less than or equal to 1.0" in errors_on(changeset2).confidence

      # Test boundary values
      changeset3 = Transcription.changeset(%Transcription{}, Map.put(base_attrs, :confidence, 0.0))
      assert changeset3.valid?

      changeset4 = Transcription.changeset(%Transcription{}, Map.put(base_attrs, :confidence, 1.0))
      assert changeset4.valid?
    end

    test "validates text length" do
      attrs = %{
        timestamp: ~U[2024-01-01 12:00:00.000000Z],
        duration: 2.5,
        text: String.duplicate("a", 10_001)
      }

      changeset = Transcription.changeset(%Transcription{}, attrs)

      refute changeset.valid?
      assert "should be at most 10000 character(s)" in errors_on(changeset).text
    end

    test "validates text is not empty string" do
      attrs = %{
        timestamp: ~U[2024-01-01 12:00:00.000000Z],
        duration: 2.5,
        text: ""
      }

      changeset = Transcription.changeset(%Transcription{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).text
    end

    test "validates text is not only whitespace" do
      attrs = %{
        timestamp: ~U[2024-01-01 12:00:00.000000Z],
        duration: 2.5,
        text: "   \n\t   "
      }

      changeset = Transcription.changeset(%Transcription{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).text
    end

    test "accepts text with whitespace" do
      attrs = %{
        timestamp: ~U[2024-01-01 12:00:00.000000Z],
        duration: 2.5,
        text: "  Hello world  "
      }

      changeset = Transcription.changeset(%Transcription{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :text) == "  Hello world  "
    end

    test "allows valid source_id formats" do
      base_attrs = %{
        timestamp: ~U[2024-01-01 12:00:00.000000Z],
        duration: 2.5,
        text: "Hello world"
      }

      valid_sources = ["phononmaser", "manual", "test_source", "source-123"]

      for source <- valid_sources do
        changeset = Transcription.changeset(%Transcription{}, Map.put(base_attrs, :source_id, source))
        assert changeset.valid?, "Expected #{source} to be valid"
      end
    end

    test "allows valid stream_session_id formats" do
      base_attrs = %{
        timestamp: ~U[2024-01-01 12:00:00.000000Z],
        duration: 2.5,
        text: "Hello world"
      }

      valid_sessions = ["stream_2024_01_01", "session_abc123", "live_stream_20240101"]

      for session <- valid_sessions do
        changeset = Transcription.changeset(%Transcription{}, Map.put(base_attrs, :stream_session_id, session))
        assert changeset.valid?, "Expected #{session} to be valid"
      end
    end

    test "handles metadata as map" do
      attrs = %{
        timestamp: ~U[2024-01-01 12:00:00.000000Z],
        duration: 2.5,
        text: "Hello world",
        metadata: %{
          "language" => "en",
          "model_version" => "whisper-large-v2",
          "processing_time" => 1.23,
          "segments" => [
            %{"start" => 0.0, "end" => 2.5, "text" => "Hello world"}
          ]
        }
      }

      changeset = Transcription.changeset(%Transcription{}, attrs)

      assert changeset.valid?
      metadata = get_change(changeset, :metadata)
      assert metadata["language"] == "en"
      assert metadata["model_version"] == "whisper-large-v2"
      assert metadata["processing_time"] == 1.23
      assert is_list(metadata["segments"])
    end

    test "defaults metadata to empty map when not provided" do
      attrs = %{
        timestamp: ~U[2024-01-01 12:00:00.000000Z],
        duration: 2.5,
        text: "Hello world"
      }

      changeset = Transcription.changeset(%Transcription{}, attrs)

      assert changeset.valid?
      # The default should be set by the database, not the changeset
      refute Map.has_key?(changeset.changes, :metadata)
    end

    test "does not generate id in changeset (handled by database)" do
      attrs = %{
        timestamp: ~U[2024-01-01 12:00:00.000000Z],
        duration: 2.5,
        text: "Hello world"
      }

      changeset = Transcription.changeset(%Transcription{}, attrs)

      assert changeset.valid?
      refute Map.has_key?(changeset.changes, :id)
    end

    test "accepts updates to existing record" do
      existing_transcription = %Transcription{
        id: Ecto.UUID.generate(),
        timestamp: ~U[2024-01-01 12:00:00.000000Z],
        duration: 2.5,
        text: "Original text"
      }

      attrs = %{text: "Updated text"}

      changeset = Transcription.changeset(existing_transcription, attrs)

      assert changeset.valid?
      assert get_change(changeset, :text) == "Updated text"
    end
  end

  describe "type specifications" do
    test "struct has correct type" do
      transcription = %Transcription{}

      # These should compile without warnings when using dialyzer
      assert is_struct(transcription, Transcription)
      assert is_binary(transcription.id) or is_nil(transcription.id)
      assert is_struct(transcription.timestamp, DateTime) or is_nil(transcription.timestamp)
      assert is_float(transcription.duration) or is_nil(transcription.duration)
      assert is_binary(transcription.text) or is_nil(transcription.text)
      assert is_binary(transcription.source_id) or is_nil(transcription.source_id)
      assert is_binary(transcription.stream_session_id) or is_nil(transcription.stream_session_id)
      assert is_float(transcription.confidence) or is_nil(transcription.confidence)
      assert is_map(transcription.metadata)
    end
  end
end
