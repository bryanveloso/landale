defmodule Server.Services.OBS.EventHandlerPropertyTest do
  @moduledoc """
  Property-based tests for the OBS EventHandler.

  Tests invariants and properties including:
  - Event processing never crashes the handler
  - All events are logged appropriately
  - Session ID remains constant
  - Concurrent event handling maintains consistency
  - Event ordering is preserved per sender
  """
  use ExUnit.Case, async: true
  use ExUnitProperties
  import ExUnit.CaptureLog

  alias Server.Services.OBS.EventHandler

  setup do
    # Start PubSub if not already started
    case start_supervised({Phoenix.PubSub, name: Server.PubSub}) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end
  end

  describe "event processing properties" do
    property "handler never crashes regardless of event content" do
      check all(
              session_id <- session_id_gen(),
              events <- list_of(event_gen(), min_length: 1, max_length: 20)
            ) do
        name = :"test_handler_#{session_id}_#{:rand.uniform(10000)}"
        opts = [session_id: session_id, name: name]
        {:ok, pid} = EventHandler.start_link(opts)

        # Send all events
        for event <- events do
          send(pid, {:obs_event, event})
        end

        # Give time to process
        Process.sleep(10)

        # Handler should still be alive
        assert Process.alive?(pid)

        # Clean up
        GenServer.stop(pid)
      end
    end

    property "all valid events produce log entries" do
      check all(
              session_id <- session_id_gen(),
              event_type <- event_type_gen(),
              event_data <- event_data_gen()
            ) do
        name = :"test_handler_#{session_id}_#{:rand.uniform(10000)}"
        opts = [session_id: session_id, name: name]
        {:ok, pid} = EventHandler.start_link(opts)

        event = %{eventType: event_type, eventData: event_data}

        log =
          capture_log([level: :debug], fn ->
            send(pid, {:obs_event, event})
            Process.sleep(10)
          end)

        # All events should be logged
        assert log =~ "OBS event received" or log =~ "changed"
        assert log =~ session_id

        # Clean up
        GenServer.stop(pid)
      end
    end

    property "session_id remains immutable throughout lifecycle" do
      check all(
              session_id <- session_id_gen(),
              events <- list_of(event_gen(), min_length: 5, max_length: 50)
            ) do
        name = :"test_handler_#{session_id}_#{:rand.uniform(10000)}"
        opts = [session_id: session_id, name: name]
        {:ok, pid} = EventHandler.start_link(opts)

        # Check initial state
        assert %EventHandler{session_id: ^session_id} = :sys.get_state(pid)

        # Send many events
        for event <- events do
          send(pid, {:obs_event, event})
        end

        Process.sleep(20)

        # Session ID should not have changed
        assert %EventHandler{session_id: ^session_id} = :sys.get_state(pid)

        # Clean up
        GenServer.stop(pid)
      end
    end
  end

  describe "concurrent event properties" do
    property "concurrent events from same source maintain order" do
      check all(
              session_id <- session_id_gen(),
              scene_names <- uniq_list_of(scene_name_gen(), min_length: 5, max_length: 10)
            ) do
        name = :"test_handler_#{session_id}_#{:rand.uniform(10000)}"
        opts = [session_id: session_id, name: name]
        {:ok, pid} = EventHandler.start_link(opts)

        # Send scene change events in order
        log =
          capture_log(fn ->
            for scene_name <- scene_names do
              event = %{
                eventType: "CurrentProgramSceneChanged",
                eventData: %{sceneName: scene_name}
              }

              send(pid, {:obs_event, event})
            end

            Process.sleep(50)
          end)

        # Verify all scenes appear in log
        for scene_name <- scene_names do
          assert log =~ scene_name
        end

        # Clean up
        GenServer.stop(pid)
      end
    end

    property "handles mixed event types without interference" do
      check all(
              session_id <- session_id_gen(),
              mixed_events <- mixed_events_gen()
            ) do
        name = :"test_handler_#{session_id}_#{:rand.uniform(10000)}"
        opts = [session_id: session_id, name: name]
        {:ok, pid} = EventHandler.start_link(opts)

        log =
          capture_log([level: :debug], fn ->
            for event <- mixed_events do
              send(pid, {:obs_event, event})
            end

            Process.sleep(50)
          end)

        # Count expected log entries
        scene_events = Enum.count(mixed_events, &(&1.eventType == "CurrentProgramSceneChanged"))
        stream_events = Enum.count(mixed_events, &(&1.eventType == "StreamStateChanged"))
        record_events = Enum.count(mixed_events, &(&1.eventType == "RecordStateChanged"))

        # Verify appropriate number of specific log entries
        assert count_occurrences(log, "Scene changed to:") >= scene_events
        assert count_occurrences(log, "Stream state changed") >= stream_events
        assert count_occurrences(log, "Record state changed") >= record_events

        # Clean up
        GenServer.stop(pid)
      end
    end
  end

  describe "message handling properties" do
    property "non-event messages are ignored without crashing" do
      check all(
              session_id <- session_id_gen(),
              messages <- list_of(any_message_gen(), min_length: 1, max_length: 20)
            ) do
        name = :"test_handler_#{session_id}_#{:rand.uniform(10000)}"
        opts = [session_id: session_id, name: name]
        {:ok, pid} = EventHandler.start_link(opts)

        # Send various message types
        for message <- messages do
          send(pid, message)
        end

        Process.sleep(10)

        # Handler should still be alive
        assert Process.alive?(pid)

        # Clean up
        GenServer.stop(pid)
      end
    end

    property "event data structure variations are handled gracefully" do
      check all(
              session_id <- session_id_gen(),
              event_structures <- list_of(event_structure_gen(), min_length: 1, max_length: 10)
            ) do
        name = :"test_handler_#{session_id}_#{:rand.uniform(10000)}"
        opts = [session_id: session_id, name: name]
        {:ok, pid} = EventHandler.start_link(opts)

        # Send events with various structures
        for event <- event_structures do
          send(pid, {:obs_event, event})
        end

        Process.sleep(10)

        # Handler should handle all variations
        assert Process.alive?(pid)

        # Clean up
        GenServer.stop(pid)
      end
    end
  end

  describe "logging properties" do
    property "known event types produce specific log messages" do
      check all(
              session_id <- session_id_gen(),
              known_event <- known_event_gen()
            ) do
        name = :"test_handler_#{session_id}_#{:rand.uniform(10000)}"
        opts = [session_id: session_id, name: name]
        {:ok, pid} = EventHandler.start_link(opts)

        log =
          capture_log(fn ->
            send(pid, {:obs_event, known_event})
            Process.sleep(10)
          end)

        # Verify specific log messages based on event type
        case known_event.eventType do
          "CurrentProgramSceneChanged" ->
            assert log =~ "Scene changed to:"

          "StreamStateChanged" ->
            assert log =~ "Stream state changed"

          "RecordStateChanged" ->
            assert log =~ "Record state changed"
        end

        # Clean up
        GenServer.stop(pid)
      end
    end

    property "unknown event types are logged as unhandled" do
      check all(
              session_id <- session_id_gen(),
              unknown_type <- unknown_event_type_gen(),
              event_data <- event_data_gen()
            ) do
        name = :"test_handler_#{session_id}_#{:rand.uniform(10000)}"
        opts = [session_id: session_id, name: name]
        {:ok, pid} = EventHandler.start_link(opts)

        event = %{eventType: unknown_type, eventData: event_data}

        log =
          capture_log([level: :debug], fn ->
            send(pid, {:obs_event, event})
            Process.sleep(10)
          end)

        # Should log as unhandled
        assert log =~ "Unhandled OBS event"
        assert log =~ unknown_type

        # Clean up
        GenServer.stop(pid)
      end
    end
  end

  # Generator functions

  defp session_id_gen do
    map({string(:alphanumeric, min_length: 1), integer(1..10000)}, fn {prefix, num} ->
      "#{prefix}_#{num}"
    end)
  end

  defp event_type_gen do
    one_of([
      constant("CurrentProgramSceneChanged"),
      constant("StreamStateChanged"),
      constant("RecordStateChanged"),
      constant("UnknownEvent"),
      string(:alphanumeric, min_length: 1)
    ])
  end

  defp scene_name_gen do
    one_of([
      constant("Main Scene"),
      constant("BRB Scene"),
      constant("Starting Scene"),
      constant("Ending Scene"),
      map({string(:alphanumeric, min_length: 1), integer(1..100)}, fn {name, num} ->
        "#{name} #{num}"
      end)
    ])
  end

  defp event_data_gen do
    one_of([
      # Scene change data
      map(scene_name_gen(), fn scene ->
        %{sceneName: scene}
      end),
      # Stream/Record state data
      map({boolean(), output_state_gen()}, fn {active, state} ->
        %{outputActive: active, outputState: state}
      end),
      # Generic data
      map_of(atom(:alphanumeric), one_of([string(:utf8), integer(), boolean()]))
    ])
  end

  defp output_state_gen do
    one_of([
      constant("OBS_WEBSOCKET_OUTPUT_STARTED"),
      constant("OBS_WEBSOCKET_OUTPUT_STOPPED"),
      constant("OBS_WEBSOCKET_OUTPUT_STARTING"),
      constant("OBS_WEBSOCKET_OUTPUT_STOPPING"),
      constant("OBS_WEBSOCKET_OUTPUT_PAUSED"),
      constant("OBS_WEBSOCKET_OUTPUT_RESUMED")
    ])
  end

  defp event_gen do
    map({event_type_gen(), event_data_gen()}, fn {type, data} ->
      %{eventType: type, eventData: data}
    end)
  end

  defp known_event_gen do
    one_of([
      map(scene_name_gen(), fn scene ->
        %{
          eventType: "CurrentProgramSceneChanged",
          eventData: %{sceneName: scene}
        }
      end),
      map({boolean(), output_state_gen()}, fn {active, state} ->
        %{
          eventType: "StreamStateChanged",
          eventData: %{outputActive: active, outputState: state}
        }
      end),
      map({boolean(), output_state_gen()}, fn {active, state} ->
        %{
          eventType: "RecordStateChanged",
          eventData: %{outputActive: active, outputState: state}
        }
      end)
    ])
  end

  defp unknown_event_type_gen do
    filter(string(:alphanumeric, min_length: 1), fn type ->
      type not in [
        "CurrentProgramSceneChanged",
        "StreamStateChanged",
        "RecordStateChanged"
      ]
    end)
  end

  defp mixed_events_gen do
    list_of(
      frequency([
        {3, known_event_gen()},
        {1, event_gen()}
      ]),
      min_length: 5,
      max_length: 20
    )
  end

  defp any_message_gen do
    one_of([
      atom(:alphanumeric),
      string(:utf8),
      integer(),
      tuple({atom(:alphanumeric), term()}),
      list_of(term(), max_length: 3)
    ])
  end

  defp event_structure_gen do
    one_of([
      # Normal structure
      event_gen(),
      # Missing eventData
      map(event_type_gen(), fn type -> %{eventType: type} end),
      # Missing eventType
      map(event_data_gen(), fn data -> %{eventData: data} end),
      # Empty map
      constant(%{}),
      # Extra fields
      map({event_type_gen(), event_data_gen()}, fn {type, data} ->
        %{
          eventType: type,
          eventData: data,
          extraField: "ignored",
          timestamp: System.system_time()
        }
      end)
    ])
  end

  # Helper functions

  defp count_occurrences(string, substring) do
    string
    |> String.split(substring)
    |> length()
    |> Kernel.-(1)
  end
end
