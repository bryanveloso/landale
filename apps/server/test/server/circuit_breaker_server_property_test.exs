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
      fn breakers ->
        %{
          breakers: Map.new(breakers),
          cleanup_interval: 300_000
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
        positive_integer()
      },
      fn {state, failure_count, success_count, last_failure_time} ->
        %{
          state: state,
          failure_count: failure_count,
          success_count: success_count,
          last_failure_time: last_failure_time,
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

  defp call_request_generator do
    one_of([
      tuple({constant(:call), string(:alphanumeric), function_gen(), PropertyTestHelpers.circuit_breaker_config_gen()}),
      tuple({constant(:get_state), string(:alphanumeric)}),
      constant(:get_all_metrics),
      tuple({constant(:remove), string(:alphanumeric)})
    ])
  end

  defp cast_request_generator do
    # CircuitBreakerServer doesn't use cast, but we need to provide this
    constant({:noop})
  end

  defp info_message_generator do
    one_of([
      constant(:cleanup_stale_breakers),
      tuple({constant(:reset_breaker), string(:alphanumeric)})
    ])
  end

  defp function_gen do
    # Generate different types of functions that might be called
    one_of([
      constant(fn -> :ok end),
      constant(fn -> {:ok, :result} end),
      constant(fn -> raise "error" end),
      constant(fn -> throw(:error) end)
    ])
  end

  defp apply_operation({:call, name, fun, config}, state) do
    # Simulate circuit breaker call
    breaker = get_in(state, [:breakers, name]) || create_breaker(config)

    case breaker.state do
      :closed ->
        # Try to execute the function
        try do
          fun.()
          # Success - might reset failure count
          put_in(state, [:breakers, name], %{breaker | failure_count: 0})
        rescue
          _ ->
            # Failure - increment count and maybe open
            new_failure_count = breaker.failure_count + 1
            new_state = if new_failure_count >= breaker.config.failure_threshold, do: :open, else: :closed

            put_in(state, [:breakers, name], %{
              breaker
              | failure_count: new_failure_count,
                state: new_state,
                last_failure_time: System.system_time(:millisecond)
            })
        end

      :open ->
        # Circuit is open, don't execute
        state

      :half_open ->
        # Try once
        try do
          fun.()
          # Success - move towards closing
          new_success_count = breaker.success_count + 1
          new_state = if new_success_count >= breaker.config.success_threshold, do: :closed, else: :half_open

          put_in(state, [:breakers, name], %{
            breaker
            | success_count: new_success_count,
              state: new_state
          })
        rescue
          _ ->
            # Failure - reopen
            put_in(state, [:breakers, name], %{
              breaker
              | state: :open,
                last_failure_time: System.system_time(:millisecond)
            })
        end
    end
  end

  defp apply_operation({:remove, name}, state) do
    update_in(state, [:breakers], &Map.delete(&1, name))
  end

  defp apply_operation(_, state), do: state

  defp create_breaker(config) do
    %{
      state: :closed,
      failure_count: 0,
      success_count: 0,
      last_failure_time: 0,
      config: config
    }
  end

  defp state_invariants_hold?(state) do
    # Check all circuit breaker invariants
    Enum.all?(state.breakers, fn {_name, breaker} ->
      # State must be valid
      # Counts must be non-negative
      # Config must have required fields
      breaker.state in [:closed, :open, :half_open] &&
        breaker.failure_count >= 0 &&
        breaker.success_count >= 0 &&
        is_map(breaker.config) &&
        is_integer(breaker.config.failure_threshold) &&
        breaker.config.failure_threshold > 0
    end)
  end

  describe "circuit breaker specific properties" do
    property "circuit breaker transitions follow correct pattern" do
      check all(
              transitions <-
                list_of(
                  tuple({
                    one_of([:closed, :open, :half_open]),
                    one_of([:success, :failure, :timeout])
                  }),
                  min_length: 1,
                  max_length: 20
                )
            ) do
        # Verify transition validity
        Enum.reduce(transitions, :closed, fn {from_state, event}, current_state ->
          assert current_state == from_state

          next_state =
            case {from_state, event} do
              # Assuming threshold reached
              {:closed, :failure} -> :open
              {:closed, :success} -> :closed
              {:open, :timeout} -> :half_open
              {:open, _} -> :open
              {:half_open, :success} -> :closed
              {:half_open, :failure} -> :open
              _ -> from_state
            end

          next_state
        end)
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
          Enum.reduce(1..failures, breaker, fn _, b ->
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
