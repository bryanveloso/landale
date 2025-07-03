defmodule Server.TranscriptionTest do
  use Server.DataCase, async: true

  alias Server.Transcription

  describe "list_transcriptions/1" do
    test "returns empty list when no transcriptions exist" do
      assert Transcription.list_transcriptions() == []
    end

    test "returns transcriptions ordered by timestamp desc" do
      older = insert_transcription(%{timestamp: ~U[2024-01-01 12:00:00.000000Z]})
      newer = insert_transcription(%{timestamp: ~U[2024-01-01 13:00:00.000000Z]})

      result = Transcription.list_transcriptions()

      assert length(result) == 2
      assert hd(result).id == newer.id
      assert List.last(result).id == older.id
    end

    test "respects limit option" do
      insert_transcription(%{text: "first"})
      insert_transcription(%{text: "second"})
      insert_transcription(%{text: "third"})

      result = Transcription.list_transcriptions(limit: 2)

      assert length(result) == 2
    end

    test "enforces maximum limit of 1000" do
      # Create a few transcriptions to test with
      for i <- 1..5 do
        insert_transcription(%{text: "transcription #{i}"})
      end

      result = Transcription.list_transcriptions(limit: 2000)

      # Should only return the actual number of records, not fail
      assert length(result) == 5
    end

    test "filters by stream_session_id" do
      session1_trans = insert_transcription(%{stream_session_id: "stream_2024_01_01"})
      _session2_trans = insert_transcription(%{stream_session_id: "stream_2024_01_02"})

      result = Transcription.list_transcriptions(stream_session_id: "stream_2024_01_01")

      assert length(result) == 1
      assert hd(result).id == session1_trans.id
    end
  end

  describe "get_transcription!/1" do
    test "returns transcription when it exists" do
      transcription = insert_transcription()

      result = Transcription.get_transcription!(transcription.id)

      assert result.id == transcription.id
      assert result.text == transcription.text
    end

    test "raises when transcription does not exist" do
      assert_raise Ecto.NoResultsError, fn ->
        Transcription.get_transcription!(Ecto.UUID.generate())
      end
    end
  end

  describe "create_transcription/1" do
    test "creates transcription with valid attributes" do
      attrs = %{
        timestamp: ~U[2024-01-01 12:00:00.000000Z],
        duration: 2.5,
        text: "Hello world",
        source_id: "phononmaser",
        stream_session_id: "stream_2024_01_01",
        confidence: 0.95,
        metadata: %{"language" => "en"}
      }

      assert {:ok, transcription} = Transcription.create_transcription(attrs)
      assert transcription.text == "Hello world"
      assert transcription.duration == 2.5
      assert transcription.confidence == 0.95
      assert transcription.metadata == %{"language" => "en"}
    end

    test "returns error with invalid attributes" do
      attrs = %{
        # Missing required fields
        text: "Hello"
      }

      assert {:error, %Ecto.Changeset{}} = Transcription.create_transcription(attrs)
    end

    test "validates duration is positive" do
      attrs = valid_transcription_attrs(%{duration: -1.0})

      assert {:error, changeset} = Transcription.create_transcription(attrs)
      assert "must be greater than 0.0" in errors_on(changeset).duration
    end

    test "validates confidence is between 0 and 1" do
      attrs = valid_transcription_attrs(%{confidence: 1.5})

      assert {:error, changeset} = Transcription.create_transcription(attrs)
      assert "must be less than or equal to 1.0" in errors_on(changeset).confidence
    end

    test "validates text length" do
      attrs = valid_transcription_attrs(%{text: String.duplicate("a", 10_001)})

      assert {:error, changeset} = Transcription.create_transcription(attrs)
      assert "should be at most 10000 character(s)" in errors_on(changeset).text
    end
  end

  describe "search_transcriptions/2" do
    test "returns empty list when no matches found" do
      insert_transcription(%{text: "Hello world"})

      result = Transcription.search_transcriptions("nonexistent")

      assert result == []
    end

    test "finds transcriptions containing search term" do
      match = insert_transcription(%{text: "Hello world programming"})
      _no_match = insert_transcription(%{text: "Goodbye universe"})

      result = Transcription.search_transcriptions("programming")

      assert length(result) == 1
      assert hd(result).id == match.id
    end

    test "search is case insensitive" do
      match = insert_transcription(%{text: "Hello WORLD"})

      result = Transcription.search_transcriptions("world")

      assert length(result) == 1
      assert hd(result).id == match.id
    end

    test "respects limit option" do
      for i <- 1..5 do
        insert_transcription(%{text: "hello world #{i}"})
      end

      result = Transcription.search_transcriptions("hello", limit: 3)

      assert length(result) == 3
    end

    test "filters by stream_session_id" do
      session1_match =
        insert_transcription(%{
          text: "hello world",
          stream_session_id: "stream_2024_01_01"
        })

      _session2_match =
        insert_transcription(%{
          text: "hello world",
          stream_session_id: "stream_2024_01_02"
        })

      result = Transcription.search_transcriptions("hello", stream_session_id: "stream_2024_01_01")

      assert length(result) == 1
      assert hd(result).id == session1_match.id
    end

    test "sanitizes SQL injection attempts" do
      insert_transcription(%{text: "safe content"})

      # These should not cause SQL errors
      result1 = Transcription.search_transcriptions("'; DROP TABLE transcriptions; --")
      result2 = Transcription.search_transcriptions("%'; OR '1'='1")

      assert result1 == []
      assert result2 == []
    end
  end

  describe "search_transcriptions_full_text/2" do
    test "falls back to basic search in test environment" do
      match = insert_transcription(%{text: "hello world"})

      result = Transcription.search_transcriptions_full_text("hello")

      assert length(result) == 1
      assert hd(result).id == match.id
    end
  end

  describe "get_session_transcriptions/2" do
    test "returns transcriptions for specific session" do
      session1_trans = insert_transcription(%{stream_session_id: "stream_2024_01_01"})
      _session2_trans = insert_transcription(%{stream_session_id: "stream_2024_01_02"})

      result = Transcription.get_session_transcriptions("stream_2024_01_01")

      assert length(result) == 1
      assert hd(result).id == session1_trans.id
    end

    test "returns empty list for non-existent session" do
      result = Transcription.get_session_transcriptions("nonexistent")

      assert result == []
    end
  end

  describe "list_transcriptions_by_time_range/3" do
    test "returns transcriptions within time range" do
      start_time = ~U[2024-01-01 12:00:00.000000Z]
      end_time = ~U[2024-01-01 14:00:00.000000Z]

      in_range = insert_transcription(%{timestamp: ~U[2024-01-01 13:00:00.000000Z]})
      _before = insert_transcription(%{timestamp: ~U[2024-01-01 11:00:00.000000Z]})
      _after = insert_transcription(%{timestamp: ~U[2024-01-01 15:00:00.000000Z]})

      result = Transcription.list_transcriptions_by_time_range(start_time, end_time)

      assert length(result) == 1
      assert hd(result).id == in_range.id
    end

    test "respects limit option" do
      start_time = ~U[2024-01-01 12:00:00.000000Z]
      end_time = ~U[2024-01-01 14:00:00.000000Z]

      for _i <- 1..5 do
        insert_transcription(%{timestamp: ~U[2024-01-01 13:00:00.000000Z]})
      end

      result = Transcription.list_transcriptions_by_time_range(start_time, end_time, limit: 3)

      assert length(result) == 3
    end
  end

  describe "get_recent_transcriptions/1" do
    test "returns recent transcriptions within time window" do
      recent =
        insert_transcription(%{
          timestamp: DateTime.add(DateTime.utc_now(), -30, :minute)
        })

      _old =
        insert_transcription(%{
          timestamp: DateTime.add(DateTime.utc_now(), -2, :hour)
        })

      result = Transcription.get_recent_transcriptions(60)

      assert length(result) == 1
      assert hd(result).id == recent.id
    end
  end

  describe "get_transcription_stats/0" do
    test "returns correct statistics" do
      session1_id = "stream_2024_01_01"
      session2_id = "stream_2024_01_02"

      # Create recent transcriptions (within last 24 hours)
      recent_time = DateTime.utc_now() |> DateTime.add(-1, :hour)
      insert_transcription(%{stream_session_id: session1_id, duration: 2.0, timestamp: recent_time})
      insert_transcription(%{stream_session_id: session1_id, duration: 3.0, timestamp: recent_time})
      insert_transcription(%{stream_session_id: session2_id, duration: 1.0, timestamp: recent_time})

      stats = Transcription.get_transcription_stats()

      assert stats.total_count == 3
      assert stats.unique_sessions == 2
      assert stats.total_duration == 6.0
    end

    test "handles empty database" do
      stats = Transcription.get_transcription_stats()

      assert stats.total_count == 0
      assert stats.unique_sessions == 0
      assert is_nil(stats.total_duration)
    end
  end

  # Helper functions

  defp valid_transcription_attrs(attrs \\ %{}) do
    %{
      timestamp: ~U[2024-01-01 12:00:00.000000Z],
      duration: 2.5,
      text: "Test transcription",
      source_id: "test_source"
    }
    |> Map.merge(attrs)
  end

  defp insert_transcription(attrs \\ %{}) do
    {:ok, transcription} =
      attrs
      |> valid_transcription_attrs()
      |> Transcription.create_transcription()

    transcription
  end
end
