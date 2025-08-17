defmodule Server.LiveCorrelationTest do
  @moduledoc """
  Live data testing script for the correlation engine.

  Run with: mix run test/live_correlation_test.exs

  This script simulates live streaming conditions with:
  - Realistic transcription segments from Phononmaser
  - Mock chat messages with varying patterns
  - Performance monitoring and metrics collection
  """

  alias Server.Correlation.Engine

  require Logger

  # 1 minute test
  @test_duration_ms 60_000
  # 0.5 seconds (Phononmaser rate)
  @transcription_interval 500
  # Average chat message every 2 seconds
  @chat_message_rate 2_000
  # 10% chance of chat burst
  @burst_probability 0.1

  def run do
    Logger.info("Starting live correlation engine test for #{@test_duration_ms / 1000} seconds")

    # Start correlation engine if not already running
    ensure_engine_started()

    # Mark stream as started
    Engine.stream_started()
    Process.sleep(100)

    # Start metrics collection
    metrics_pid = spawn_link(fn -> collect_metrics() end)

    # Start transcription simulator
    trans_pid = spawn_link(fn -> simulate_transcriptions() end)

    # Start chat simulator
    chat_pid = spawn_link(fn -> simulate_chat() end)

    # Run for test duration
    Process.sleep(@test_duration_ms)

    # Stop simulators
    Process.exit(trans_pid, :normal)
    Process.exit(chat_pid, :normal)

    # Collect final metrics
    send(metrics_pid, :report)
    Process.sleep(1000)
    Process.exit(metrics_pid, :normal)

    # Mark stream as stopped
    Engine.stream_stopped()

    Logger.info("Live correlation test completed")
  end

  defp ensure_engine_started do
    case Process.whereis(Server.Correlation.Engine) do
      nil ->
        {:ok, _pid} = Engine.start_link()
        Logger.info("Started correlation engine")

      pid ->
        Logger.info("Correlation engine already running: #{inspect(pid)}")
    end
  end

  defp simulate_transcriptions do
    transcription_segments = [
      "Hello everyone welcome to the stream",
      "Today we're going to be playing some games",
      "Let me know in chat what you want to see",
      "I've been working on this project all week",
      "The code is getting pretty complex now",
      "But I think we're making good progress",
      "Oh wow look at that someone just subscribed",
      "Thank you so much for the support",
      "Let's take a quick break and read chat",
      "What do you all think about this approach",
      "I see some good suggestions in chat",
      "Yeah that's a great point actually",
      "Let me show you what I mean",
      "This is the tricky part right here",
      "We need to be careful with memory usage",
      "Performance is really important for this",
      "I'm going to refactor this section",
      "Does anyone have questions so far",
      "Feel free to ask anything in chat",
      "We're almost done with this feature"
    ]

    Stream.cycle(transcription_segments)
    |> Stream.with_index()
    |> Enum.each(fn {text, index} ->
      Process.sleep(@transcription_interval)

      transcription = %{
        id: Ecto.UUID.generate(),
        text: text,
        timestamp: System.system_time(:millisecond)
      }

      # Broadcast to Phoenix PubSub (Engine will receive via subscription)
      Phoenix.PubSub.broadcast(
        Server.PubSub,
        "transcription:live",
        {:new_transcription, transcription}
      )

      if rem(index, 10) == 0 do
        Logger.debug("Sent transcription #{index}: #{String.slice(text, 0, 30)}...")
      end
    end)
  end

  defp simulate_chat do
    chat_responses = [
      # Direct reactions
      {"Hello!", :greeting},
      {"hi streamer!", :greeting},
      {"GAMES PogChamp", :excitement},
      {"what games?", :question},
      {"show us the code!", :request},
      {"this is cool", :positive},
      {"complex indeed", :agreement},
      {"LULW", :emote},
      {"Pog", :emote},
      {"nice progress", :positive},
      {"Thanks for streaming!", :appreciation},
      {"great point", :agreement},
      {"memory leak?", :question},
      {"performance Kappa", :sarcasm},
      {"refactor everything!", :suggestion},
      {"no questions", :response},
      {"feature looks good", :positive},

      # Burst messages (spam)
      {"POG POG POG", :burst},
      {"LETS GOOO", :burst},
      {"🔥🔥🔥", :burst},

      # Contextual responses
      {"yeah the code is getting complex", :echo},
      {"welcome to the stream everyone", :echo},
      {"good progress today", :echo},
      {"memory usage is important", :echo},
      {"what about testing?", :technical},
      {"use TypeScript", :suggestion},
      {"have you tried Rust?", :suggestion}
    ]

    users = [
      "viewer1",
      "chatter42",
      "streamfan",
      "codemaster",
      "lurker99",
      "subscriber1",
      "mod_user",
      "vip_user",
      "regular_viewer",
      "new_user"
    ]

    message_id = 0

    Stream.repeatedly(fn ->
      Process.sleep(calculate_chat_delay())

      # Occasionally generate burst
      messages =
        if :rand.uniform() < @burst_probability do
          # Burst of 3-7 messages
          count = 3 + :rand.uniform(4)

          for _ <- 1..count do
            {msg, _type} = Enum.random(chat_responses)
            user = Enum.random(users)
            create_chat_event(message_id, user, msg)
          end
        else
          # Single message
          {msg, _type} = Enum.random(chat_responses)
          user = Enum.random(users)
          [create_chat_event(message_id, user, msg)]
        end

      # Send all messages via PubSub (Engine and ContentAggregator will receive)
      Enum.each(messages, fn event ->
        # Broadcast in the expected format
        Phoenix.PubSub.broadcast(Server.PubSub, "events", {:event, event})
      end)

      message_id + length(messages)
    end)
    # Safety limit
    |> Stream.take_while(fn id -> id < 1000 end)
    |> Stream.run()
  end

  defp calculate_chat_delay do
    # Variable delay with occasional bursts
    base_delay = @chat_message_rate
    variation = :rand.uniform(1000) - 500
    max(100, base_delay + variation)
  end

  defp create_chat_event(id, user, text) do
    %{
      type: "channel.chat.message",
      data: %{
        "message_id" => "chat_#{id}",
        "chatter_user_name" => user,
        "message" => %{
          "text" => text,
          "emotes" => detect_emotes(text)
        }
      }
    }
  end

  defp detect_emotes(text) do
    emote_patterns = ["Pog", "Kappa", "LULW", "PogChamp", "KEKW"]

    emote_patterns
    |> Enum.filter(&String.contains?(text, &1))
    |> Enum.map(fn emote ->
      %{"name" => emote, "id" => "emote_#{emote}"}
    end)
  end

  defp collect_metrics do
    # Initial delay
    Process.sleep(5000)

    Stream.repeatedly(fn ->
      receive do
        :report ->
          report_final_metrics()
          :stop
      after
        5000 ->
          report_metrics()
          :continue
      end
    end)
    |> Stream.take_while(&(&1 == :continue))
    |> Stream.run()
  end

  defp report_metrics do
    state = Engine.get_buffer_state()
    correlations = Engine.get_recent_correlations(5)

    Logger.info("""
    === Correlation Engine Metrics ===
    Buffers:
      Transcriptions: #{state.transcription_count}
      Chat messages: #{state.chat_count}
      Active correlations: #{state.correlation_count}
      Fingerprints tracked: #{state.fingerprint_count}

    Recent Correlations (top 5):
    #{format_correlations(correlations)}
    Memory:
      Process: #{process_memory_mb()} MB
      System: #{system_memory_mb()} MB
    """)
  end

  defp report_final_metrics do
    state = Engine.get_buffer_state()
    all_correlations = Engine.get_recent_correlations(100)

    # Group by pattern type
    by_pattern = Enum.group_by(all_correlations, & &1.pattern)

    pattern_stats =
      Enum.map(by_pattern, fn {pattern, corrs} ->
        avg_confidence =
          corrs
          |> Enum.map(& &1.confidence)
          |> Enum.sum()
          |> Kernel./(length(corrs))
          |> Float.round(2)

        "  #{pattern}: #{length(corrs)} correlations, avg confidence: #{avg_confidence}"
      end)

    Logger.info("""

    === FINAL TEST RESULTS ===
    Total Correlations Detected: #{length(all_correlations)}

    By Pattern Type:
    #{Enum.join(pattern_stats, "\n")}

    Confidence Distribution:
      High (>0.7): #{count_by_confidence(all_correlations, 0.7, 1.0)}
      Medium (0.5-0.7): #{count_by_confidence(all_correlations, 0.5, 0.7)}
      Low (<0.5): #{count_by_confidence(all_correlations, 0.0, 0.5)}

    Time Offset Stats:
      Min: #{min_offset(all_correlations)} ms
      Max: #{max_offset(all_correlations)} ms
      Avg: #{avg_offset(all_correlations)} ms

    Buffer Performance:
      Transcription buffer size: #{state.transcription_count}
      Chat buffer size: #{state.chat_count}
      Fingerprints tracked: #{state.fingerprint_count}

    System Performance:
      Final process memory: #{process_memory_mb()} MB
      Peak correlation count: #{state.correlation_count}
    """)
  end

  defp format_correlations([]), do: "  No correlations detected yet"

  defp format_correlations(correlations) do
    correlations
    |> Enum.map(fn corr ->
      "  [#{corr.pattern}] #{corr.confidence} - \"#{String.slice(corr.transcription || "", 0, 30)}...\" -> \"#{String.slice(corr.chat_message || "", 0, 30)}...\""
    end)
    |> Enum.join("\n")
  end

  defp count_by_confidence(correlations, min, max) do
    correlations
    |> Enum.filter(fn c -> c.confidence >= min and c.confidence < max end)
    |> length()
  end

  defp min_offset([]), do: 0

  defp min_offset(correlations) do
    correlations
    |> Enum.map(& &1.time_offset_ms)
    |> Enum.min()
  end

  defp max_offset([]), do: 0

  defp max_offset(correlations) do
    correlations
    |> Enum.map(& &1.time_offset_ms)
    |> Enum.max()
  end

  defp avg_offset([]), do: 0

  defp avg_offset(correlations) do
    sum = correlations |> Enum.map(& &1.time_offset_ms) |> Enum.sum()
    Float.round(sum / length(correlations), 1)
  end

  defp process_memory_mb do
    {:memory, memory} = Process.info(self(), :memory)
    Float.round(memory / 1_048_576, 2)
  end

  defp system_memory_mb do
    Float.round(:erlang.memory(:total) / 1_048_576, 2)
  end
end

# Run the test
Server.LiveCorrelationTest.run()
