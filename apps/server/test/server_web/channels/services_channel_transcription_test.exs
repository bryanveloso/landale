defmodule ServerWeb.ServicesChannelTranscriptionTest do
  use ServerWeb.ChannelCase, async: true

  alias ServerWeb.ServicesChannel

  describe "telemetry with transcription analytics" do
    test "get_telemetry includes transcription analytics data" do
      {:ok, _, socket} =
        socket(ServerWeb.UserSocket, "user_id", %{some: :assign})
        |> subscribe_and_join(ServicesChannel, "dashboard:services")

      _ref = push(socket, "get_telemetry", %{})

      # The channel sends telemetry_update as a push, not a reply
      assert_push "telemetry_update", telemetry_data

      # Verify basic telemetry structure
      assert Map.has_key?(telemetry_data, :services)
      assert Map.has_key?(telemetry_data, :system)
      assert Map.has_key?(telemetry_data, :overlays)

      # Verify transcription analytics is included
      assert Map.has_key?(telemetry_data, :transcription)

      transcription_data = telemetry_data[:transcription]

      # Verify analytics structure
      assert Map.has_key?(transcription_data, :total_transcriptions_24h)
      assert Map.has_key?(transcription_data, :confidence)
      assert Map.has_key?(transcription_data, :duration)
      assert Map.has_key?(transcription_data, :trends)
      assert Map.has_key?(transcription_data, :timestamp)

      # Verify confidence structure
      confidence = transcription_data[:confidence]
      assert Map.has_key?(confidence, :average)
      assert Map.has_key?(confidence, :min)
      assert Map.has_key?(confidence, :max)
      assert Map.has_key?(confidence, :distribution)

      # Verify trends structure
      trends = transcription_data[:trends]
      assert Map.has_key?(trends, :confidence_trend)
      assert Map.has_key?(trends, :hourly_volume)
      assert Map.has_key?(trends, :quality_trend)
    end
  end
end
