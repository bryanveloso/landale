defmodule Server.Transcription.ValidationTest do
  use ExUnit.Case, async: true
  alias Server.Transcription.Validation

  describe "validate/1" do
    test "validates a complete valid payload" do
      payload = %{
        "timestamp" => "2024-01-01T00:00:00Z",
        "duration" => 1.5,
        "text" => "Hello world",
        "source_id" => "phononmaser",
        "stream_session_id" => "stream_2024_01_01",
        "confidence" => 0.95,
        "metadata" => %{"language" => "en"}
      }

      assert {:ok, validated} = Validation.validate(payload)
      assert validated.timestamp == ~U[2024-01-01 00:00:00Z]
      assert validated.duration == 1.5
      assert validated.text == "Hello world"
      assert validated.source_id == "phononmaser"
      assert validated.stream_session_id == "stream_2024_01_01"
      assert validated.confidence == 0.95
      assert validated.metadata == %{"language" => "en"}
    end

    test "validates minimal valid payload" do
      payload = %{
        "timestamp" => "2024-01-01T00:00:00Z",
        "duration" => 1.5,
        "text" => "Hello"
      }

      assert {:ok, validated} = Validation.validate(payload)
      assert validated.timestamp == ~U[2024-01-01 00:00:00Z]
      assert validated.duration == 1.5
      assert validated.text == "Hello"
    end

    test "accepts atom keys" do
      payload = %{
        timestamp: "2024-01-01T00:00:00Z",
        duration: 1.5,
        text: "Hello"
      }

      assert {:ok, _validated} = Validation.validate(payload)
    end

    test "accepts DateTime struct for timestamp" do
      now = DateTime.utc_now()

      payload = %{
        timestamp: now,
        duration: 1.5,
        text: "Hello"
      }

      assert {:ok, validated} = Validation.validate(payload)
      assert validated.timestamp == now
    end

    test "rejects missing required fields" do
      assert {:error, errors} = Validation.validate(%{})
      assert errors.timestamp == ["is required"]
      assert errors.duration == ["is required"]
      assert errors.text == ["is required"]
    end

    test "rejects empty text" do
      payload = %{
        "timestamp" => "2024-01-01T00:00:00Z",
        "duration" => 1.5,
        "text" => ""
      }

      assert {:error, errors} = Validation.validate(payload)
      assert errors.text == ["is required"]
    end

    test "rejects invalid timestamp format" do
      payload = %{
        "timestamp" => "not-a-timestamp",
        "duration" => 1.5,
        "text" => "Hello"
      }

      assert {:error, errors} = Validation.validate(payload)
      assert errors.timestamp == ["must be a valid ISO 8601 datetime"]
    end

    test "rejects non-numeric duration" do
      payload = %{
        "timestamp" => "2024-01-01T00:00:00Z",
        "duration" => "not-a-number",
        "text" => "Hello"
      }

      assert {:error, errors} = Validation.validate(payload)
      assert errors.duration == ["must be a valid number"]
    end

    test "rejects negative duration" do
      payload = %{
        "timestamp" => "2024-01-01T00:00:00Z",
        "duration" => -1.0,
        "text" => "Hello"
      }

      assert {:error, errors} = Validation.validate(payload)
      assert errors.duration == ["must be greater than 0"]
    end

    test "rejects zero duration" do
      payload = %{
        "timestamp" => "2024-01-01T00:00:00Z",
        "duration" => 0.0,
        "text" => "Hello"
      }

      assert {:error, errors} = Validation.validate(payload)
      assert errors.duration == ["must be greater than 0"]
    end

    test "rejects text that is too long" do
      long_text = String.duplicate("a", 10_001)

      payload = %{
        "timestamp" => "2024-01-01T00:00:00Z",
        "duration" => 1.5,
        "text" => long_text
      }

      assert {:error, errors} = Validation.validate(payload)
      assert errors.text == ["is too long (maximum is 10000 characters)"]
    end

    test "validates confidence between 0.0 and 1.0" do
      base_payload = %{
        "timestamp" => "2024-01-01T00:00:00Z",
        "duration" => 1.5,
        "text" => "Hello"
      }

      # Valid confidence values
      assert {:ok, _} = Validation.validate(Map.put(base_payload, "confidence", 0.0))
      assert {:ok, _} = Validation.validate(Map.put(base_payload, "confidence", 0.5))
      assert {:ok, _} = Validation.validate(Map.put(base_payload, "confidence", 1.0))

      # Invalid confidence values
      assert {:error, errors} = Validation.validate(Map.put(base_payload, "confidence", -0.1))
      assert errors.confidence == ["must be between 0.0 and 1.0"]

      assert {:error, errors} = Validation.validate(Map.put(base_payload, "confidence", 1.1))
      assert errors.confidence == ["must be between 0.0 and 1.0"]
    end

    test "accepts nil confidence" do
      payload = %{
        "timestamp" => "2024-01-01T00:00:00Z",
        "duration" => 1.5,
        "text" => "Hello",
        "confidence" => nil
      }

      assert {:ok, validated} = Validation.validate(payload)
      assert validated.confidence == nil
    end

    test "accepts string numbers for duration and confidence" do
      payload = %{
        "timestamp" => "2024-01-01T00:00:00Z",
        "duration" => "1.5",
        "text" => "Hello",
        "confidence" => "0.95"
      }

      assert {:ok, validated} = Validation.validate(payload)
      assert validated.duration == 1.5
      assert validated.confidence == 0.95
    end

    test "ignores unknown fields" do
      payload = %{
        "timestamp" => "2024-01-01T00:00:00Z",
        "duration" => 1.5,
        "text" => "Hello",
        "unknown_field" => "ignored"
      }

      assert {:ok, validated} = Validation.validate(payload)
      refute Map.has_key?(validated, :unknown_field)
    end

    test "validates metadata as map" do
      payload = %{
        "timestamp" => "2024-01-01T00:00:00Z",
        "duration" => 1.5,
        "text" => "Hello",
        "metadata" => "not-a-map"
      }

      assert {:error, errors} = Validation.validate(payload)
      assert errors.metadata == ["must be a map"]
    end

    test "collects multiple errors" do
      payload = %{
        "timestamp" => "invalid",
        "duration" => -1.0,
        "text" => "",
        "confidence" => 2.0
      }

      assert {:error, errors} = Validation.validate(payload)
      assert errors.timestamp == ["must be a valid ISO 8601 datetime"]
      assert errors.duration == ["must be greater than 0"]
      assert errors.text == ["is required"]
      assert errors.confidence == ["must be between 0.0 and 1.0"]
    end
  end

  describe "format_errors/1" do
    test "formats error map into consistent structure" do
      errors = %{
        text: ["can't be blank", "is too short"],
        duration: ["is required"]
      }

      formatted = Validation.format_errors(errors)

      assert formatted == [
               %{field: "duration", messages: ["is required"]},
               %{field: "text", messages: ["can't be blank", "is too short"]}
             ]
    end

    test "sorts errors by field name" do
      errors = %{z: ["error"], a: ["error"], m: ["error"]}
      formatted = Validation.format_errors(errors)

      field_names = Enum.map(formatted, & &1.field)
      assert field_names == ["a", "m", "z"]
    end
  end
end
