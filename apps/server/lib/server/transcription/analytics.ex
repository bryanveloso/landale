defmodule Server.Transcription.Analytics do
  @moduledoc """
  Transcription analytics for monitoring accuracy and performance.

  Provides insights into:
  - Confidence score trends
  - Accuracy metrics
  - Whisper model performance
  - Error rates and patterns
  """

  alias Server.Repo
  alias Server.Transcription.Transcription
  import Ecto.Query

  # SQL fragment constants for maintainability
  @hour_bucket_fragment "time_bucket('1 hour', ?)"

  @doc """
  Gathers transcription analytics data for telemetry using TimescaleDB optimizations.
  Uses continuous aggregates when available for better performance.
  """
  @spec gather_analytics() :: map()
  def gather_analytics do
    now = DateTime.utc_now()
    twenty_four_hours_ago = DateTime.add(now, -24, :hour)

    # Try to use optimized queries first, fallback to standard queries
    {confidence_metrics, duration_metrics, hourly_volume} =
      if use_optimized_analytics?() do
        # Use continuous aggregates and optimized queries
        alias Server.Transcription.OptimizedAnalytics

        hourly_data = OptimizedAnalytics.get_hourly_metrics(twenty_four_hours_ago, now)
        confidence = calculate_confidence_from_aggregates(hourly_data)
        duration = calculate_duration_from_aggregates(hourly_data)

        {confidence, duration, format_hourly_volume(hourly_data)}
      else
        # Fallback to standard database queries
        confidence_metrics = calculate_confidence_metrics_db(twenty_four_hours_ago, now)
        duration_metrics = calculate_duration_metrics_db(twenty_four_hours_ago, now)
        hourly_volume = calculate_hourly_volume_db(now)

        {confidence_metrics, duration_metrics, hourly_volume}
      end

    %{
      timestamp: System.system_time(:millisecond),
      total_transcriptions_24h: confidence_metrics.total_count,
      confidence: Map.drop(confidence_metrics, [:total_count]),
      duration: duration_metrics,
      trends: %{
        confidence_trend: calculate_confidence_trend_db(twenty_four_hours_ago, now),
        hourly_volume: hourly_volume,
        quality_trend: determine_quality_trend_db(twenty_four_hours_ago, now)
      }
    }
  end

  # Check if optimized analytics are available
  defp use_optimized_analytics? do
    Application.get_env(:server, :timescaledb_enabled, false) &&
      Application.get_env(:server, :use_continuous_aggregates, true)
  end

  # Calculate confidence metrics from continuous aggregate data
  defp calculate_confidence_from_aggregates(hourly_data) when hourly_data == [], do: default_confidence_metrics()

  defp calculate_confidence_from_aggregates(hourly_data) do
    total_count = Enum.reduce(hourly_data, 0, &(&1["count"] + &2))

    {sum_confidence, high, medium, low} =
      Enum.reduce(hourly_data, {0, 0, 0, 0}, fn data, {sum, h, m, l} ->
        weighted_confidence = (data["avg_confidence"] || 0) * data["count"]

        {
          sum + weighted_confidence,
          h + (data["high_confidence_count"] || 0),
          m + (data["medium_confidence_count"] || 0),
          l + (data["low_confidence_count"] || 0)
        }
      end)

    avg_confidence = if total_count > 0, do: sum_confidence / total_count, else: 0.0

    %{
      total_count: total_count,
      average: Float.round(avg_confidence, 3),
      min:
        Enum.min_by(hourly_data, & &1["min_confidence"], fn -> %{"min_confidence" => 0} end)["min_confidence"]
        |> Float.round(3),
      max:
        Enum.max_by(hourly_data, & &1["max_confidence"], fn -> %{"max_confidence" => 0} end)["max_confidence"]
        |> Float.round(3),
      distribution: %{
        high: high,
        medium: medium,
        low: low
      }
    }
  end

  defp default_confidence_metrics do
    %{
      total_count: 0,
      average: 0.0,
      min: 0.0,
      max: 0.0,
      distribution: %{high: 0, medium: 0, low: 0}
    }
  end

  # Calculate duration metrics from continuous aggregate data
  defp calculate_duration_from_aggregates([]), do: %{total_seconds: 0.0, average_duration: 0.0, total_text_length: 0}

  defp calculate_duration_from_aggregates(hourly_data) do
    total_duration = Enum.reduce(hourly_data, 0, &((&1["total_duration"] || 0) + &2))
    total_count = Enum.reduce(hourly_data, 0, &(&1["count"] + &2))

    %{
      total_seconds: Float.round(total_duration, 1),
      average_duration: Float.round(if(total_count > 0, do: total_duration / total_count, else: 0.0), 2),
      # Not available in hourly aggregates, would need daily
      total_text_length: 0
    }
  end

  # Format hourly volume data from aggregates
  defp format_hourly_volume(hourly_data) do
    Enum.map(hourly_data, fn data ->
      %{
        hour: DateTime.to_iso8601(data["hour"]),
        count: data["count"] || 0
      }
    end)
  end

  # Database-optimized analytics functions using TimescaleDB time_bucket

  defp calculate_confidence_metrics_db(start_time, end_time) do
    result =
      from(t in Transcription,
        where: t.timestamp >= ^start_time and t.timestamp <= ^end_time,
        select: %{
          total_count: count(t.id),
          avg_confidence: avg(t.confidence),
          min_confidence: min(t.confidence),
          max_confidence: max(t.confidence),
          high_confidence: count(fragment("CASE WHEN ? >= 0.8 THEN 1 END", t.confidence)),
          medium_confidence: count(fragment("CASE WHEN ? >= 0.6 AND ? < 0.8 THEN 1 END", t.confidence, t.confidence)),
          low_confidence: count(fragment("CASE WHEN ? < 0.6 THEN 1 END", t.confidence))
        }
      )
      |> Repo.one()

    case result do
      %{total_count: 0} ->
        %{
          total_count: 0,
          average: 0.0,
          min: 0.0,
          max: 0.0,
          distribution: %{high: 0, medium: 0, low: 0}
        }

      r ->
        %{
          total_count: r.total_count,
          average: Float.round(r.avg_confidence || 0.0, 3),
          min: Float.round(r.min_confidence || 0.0, 3),
          max: Float.round(r.max_confidence || 0.0, 3),
          distribution: %{
            high: r.high_confidence,
            medium: r.medium_confidence,
            low: r.low_confidence
          }
        }
    end
  end

  defp calculate_duration_metrics_db(start_time, end_time) do
    result =
      from(t in Transcription,
        where: t.timestamp >= ^start_time and t.timestamp <= ^end_time,
        select: %{
          total_duration: sum(t.duration),
          avg_duration: avg(t.duration),
          total_text_length: sum(fragment("length(?)", t.text)),
          total_count: count(t.id)
        }
      )
      |> Repo.one()

    case result do
      %{total_count: 0} ->
        %{
          total_seconds: 0.0,
          average_duration: 0.0,
          total_text_length: 0
        }

      r ->
        %{
          total_seconds: Float.round(r.total_duration || 0.0, 1),
          average_duration: Float.round(r.avg_duration || 0.0, 2),
          total_text_length: r.total_text_length || 0
        }
    end
  end

  defp calculate_hourly_volume_db(now) do
    if Application.get_env(:server, :timescaledb_enabled, false) do
      calculate_hourly_volume_timescaledb(now)
    else
      calculate_hourly_volume_fallback(now)
    end
  end

  defp calculate_hourly_volume_timescaledb(now) do
    # Use TimescaleDB time_bucket for efficient hourly aggregation
    twenty_four_hours_ago = DateTime.add(now, -24, :hour)

    from(t in Transcription,
      where: t.timestamp >= ^twenty_four_hours_ago,
      group_by: fragment(@hour_bucket_fragment, t.timestamp),
      select: %{
        hour: fragment(@hour_bucket_fragment, t.timestamp),
        count: count(t.id)
      },
      order_by: [asc: fragment(@hour_bucket_fragment, t.timestamp)]
    )
    |> Repo.all()
    |> Enum.map(fn %{hour: hour, count: count} ->
      # Convert NaiveDateTime from time_bucket to DateTime
      datetime =
        case hour do
          %NaiveDateTime{} = naive -> DateTime.from_naive!(naive, "Etc/UTC")
          %DateTime{} = dt -> dt
        end

      %{
        hour: DateTime.to_iso8601(datetime),
        count: count
      }
    end)
  end

  defp calculate_hourly_volume_fallback(now) do
    # Standard PostgreSQL approach using generate_series to create hourly buckets in database
    twenty_four_hours_ago = DateTime.add(now, -24, :hour)

    # Use PostgreSQL generate_series to create all 24 hourly buckets and left join actual data
    # This generates the time buckets directly in the database instead of application memory
    from(
      hour_bucket in fragment(
        """
          SELECT generate_series(
            date_trunc('hour', ?::timestamp),
            date_trunc('hour', ?::timestamp) + interval '23 hours',
            interval '1 hour'
          ) as hour
        """,
        ^twenty_four_hours_ago,
        ^twenty_four_hours_ago
      ),
      left_join: t in Transcription,
      on:
        fragment("date_trunc('hour', ?)", t.timestamp) == hour_bucket.hour and
          t.timestamp >= ^twenty_four_hours_ago,
      group_by: hour_bucket.hour,
      select: %{
        hour: hour_bucket.hour,
        count: count(t.id)
      },
      order_by: [asc: hour_bucket.hour]
    )
    |> Repo.all()
    |> Enum.map(fn %{hour: hour, count: count} ->
      # Convert NaiveDateTime to DateTime for consistent API
      datetime = DateTime.from_naive!(hour, "Etc/UTC")

      %{
        hour: DateTime.to_iso8601(datetime),
        count: count
      }
    end)
  end

  defp calculate_confidence_trend_db(start_time, end_time) do
    # Use database aggregations to calculate trend without loading data into memory
    # Split time period into two halves and calculate averages using SQL
    total_duration = DateTime.diff(end_time, start_time, :microsecond)
    mid_time = DateTime.add(start_time, div(total_duration, 2), :microsecond)

    # Get first half average confidence using database aggregation
    first_half_result =
      from(t in Transcription,
        where: t.timestamp >= ^start_time and t.timestamp < ^mid_time,
        select: %{
          avg_confidence: avg(t.confidence),
          count: count(t.id)
        }
      )
      |> Repo.one()

    # Get second half average confidence using database aggregation
    second_half_result =
      from(t in Transcription,
        where: t.timestamp >= ^mid_time and t.timestamp <= ^end_time,
        select: %{
          avg_confidence: avg(t.confidence),
          count: count(t.id)
        }
      )
      |> Repo.one()

    total_count = (first_half_result.count || 0) + (second_half_result.count || 0)

    case total_count do
      count when count < 2 ->
        "stable"

      _ ->
        first_avg = first_half_result.avg_confidence || 0.0
        second_avg = second_half_result.avg_confidence || 0.0

        cond do
          second_avg > first_avg + 0.05 -> "improving"
          second_avg < first_avg - 0.05 -> "declining"
          true -> "stable"
        end
    end
  end

  defp determine_quality_trend_db(start_time, end_time) do
    # Use database aggregations to analyze recent quality without loading data into memory
    # First get total count to determine how many records represent the recent quarter
    total_count_result =
      from(t in Transcription,
        where: t.timestamp >= ^start_time and t.timestamp <= ^end_time,
        select: count(t.id)
      )
      |> Repo.one()

    case total_count_result do
      0 ->
        "stable"

      total_count ->
        quarter_size = max(1, div(total_count, 4))

        # Use subquery to get the most recent records, then aggregate
        recent_transcriptions =
          from(t in Transcription,
            where: t.timestamp >= ^start_time and t.timestamp <= ^end_time,
            order_by: [desc: t.timestamp],
            limit: ^quarter_size,
            select: %{confidence: t.confidence, text_length: fragment("length(?)", t.text)}
          )

        quality_metrics =
          from(r in subquery(recent_transcriptions),
            select: %{
              avg_confidence: avg(r.confidence),
              avg_text_length: avg(r.text_length),
              count: count(r.confidence)
            }
          )
          |> Repo.one()

        avg_confidence = quality_metrics.avg_confidence || 0.0
        avg_text_length = quality_metrics.avg_text_length || 0.0

        cond do
          avg_confidence >= 0.8 and avg_text_length > 20 -> "excellent"
          avg_confidence > 0.7 and avg_text_length > 10 -> "good"
          avg_confidence > 0.7 -> "acceptable"
          true -> "needs_attention"
        end
    end
  end
end
