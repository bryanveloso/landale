defmodule Server.GenServerPropertyTemplate do
  @moduledoc """
  Template for property-based testing of GenServer modules.

  This module provides a reusable structure for testing GenServer
  state machines with StreamData, ensuring consistent testing patterns
  across the codebase.
  """

  defmacro __using__(opts) do
    module_under_test = Keyword.fetch!(opts, :module)

    quote do
      use ExUnit.Case, async: true
      use ExUnitProperties

      alias unquote(module_under_test)

      describe "GenServer lifecycle properties" do
        property "init/1 always returns a valid response" do
          check all(init_args <- init_args_generator()) do
            result = unquote(module_under_test).init(init_args)

            assert match?({:ok, _state}, result) or
                     match?({:ok, _state, _opts}, result) or
                     match?({:stop, _reason}, result)
          end
        end

        property "handle_call/3 always returns a valid response" do
          check all(
                  state <- state_generator(),
                  request <- call_request_generator()
                ) do
            from = {self(), make_ref()}
            result = unquote(module_under_test).handle_call(request, from, state)

            assert match?({:reply, _reply, _new_state}, result) or
                     match?({:reply, _reply, _new_state, _opts}, result) or
                     match?({:noreply, _new_state}, result) or
                     match?({:noreply, _new_state, _opts}, result) or
                     match?({:stop, _reason, _reply, _new_state}, result) or
                     match?({:stop, _reason, _new_state}, result)
          end
        end

        property "handle_cast/2 always returns a valid response" do
          check all(
                  state <- state_generator(),
                  request <- cast_request_generator()
                ) do
            result = unquote(module_under_test).handle_cast(request, state)

            assert match?({:noreply, _new_state}, result) or
                     match?({:noreply, _new_state, _opts}, result) or
                     match?({:stop, _reason, _new_state}, result)
          end
        end

        property "handle_info/2 always returns a valid response" do
          check all(
                  state <- state_generator(),
                  message <- info_message_generator()
                ) do
            result = unquote(module_under_test).handle_info(message, state)

            assert match?({:noreply, _new_state}, result) or
                     match?({:noreply, _new_state, _opts}, result) or
                     match?({:stop, _reason, _new_state}, result)
          end
        end
      end

      describe "State invariant properties" do
        property "state transitions maintain invariants" do
          check all(
                  initial_state <- state_generator(),
                  operations <- list_of(operation_generator(), min_length: 1, max_length: 50)
                ) do
            final_state =
              Enum.reduce(operations, initial_state, fn operation, state ->
                new_state = apply_operation(operation, state)

                # Check invariants after each operation
                assert state_invariants_hold?(new_state)

                new_state
              end)

            # Final state should also maintain invariants
            assert state_invariants_hold?(final_state)
          end
        end

        property "concurrent operations maintain consistency" do
          check all(
                  initial_state <- state_generator(),
                  operation_groups <-
                    list_of(
                      list_of(operation_generator(), min_length: 1, max_length: 5),
                      min_length: 1,
                      max_length: 10
                    )
                ) do
            # Simulate concurrent operations
            results =
              Enum.map(operation_groups, fn operations ->
                # Each group represents operations that might happen concurrently
                Enum.reduce(operations, initial_state, &apply_operation/2)
              end)

            # All results should maintain invariants
            for state <- results do
              assert state_invariants_hold?(state)
            end
          end
        end
      end

      # Override these functions in your test module

      defp init_args_generator do
        # Default generator - override in your test
        one_of([
          constant([]),
          map_of(atom(:alphanumeric), term())
        ])
      end

      defp state_generator do
        # Default generator - override in your test
        map_of(atom(:alphanumeric), term())
      end

      defp call_request_generator do
        # Default generator - override in your test
        one_of([
          constant(:get_state),
          tuple({constant(:request), term()})
        ])
      end

      defp cast_request_generator do
        # Default generator - override in your test
        one_of([
          constant(:stop),
          tuple({constant(:update), term()})
        ])
      end

      defp info_message_generator do
        # Default generator - override in your test
        one_of([
          constant(:timeout),
          tuple({constant(:event), term()})
        ])
      end

      defp operation_generator do
        # Default generator - override in your test
        one_of([
          call_request_generator(),
          cast_request_generator(),
          info_message_generator()
        ])
      end

      defp apply_operation(operation, state) do
        # Default implementation - override in your test
        # This simulates how an operation would change the state
        state
      end

      defp state_invariants_hold?(state) do
        # Default implementation - override in your test
        # Check that your state maintains its invariants
        is_map(state)
      end

      defoverridable init_args_generator: 0,
                     state_generator: 0,
                     call_request_generator: 0,
                     cast_request_generator: 0,
                     info_message_generator: 0,
                     operation_generator: 0,
                     apply_operation: 2,
                     state_invariants_hold?: 1
    end
  end
end
