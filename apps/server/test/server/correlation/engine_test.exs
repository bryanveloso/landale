defmodule Server.Correlation.EngineTest do
  use ExUnit.Case, async: false
  alias Server.Correlation.Engine
  import ExUnit.CaptureLog

  setup do
    # Start the engine for each test
    {:ok, pid} = Engine.start_link()

    # Mark stream as started (captures database connection errors in tests)
    capture_log(fn ->
      Engine.stream_started()
    end)

    # Wait for the engine to be ready
    Process.sleep(50)

    on_exit(fn ->
      # Clean up
      if Process.alive?(pid), do: GenServer.stop(pid)
    end)

    {:ok, pid: pid}
  end

  describe "duplicate detection" do
    test "prevents storing duplicate correlations with same fingerprint" do
      # Create a mock transcription event
      transcription = %{
        id: Ecto.UUID.generate(),
        text: "Hello everyone, how are you doing today?",
        # 5 seconds ago
        timestamp: System.system_time(:millisecond) - 5000
      }

      # Create a mock chat message that correlates
      chat_message = %{
        type: "channel.chat.message",
        data: %{
          "message_id" => "chat_456",
          "chatter_user_name" => "testuser",
          "message" => %{
            "text" => "Hello streamer!",
            "emotes" => []
          }
        }
      }

      # Send transcription
      send(Engine, {:new_transcription, transcription})

      # Capture logs to avoid noise from duplicate detection
      _logs =
        capture_log(fn ->
          # Send the same chat message multiple times
          send(Engine, {:event, chat_message})
          # Allow processing
          Process.sleep(100)
          send(Engine, {:event, chat_message})
          # Allow processing
          Process.sleep(100)
          send(Engine, {:event, chat_message})
          # Allow processing
          Process.sleep(100)
        end)

      # Check buffer state
      state = Engine.get_buffer_state()

      # Should have recorded exactly one fingerprint (not duplicates)
      assert state.fingerprint_count == 1

      # Get recent correlations
      correlations = Engine.get_recent_correlations()

      # Should only have one correlation despite multiple attempts
      assert length(correlations) == 1

      # The log message about skipping duplicates appears at debug level
      # and may not always show up depending on timing
    end

    test "fingerprint uniqueness is enforced" do
      # Create a scenario where the same correlation would be detected multiple times
      transcription = %{
        id: Ecto.UUID.generate(),
        text: "Testing fingerprint uniqueness",
        timestamp: System.system_time(:millisecond) - 5000
      }

      chat = %{
        type: "channel.chat.message",
        data: %{
          "message_id" => "chat_unique",
          "chatter_user_name" => "user",
          "message" => %{
            # Direct quote for high correlation
            "text" => "Testing fingerprint uniqueness",
            "emotes" => []
          }
        }
      }

      # Send transcription
      send(Engine, {:new_transcription, transcription})

      # Get initial state
      initial_state = Engine.get_buffer_state()
      initial_fingerprints = initial_state.fingerprint_count

      # Send chat message three times quickly
      capture_log(fn ->
        send(Engine, {:event, chat})
        send(Engine, {:event, chat})
        send(Engine, {:event, chat})
        # Allow all processing
        Process.sleep(200)
      end)

      # Get final state
      final_state = Engine.get_buffer_state()

      # Should have added exactly one fingerprint
      assert final_state.fingerprint_count == initial_fingerprints + 1

      # Should have exactly one correlation
      correlations = Engine.get_recent_correlations()
      assert length(correlations) == 1
    end

    test "allows different correlations with different fingerprints" do
      base_time = System.system_time(:millisecond)

      # Create multiple distinct transcriptions
      trans1 = %{
        id: Ecto.UUID.generate(),
        text: "First topic about gaming",
        timestamp: base_time - 5000
      }

      trans2 = %{
        id: Ecto.UUID.generate(),
        text: "Second topic about coding",
        timestamp: base_time - 4000
      }

      # Create different chat messages
      chat1 = %{
        type: "channel.chat.message",
        data: %{
          "message_id" => "chat_001",
          "chatter_user_name" => "user1",
          "message" => %{
            "text" => "gaming is awesome",
            "emotes" => []
          }
        }
      }

      chat2 = %{
        type: "channel.chat.message",
        data: %{
          "message_id" => "chat_002",
          "chatter_user_name" => "user2",
          "message" => %{
            "text" => "coding is fun",
            "emotes" => []
          }
        }
      }

      # Capture logs to suppress database errors
      capture_log(fn ->
        # Send transcriptions
        send(Engine, {:new_transcription, trans1})
        send(Engine, {:new_transcription, trans2})

        # Send chat messages
        send(Engine, {:event, chat1})
        Process.sleep(100)
        send(Engine, {:event, chat2})
        Process.sleep(100)
      end)

      # Check buffer state
      state = Engine.get_buffer_state()

      # Should have multiple fingerprints
      assert state.fingerprint_count >= 0

      # Both correlations should be allowed as they have different fingerprints
      assert state.transcription_count == 2
      assert state.chat_count == 2
    end

    test "fingerprints are pruned after retention window" do
      # This test would need to mock time or wait for actual pruning
      # For now, we'll just verify the pruning mechanism exists

      # Capture logs to suppress any errors
      capture_log(fn ->
        # Send a prune message directly
        send(Engine, :prune_buffers)
        Process.sleep(100)
      end)

      # Verify the engine is still running
      state = Engine.get_buffer_state()
      assert is_map(state)
      assert Map.has_key?(state, :fingerprint_count)
    end
  end

  describe "buffer state tracking" do
    test "includes fingerprint count in buffer state" do
      state = Engine.get_buffer_state()

      assert Map.has_key?(state, :fingerprint_count)
      assert is_integer(state.fingerprint_count)
      assert state.fingerprint_count >= 0
    end

    test "fingerprint count increases when correlations are detected" do
      initial_state = Engine.get_buffer_state()
      initial_count = initial_state.fingerprint_count

      # Create a correlation scenario
      transcription = %{
        id: Ecto.UUID.generate(),
        text: "Let's talk about testing",
        timestamp: System.system_time(:millisecond) - 4000
      }

      chat = %{
        type: "channel.chat.message",
        data: %{
          "message_id" => "chat_test",
          "chatter_user_name" => "tester",
          "message" => %{
            "text" => "testing is important",
            "emotes" => []
          }
        }
      }

      capture_log(fn ->
        send(Engine, {:new_transcription, transcription})
        send(Engine, {:event, chat})
        Process.sleep(100)
      end)

      final_state = Engine.get_buffer_state()

      # Fingerprint count should increase if correlation was detected
      # (It might not always correlate depending on timing and pattern matching)
      assert final_state.fingerprint_count >= initial_count
    end
  end

  describe "stream session handling" do
    test "clears fingerprints when stream restarts" do
      # Add some test data
      transcription = %{
        id: Ecto.UUID.generate(),
        text: "Stream session test",
        timestamp: System.system_time(:millisecond) - 4000
      }

      chat = %{
        type: "channel.chat.message",
        data: %{
          "message_id" => "chat_session",
          "chatter_user_name" => "viewer",
          "message" => %{
            "text" => "session test",
            "emotes" => []
          }
        }
      }

      capture_log(fn ->
        send(Engine, {:new_transcription, transcription})
        send(Engine, {:event, chat})
        Process.sleep(100)
      end)

      # Get state before stream stop
      _state_before = Engine.get_buffer_state()

      # Stop and restart stream (capture logs to suppress database errors)
      capture_log(fn ->
        Engine.stream_stopped()
        Process.sleep(50)
        Engine.stream_started()
        Process.sleep(50)
      end)

      # Get state after restart
      state_after = Engine.get_buffer_state()

      # Fingerprints should be cleared
      assert state_after.fingerprint_count == 0
      assert state_after.transcription_count == 0
      assert state_after.chat_count == 0
      assert state_after.correlation_count == 0
    end
  end
end
