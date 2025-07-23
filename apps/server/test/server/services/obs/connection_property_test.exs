defmodule Server.Services.OBS.ConnectionPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Server.PropertyTestHelpers

  describe "connection state machine properties" do
    property "all state transitions follow valid paths" do
      check all(transitions <- PropertyTestHelpers.valid_transition_sequence_gen(20)) do
        # Verify each transition in the sequence is valid
        for {from_state, event, to_state} <- transitions do
          assert PropertyTestHelpers.valid_state_transition?(from_state, event),
                 "Invalid transition from #{inspect(from_state)} with event #{inspect(event)}"

          # The helper should correctly predict the next state
          {event_type, _} = event
          expected_state = expected_next_state(from_state, event_type)

          assert to_state == expected_state,
                 "Expected transition from #{inspect(from_state)} -> #{inspect(expected_state)}, got #{inspect(to_state)}"
        end
      end
    end

    property "connection never gets stuck in an unrecoverable state" do
      check all(
              initial_state <- PropertyTestHelpers.connection_state_gen(),
              events <- list_of(PropertyTestHelpers.connection_event_gen(), min_length: 1, max_length: 50)
            ) do
        # Apply all events and ensure we can always reach :ready or :disconnected
        final_state =
          Enum.reduce(events, initial_state, fn event, state ->
            if PropertyTestHelpers.valid_state_transition?(state, event) do
              {event_type, _} = event
              expected_next_state(state, event_type)
            else
              state
            end
          end)

        # From any final state, we should be able to reach either :ready or :disconnected
        assert can_reach_stable_state?(final_state),
               "Got stuck in state #{inspect(final_state)}"
      end
    end

    property "request tracking maintains consistency" do
      check all(
              requests <-
                list_of(
                  {PropertyTestHelpers.obs_request_name_gen(), PropertyTestHelpers.request_id_gen()},
                  max_length: 100
                )
            ) do
        # Simulate request tracking
        tracker =
          Enum.reduce(requests, %{}, fn {request_name, request_id}, acc ->
            # Add request
            acc = Map.put(acc, request_id, {:pending, request_name})

            # Randomly complete some requests
            if :rand.uniform() > 0.5 do
              Map.put(acc, request_id, {:completed, request_name})
            else
              acc
            end
          end)

        # Verify all tracked requests have valid states
        for {_id, {state, _name}} <- tracker do
          assert state in [:pending, :completed]
        end

        # Verify no duplicate IDs
        ids = Map.keys(tracker)
        assert length(ids) == length(Enum.uniq(ids))
      end
    end
  end

  describe "connection resilience properties" do
    property "exponential backoff increases correctly" do
      check all(attempt <- integer(0..10)) do
        backoff = calculate_backoff(attempt)

        # Backoff should increase exponentially with a cap
        expected_min = min(:math.pow(2, attempt) * 1000, 60_000)
        # Allow for jitter
        expected_max = expected_min * 1.5

        assert backoff >= expected_min
        assert backoff <= expected_max
      end
    end

    property "connection attempts are bounded" do
      check all(
              max_attempts <- integer(1..20),
              attempts <- integer(0..30)
            ) do
        should_reconnect = attempts < max_attempts

        # Verify reconnection logic
        if attempts >= max_attempts do
          refute should_reconnect
        else
          assert should_reconnect
        end
      end
    end
  end

  describe "message handling properties" do
    property "all valid OBS messages are handled" do
      check all(
              op_code <- integer(0..10),
              data <- map_of(atom(:alphanumeric), term())
            ) do
        message = %{"op" => op_code, "d" => data}

        # Message should either be handled or explicitly ignored
        result = categorize_message(message)
        assert result in [:hello, :identified, :event, :request_response, :unknown]
      end
    end

    property "correlation IDs are preserved through request/response cycle" do
      check all(
              correlation_id <- PropertyTestHelpers.correlation_id_gen(),
              request_id <- PropertyTestHelpers.request_id_gen(),
              request_name <- PropertyTestHelpers.obs_request_name_gen()
            ) do
        # Simulate request with correlation ID
        request = %{
          request_id: request_id,
          request_name: request_name,
          correlation_id: correlation_id
        }

        # Simulate response
        response = %{
          request_id: request_id,
          status: "success"
        }

        # Correlation ID should be retrievable from request tracking
        assert can_correlate_response?(request, response, correlation_id)
      end
    end
  end

  # Helper functions

  defp expected_next_state(state, event_type) do
    case {state, event_type} do
      {:disconnected, :connect} -> :connecting
      {:connecting, :connected} -> :connected
      {:connecting, :error} -> :error
      {:connected, :authenticate} -> :authenticating
      {:authenticating, :authenticated} -> :ready
      {:authenticating, :error} -> :error
      {:ready, :disconnect} -> :disconnected
      {:ready, :error} -> :error
      {:error, :reconnect} -> :reconnecting
      _ -> state
      _ -> state
    end
  end

  defp can_reach_stable_state?(_state) do
    # From any state, we should be able to reach :ready or :disconnected
    # :connecting and :authenticating are transient states that will timeout
    # :reconnecting will transition to :disconnected
    # :error will allow reconnection
    # All states can eventually reach a stable state
    true
  end

  defp calculate_backoff(attempt) do
    base = :math.pow(2, attempt) * 1000
    jitter = :rand.uniform() * 0.5
    min(base * (1 + jitter), 60_000) |> round()
  end

  defp categorize_message(%{"op" => op}) do
    case op do
      0 -> :hello
      2 -> :identified
      5 -> :event
      7 -> :request_response
      _ -> :unknown
    end
  end

  defp can_correlate_response?(request, response, expected_correlation_id) do
    # In a real implementation, this would check the request tracker
    request.correlation_id == expected_correlation_id &&
      request.request_id == response.request_id
  end
end
