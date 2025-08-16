defmodule Server.Transcription.AnalyticsTest do
  use Server.DataCase, async: true

  alias Server.Repo
  alias Server.Transcription.Analytics
  alias Server.Transcription.Transcription

  describe "gather_analytics/0" do
    test "returns analytics with no transcriptions" do
      analytics = Analytics.gather_analytics()

      assert analytics.total_transcriptions_24h == 0
      assert analytics.confidence.average == 0.0
      assert analytics.duration.total_seconds == 0.0
      assert analytics.trends.confidence_trend == "stable"
      assert analytics.trends.quality_trend == "stable"
      assert is_number(analytics.timestamp)
    end

    test "calculates analytics with transcription data" do
      # Create test transcriptions spanning the 24-hour window
      # First half: -24 to -12 hours (higher confidence)
      _transcription1 =
        %Transcription{
          text: "Hello world test",
          duration: 2.5,
          confidence: 0.9,
          timestamp: DateTime.add(DateTime.utc_now(), -18, :hour)
        }
        |> Repo.insert!()

      # Second half: -12 to 0 hours (lower confidence)
      _transcription2 =
        %Transcription{
          text: "Another test transcription",
          duration: 3.2,
          confidence: 0.7,
          timestamp: DateTime.add(DateTime.utc_now(), -6, :hour)
        }
        |> Repo.insert!()

      analytics = Analytics.gather_analytics()

      assert analytics.total_transcriptions_24h == 2
      assert analytics.confidence.average == 0.8
      assert analytics.confidence.min == 0.7
      assert analytics.confidence.max == 0.9
      assert analytics.confidence.distribution.high == 1
      assert analytics.confidence.distribution.medium == 1
      assert analytics.confidence.distribution.low == 0
      assert analytics.duration.total_seconds == 5.7
      assert analytics.duration.average_duration == 2.85
      assert analytics.duration.total_text_length == 42
      # 0.9 -> 0.7 is declining
      assert analytics.trends.confidence_trend == "declining"
      # Last quarter avg confidence < 0.7
      assert analytics.trends.quality_trend == "needs_attention"
    end

    test "handles confidence trend calculation" do
      # Create transcriptions with improving confidence over time
      %Transcription{
        text: "First transcription",
        duration: 1.0,
        confidence: 0.6,
        timestamp: DateTime.add(DateTime.utc_now(), -4, :hour)
      }
      |> Repo.insert!()

      %Transcription{
        text: "Second transcription",
        duration: 1.0,
        confidence: 0.8,
        timestamp: DateTime.add(DateTime.utc_now(), -2, :hour)
      }
      |> Repo.insert!()

      %Transcription{
        text: "Third transcription",
        duration: 1.0,
        confidence: 0.9,
        timestamp: DateTime.add(DateTime.utc_now(), -1, :hour)
      }
      |> Repo.insert!()

      analytics = Analytics.gather_analytics()

      assert analytics.trends.confidence_trend == "improving"
    end

    test "calculates hourly volume correctly" do
      # Create transcriptions in different hours
      %Transcription{
        text: "Test transcription 1",
        duration: 1.0,
        timestamp: DateTime.add(DateTime.utc_now(), -2, :hour)
      }
      |> Repo.insert!()

      %Transcription{
        text: "Test transcription 2",
        duration: 1.0,
        timestamp: DateTime.add(DateTime.utc_now(), -2, :hour)
      }
      |> Repo.insert!()

      %Transcription{
        text: "Test transcription 3",
        duration: 1.0,
        timestamp: DateTime.add(DateTime.utc_now(), -1, :hour)
      }
      |> Repo.insert!()

      analytics = Analytics.gather_analytics()

      assert length(analytics.trends.hourly_volume) == 24

      # Check that some buckets have the correct counts
      volume_counts = Enum.map(analytics.trends.hourly_volume, & &1.count)
      assert Enum.sum(volume_counts) == 3
    end
  end
end
