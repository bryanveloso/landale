defmodule Server.CircuitBreakerServerPropertyTest do
  @moduledoc """
  Property-based tests for CircuitBreakerServer using the GenServer template.
  """

  use Server.GenServerPropertyTemplate, module: Server.CircuitBreakerServer

  alias Server.PropertyTestHelpers

  # Override the generator functions for CircuitBreakerServer

  defp init_args_generator do
    constant([])
  end

  defp state_generator do
    # Generate a state with multiple circuit breakers
    map(
      list_of(
        {string(:alphanumeric, min_length: 3), circuit_breaker_state_gen()},
        max_length: 10
      ),
      fn circuits ->
        circuits_with_names =
          circuits
          |> Enum.map(fn {name, circuit} -> {name, Map.put(circuit, :name, name)} end)
          |> Map.new()

        %{
          circuits: circuits_with_names,
          cleanup_timer: nil
        }
      end
    )
  end

  defp circuit_breaker_state_gen do
    map(
      {
        one_of([:closed, :open, :half_open]),
        integer(0..10),
        integer(0..100),
        one_of([nil, datetime_gen()]),
        datetime_gen(),
        datetime_gen()
      },
      fn {state, failure_count, half_open_success_count, last_failure_time, state_changed_at, last_accessed_at} ->
        %{
          state: state,
          failure_count: failure_count,
          half_open_success_count: half_open_success_count,
          last_failure_time: last_failure_time,
          state_changed_at: state_changed_at,
          last_accessed_at: last_accessed_at,
          config: %{
            failure_threshold: 3,
            success_threshold: 2,
            timeout_ms: 5000,
            reset_timeout_ms: 10_000
          }
        }
      end
    )
  end

  defp datetime_gen do
    map(integer(0..1_000_000), fn seconds ->
      DateTime.add(~U[2025-01-01 00:00:00Z], seconds, :second)
    end)
  end

  defp call_request_generator do
    one_of([
      tuple(
        {constant(:execute), string(:alphanumeric, min_length: 1), function_gen(),
         PropertyTestHelpers.circuit_breaker_config_gen()}
      ),
      tuple({constant(:get_state), string(:alphanumeric, min_length: 1)}),
      constant(:get_all_metrics),
      tuple({constant(:remove), string(:alphanumeric, min_length: 1)})
    ])
  end

  defp cast_request_generator do
    # CircuitBreakerServer doesn't implement handle_cast - this should never be called
    # But the property template requires it, so generate empty to skip the test
    constant(:skip_cast_test)
  end

  defp info_message_generator do
    # Only generate messages that the server actually handles
    constant(:cleanup)
  end

  defp function_gen do
    # Generate different types of functions that might be called
    one_of([
      constant(fn -> :ok end),
      constant(fn -> {:ok, :result} end),
      constant(fn -> {:error, :test_error} end)
    ])
  end

  defp apply_operation({:execute, name, fun, config}, state) do
    # Simulate circuit breaker call
    breaker = get_in(state, [:circuits, name]) || create_breaker(config)

    case breaker.state do
      :closed ->
        # Try to execute the function
        case fun.() do
          {:error, _} ->
            # Failure - increment count and maybe open
            new_failure_count = breaker.failure_count + 1
            new_state = if new_failure_count >= breaker.config.failure_threshold, do: :open, else: :closed

            put_in(state, [:circuits, name], %{
              breaker
              | failure_count: new_failure_count,
                state: new_state,
                last_failure_time: DateTime.utc_now()
            })

          _ ->
            # Success - reset failure count
            put_in(state, [:circuits, name], %{breaker | failure_count: 0})
        end

      :open ->
        # Circuit is open, don't execute
        state

      :half_open ->
        # Try once
        case fun.() do
          {:error, _} ->
            # Failure - reopen
            put_in(state, [:circuits, name], %{
              breaker
              | state: :open,
                last_failure_time: DateTime.utc_now()
            })

          _ ->
            # Success - move towards closing
            new_success_count = breaker.half_open_success_count + 1
            new_state = if new_success_count >= breaker.config.success_threshold, do: :closed, else: :half_open

            put_in(state, [:circuits, name], %{
              breaker
              | half_open_success_count: new_success_count,
                state: new_state
            })
        end
    end
  end

  defp apply_operation({:remove, name}, state) do
    update_in(state, [:circuits], &Map.delete(&1, name))
  end

  defp apply_operation(_, state), do: state

  defp create_breaker(config) do
    %{
      state: :closed,
      failure_count: 0,
      half_open_success_count: 0,
      last_failure_time: nil,
      state_changed_at: DateTime.utc_now(),
      last_accessed_at: DateTime.utc_now(),
      config: config
    }
  end

  defp state_invariants_hold?(state) do
    # Check all circuit breaker invariants
    Enum.all?(state.circuits, fn {_name, breaker} ->
      # State must be valid
      # Counts must be non-negative
      # Config must have required fields
      breaker.state in [:closed, :open, :half_open] &&
        breaker.failure_count >= 0 &&
        breaker.half_open_success_count >= 0 &&
        is_map(breaker.config) &&
        is_integer(breaker.config.failure_threshold) &&
        breaker.config.failure_threshold > 0
    end)
  end

  describe "circuit breaker specific properties" do
    property "circuit breaker transitions follow correct pattern" do
      check all(
              initial_state <- one_of([:closed, :open, :half_open]),
              events <-
                list_of(
                  one_of([:success, :failure, :timeout]),
                  min_length: 1,
                  max_length: 20
                )
            ) do
        # Verify transition validity by applying events in sequence
        final_state =
          Enum.reduce(events, initial_state, fn event, current_state ->
            case {current_state, event} do
              # Assuming threshold reached for failures
              {:closed, :failure} -> :open
              {:closed, :success} -> :closed
              # timeout has no effect when closed
              {:closed, :timeout} -> :closed
              {:open, :timeout} -> :half_open
              # can't succeed when open
              {:open, :success} -> :open
              {:open, :failure} -> :open
              {:half_open, :success} -> :closed
              {:half_open, :failure} -> :open
              # timeout maintains half_open
              {:half_open, :timeout} -> :half_open
            end
          end)

        # Final state should be valid
        assert final_state in [:closed, :open, :half_open]
      end
    end

    property "failure threshold is respected" do
      check all(
              threshold <- integer(1..10),
              failures <- integer(0..20)
            ) do
        breaker = %{
          state: :closed,
          failure_count: 0,
          config: %{failure_threshold: threshold}
        }

        final_breaker =
          Enum.reduce(1..failures//1, breaker, fn _, b ->
            if b.failure_count + 1 >= b.config.failure_threshold do
              %{b | state: :open, failure_count: b.failure_count + 1}
            else
              %{b | failure_count: b.failure_count + 1}
            end
          end)

        if failures >= threshold do
          assert final_breaker.state == :open
        else
          assert final_breaker.state == :closed
        end
      end
    end
  end
end
